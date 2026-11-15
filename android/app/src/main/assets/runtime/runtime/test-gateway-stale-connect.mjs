import assert from 'node:assert/strict';
import { GatewayConnection } from '../node_modules/@tencent-connect/qqbot-nodejs/dist/protocol/gateway/gateway-connection.js';

let resolveStaleUrl;
let urlCalls = 0;
const connectedUrls = [];
const controller = new AbortController();
const conn = new GatewayConnection({
  account: { accountId: 'stale-connect-test' },
  abortSignal: controller.signal,
  log: {
    info(message) {
      const match = message.match(/Connecting to (.+)$/);
      if (match) connectedUrls.push(match[1]);
    },
    debug() {}, warn() {}, error() {},
  },
  getAccessToken: async () => 'fake-token',
  getGatewayUrl: () => {
    urlCalls += 1;
    if (urlCalls === 1) return new Promise((resolve) => { resolveStaleUrl = resolve; });
    return Promise.resolve('wss://10.255.255.1/current');
  },
  reconnect: { maxAttempts: Infinity, delays: [5] },
  connectStageDeadlineMs: 20,
  connectTimeoutMs: 300,
  handshakeTimeoutMs: 1_000,
  helloTimeoutMs: 1_000,
});

void conn.start();
await new Promise((resolve) => setTimeout(resolve, 60));
assert.ok(urlCalls >= 2, 'timed-out first attempt should schedule a retry');
resolveStaleUrl('wss://10.255.255.1/stale');
await new Promise((resolve) => setTimeout(resolve, 50));
assert.equal(connectedUrls.includes('wss://10.255.255.1/stale'), false, 'stale attempt must not open a socket');
assert.equal(connectedUrls.includes('wss://10.255.255.1/current'), true, 'current attempt should own the socket');
controller.abort();
console.log('PASS stale connect continuation ignored');
