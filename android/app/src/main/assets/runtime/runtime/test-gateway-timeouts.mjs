import assert from 'node:assert/strict';
import wsPackage from '../node_modules/ws/index.js';
import { GatewayConnection } from '../node_modules/@tencent-connect/qqbot-nodejs/dist/protocol/gateway/gateway-connection.js';

// ws 是 CommonJS 包，ESM 下只能通过 default 导入。
const { WebSocketServer } = wsPackage;

const silentLog = { info() {}, warn() {}, error() {}, debug() {} };
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** 起一个本地网关，`onSocket` 决定每个连接说什么话。 */
function startGateway(onSocket) {
  const wss = new WebSocketServer({ port: 0 });
  wss.on('connection', onSocket);
  return new Promise((resolve) => {
    wss.on('listening', () => resolve({ wss, url: `ws://127.0.0.1:${wss.address().port}` }));
  });
}

function makeConnection(url, overrides = {}) {
  const controller = new AbortController();
  const disconnects = [];
  const reads = [];
  const conn = new GatewayConnection({
    account: { accountId: 'test' },
    log: silentLog,
    abortSignal: controller.signal,
    getAccessToken: async () => 'access-token',
    getGatewayUrl: async () => url,
    // 重连要快，否则测试等太久
    reconnect: { maxAttempts: 5, delays: [10] },
    onDisconnected: (event) => disconnects.push(event),
    onReady: (data) => reads.push(data),
    ...overrides,
  });
  return { conn, disconnects, reads, abort: () => controller.abort() };
}

/** start() 在重连预算耗尽时会 reject；测试只关心回调，这里吞掉。 */
function safeStart(conn) {
  conn.start().catch(() => {});
}

const HELLO = (interval) => JSON.stringify({ op: 10, d: { heartbeat_interval: interval } });
const READY = JSON.stringify({ op: 0, t: 'READY', s: 1, d: { session_id: 'sess-1' } });

// ── 场景 1：HELLO 之后服务端不发 READY，必须由本地 READY 超时兜底 ──
{
  const gateway = await startGateway((socket) => socket.send(HELLO(60_000)));
  const { conn, disconnects, abort } = makeConnection(gateway.url, { readyTimeoutMs: 120 });
  // start() 在重连预算耗尽时会 reject，测试只关心回调，这里吞掉。
  safeStart(conn);
  await wait(400);
  assert.ok(disconnects.length > 0, 'READY 超时没有触发断开，连接会静默卡死');
  const first = disconnects[0];
  assert.equal(first.codeName, 'ready_timeout');
  assert.equal(first.codeSource, 'local', '本地判定不能冒充服务端关闭帧');
  assert.equal(first.willReconnect, true);
  abort();
  gateway.wss.close();
  await wait(20);
}

// ── 场景 2：收到 READY 之后服务端不再回心跳 ACK，必须识别半开连接 ──
{
  const gateway = await startGateway((socket) => {
    socket.send(HELLO(40));
    socket.send(READY);
    // 之后什么都不回：模拟 NAT 表项过期造成的半开连接
  });
  const { conn, disconnects, reads, abort } = makeConnection(gateway.url, { readyTimeoutMs: 5_000 });
  // start() 在重连预算耗尽时会 reject，测试只关心回调，这里吞掉。
  safeStart(conn);
  await wait(500);
  assert.equal(reads.length > 0, true, 'READY 没有被派发，场景 2 无法验证');
  const beatTimeout = disconnects.find((event) => event.codeName === 'heartbeat_timeout');
  assert.ok(beatTimeout, '心跳无 ACK 没有触发重连，半开连接无法自愈');
  assert.equal(beatTimeout.codeSource, 'local');
  assert.equal(beatTimeout.willReconnect, true);
  abort();
  gateway.wss.close();
  await wait(20);
}

// ── 场景 3：服务端真的发了 close 帧，不能被标成本地判定 ──
{
  const gateway = await startGateway((socket) => {
    socket.send(HELLO(60_000));
    socket.close(4004, 'bad token');
  });
  const { conn, disconnects, abort } = makeConnection(gateway.url, { readyTimeoutMs: 5_000 });
  // start() 在重连预算耗尽时会 reject，测试只关心回调，这里吞掉。
  safeStart(conn);
  await wait(400);
  const authFailed = disconnects.find((event) => event.code === 4004);
  assert.ok(authFailed, '服务端 close 帧没有被记录');
  assert.equal(authFailed.codeSource, 'server');
  assert.equal(typeof authFailed.uptimeMs, 'number', '断开事件缺少连接存活时长');
  abort();
  gateway.wss.close();
  await wait(20);
}

console.log('PASS gateway ready timeout, heartbeat watchdog and close-code source');
