import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createGatewayEvents, describeCloseCode, explainCloseCode } from '../node_modules/@tencent-connect/dsh-qqbot/dist/gateway/gateway-events.js';

// ── close code 语义映射 ──
assert.equal(describeCloseCode(1000), 'normal');
assert.equal(describeCloseCode(1006), 'abnormal_closure');
assert.equal(describeCloseCode(4004), 'auth_failed');
assert.equal(describeCloseCode(4905), 'server_error');
assert.equal(describeCloseCode(4020), 'close_4020');
assert.equal(describeCloseCode(null), 'unknown');
assert.match(explainCloseCode(1006), /异常中断/);
assert.match(explainCloseCode(4008), /频控/);

// ── 追加写入：两次断开都必须留下，不能被后一次覆盖 ──
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shiny-colors-gateway-events-'));
process.env.SHINY_RUNTIME_ROOT = root;
// 环境变量在模块加载时读取，所以要在设置之后再创建实例（此处已满足：import 只取函数）。
const events = createGatewayEvents('1234567890', null);
const file = events.file;
// 没给 App 私有目录时才退化到 runtime/logs（runtime 目录可能被重建清空）。
assert.ok(file.endsWith(path.join('logs', 'gateway-events.jsonl')), `落盘路径不对：${file}`);

// ── 给了 App 私有目录就必须优先用它，避开 runtime 目录被 deleteRecursively 清掉 ──
const appFiles = fs.mkdtempSync(path.join(os.tmpdir(), 'shiny-colors-app-files-'));
process.env.SHINY_APP_FILES_DIR = appFiles;
const preferred = createGatewayEvents('1234567890', null);
assert.equal(
  preferred.file,
  path.join(appFiles, '.dsh-qqbot', 'gateway-events.jsonl'),
  `应优先写入 App 私有目录，实际：${preferred.file}`,
);
delete process.env.SHINY_APP_FILES_DIR;

events.disconnect(
  {
    code: 1000,
    codeSource: 'local',
    codeName: 'ready_timeout',
    reason: 'READY timeout',
    willReconnect: true,
    attempt: 3,
    uptimeMs: 5_000,
    sinceLastReadyMs: 12_000,
    readyState: 1,
  },
  'online',
);
events.disconnect(
  {
    code: 1006,
    codeSource: 'server',
    reason: '',
    willReconnect: true,
    attempt: 4,
    uptimeMs: 900,
    sinceLastReadyMs: null,
    readyState: 3,
  },
  'reconnecting',
);
events.disconnect({ code: 4004, codeSource: 'server', reason: 'bad token', willReconnect: false }, 'reconnecting');
events.online({ totalMs: 4_200, readyMs: 4_200 });
events.failed('retry exhausted', { stateBefore: 'reconnecting' });
events.connectFailed('access token timed out after 45000ms', { phase: 'connect' });
events.note('stop', 'Runtime 主动关闭网关');

const lines = fs.readFileSync(file, 'utf8').trim().split('\n').map((line) => JSON.parse(line));
assert.equal(lines.length, 7, `事件条数不对：${lines.length}`);

// 本地判定的 1000 不能冒充“服务端正常关闭”
const [readyTimeout, abnormal, authFailed] = lines;
assert.equal(readyTimeout.event, 'reconnecting');
assert.equal(readyTimeout.codeSource, 'local');
assert.equal(readyTimeout.codeName, 'ready_timeout');
assert.match(readyTimeout.codeText, /本地判定/);
assert.equal(readyTimeout.stateBefore, 'online');
assert.equal(readyTimeout.uptimeMs, 5_000);
assert.equal(readyTimeout.sinceLastReadyMs, 12_000);

assert.equal(abnormal.codeSource, 'server');
assert.equal(abnormal.codeName, 'abnormal_closure');
assert.match(abnormal.codeText, /异常中断/);
assert.equal(abnormal.sinceLastReadyMs, null);

// willReconnect=false 必须落成 offline，而不是 reconnecting
assert.equal(authFailed.event, 'offline');
assert.equal(authFailed.state, 'offline');
assert.equal(authFailed.codeName, 'auth_failed');

assert.equal(lines[3].event, 'online');
assert.equal(lines[3].totalMs, 4_200);
assert.equal(lines[4].event, 'failed');
assert.equal(lines[5].event, 'connect_failed');
assert.equal(lines[5].phase, 'connect');
assert.equal(lines[6].event, 'note');

// 每行都必须带时间戳，便于和 runtime.log 对齐
for (const line of lines) {
  assert.equal(typeof line.ts, 'number');
  assert.match(line.iso, /^\d{4}-\d{2}-\d{2}T/);
}

console.log('PASS gateway event history is append-only and labelled');
