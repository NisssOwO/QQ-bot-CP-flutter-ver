/**
 * 建连看门狗回归测试。
 *
 * 背景：`isConnecting` 只有 open/close 事件能解锁，而 ws 的 `handshakeTimeout`
 * 从 socket 建立后才开始计时，不覆盖 DNS 解析。一旦某次建连卡在 DNS/TCP 中间态，
 * `connect()` 的入口判断会把后续每一次重连都吞掉，状态机静默停摆。
 *
 * 做法：把 handshakeTimeout 调得远大于 connectTimeoutMs，连一个不可达地址
 * （SYN 无响应），断言只有 connectTimeout 会触发并交回重连循环。
 *
 * 运行：node test-gateway-connect-timeout.mjs
 */
import { GatewayConnection } from '../node_modules/@tencent-connect/qqbot-nodejs/dist/protocol/gateway/gateway-connection.js';

const events = [];
const conn = new GatewayConnection({
  account: { accountId: 'connect-timeout-test' },
  abortSignal: new AbortController().signal,
  log: { info() {}, debug() {}, warn() {}, error() {} },
  getAccessToken: async () => 'fake-token',
  getGatewayUrl: async () => 'wss://10.255.255.1/websocket/',
  onDisconnected: (event) => events.push(event),
  handshakeTimeoutMs: 120_000,
  connectTimeoutMs: 800,
  helloTimeoutMs: 120_000,
});

void conn.start();

setTimeout(() => {
  const first = events[0];
  const ok = first?.reason === 'connect timeout' && first?.willReconnect === true;
  console.log(ok ? 'PASS' : 'FAIL', JSON.stringify(events));
  process.exit(ok ? 0 : 1);
}, 4000);