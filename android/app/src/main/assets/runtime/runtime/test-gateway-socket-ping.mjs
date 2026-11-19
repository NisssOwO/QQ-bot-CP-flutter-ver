/**
 * 传输层保活回归测试。
 *
 * 背景：只发应用层 `{op: HEARTBEAT}` JSON 心跳时，部分运营商 NAT / 云加速层
 * 只把 WebSocket 控制帧算作流量，于是连接建立约 60 秒就被当空闲回收，
 * 表现为 `code=1006 连接异常中断（无关闭帧）`、每次"连上约一分钟必断"。
 * `ws.ping()` 发的是控制帧，用来绕开这类空闲判定。
 *
 * 断言：
 * 1. socket 处于 OPEN 时按 socketPingMs 周期调用 ping()；
 * 2. socket 不是 OPEN 时一个 ping 都不发；
 * 3. cleanup() 之后定时器停掉，不再有新的 ping；
 * 4. 断开事件里带上本轮 PONG 计数，方便判断控制帧有没有被链路吞掉。
 *
 * 运行：node test-gateway-socket-ping.mjs
 */
import { GatewayConnection } from '../node_modules/@tencent-connect/qqbot-nodejs/dist/protocol/gateway/gateway-connection.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${ok || !detail ? '' : ` — ${detail}`}`);
};

const log = { info() {}, debug() {}, warn() {}, error() {} };
const disconnects = [];
const conn = new GatewayConnection({
  account: { accountId: 'socket-ping-test' },
  log,
  socketPingMs: 30,
  onDisconnected: (event) => disconnects.push(event),
});

const pings = [];
const fakeSocket = (readyState) => ({
  readyState,
  ping() {
    pings.push(Date.now());
  },
  terminate() {},
});

const open = fakeSocket(1);
conn.currentWs = open;
conn.startSocketPing(open);
await sleep(140);
check('OPEN socket 会被周期 ping', pings.length >= 2, `实际 ${pings.length} 次`);

const beforeClosed = pings.length;
const notOpen = fakeSocket(3);
conn.currentWs = notOpen;
conn.startSocketPing(notOpen);
await sleep(100);
check('非 OPEN socket 不发 ping', pings.length === beforeClosed, `多发了 ${pings.length - beforeClosed} 次`);

conn.currentWs = fakeSocket(1);
conn.startSocketPing(conn.currentWs);
await sleep(40);
conn.cleanup();
const beforeCleanup = pings.length;
await sleep(120);
check('cleanup 之后停止 ping', pings.length === beforeCleanup, `多发了 ${pings.length - beforeCleanup} 次`);

conn.socketPongCount = 4;
conn.handleGatewayReconnect('socket ping test');
check(
  '断开事件带 PONG 计数',
  disconnects.at(-1)?.socketPongs === 4,
  JSON.stringify(disconnects.at(-1)),
);

const failed = results.filter((item) => !item.ok);
console.log(failed.length === 0 ? 'ALL PASS' : `${failed.length} FAILED`);
process.exit(failed.length === 0 ? 0 : 1);
