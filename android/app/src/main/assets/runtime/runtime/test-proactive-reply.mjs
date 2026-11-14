// 本地冒烟测试：node android/app/src/main/assets/runtime/runtime/test-proactive-reply.mjs
// 模拟 bot / llm / manager，验证主动回复的计数持久化、立即测试、requireMention 状态。
import { mkdtemp, readFile, writeFile, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';

const dir = await mkdtemp(join(tmpdir(), 'proactive-'));
process.env.SHINY_APP_FILES_DIR = dir;
await mkdir(join(dir, '.dsh-qqbot'), { recursive: true });
const { proactiveReply } = await import('../node_modules/@tencent-connect/dsh-qqbot/dist/middleware/proactive-reply.js');

const sent = [];
const bot = { send: async (opts) => { sent.push(opts); } };
const llm = {
    async *stream() {
        yield { type: 'block-start', index: 0, blockType: 'text' };
        yield { type: 'text-delta', index: 0, text: '你好呀' };
        yield { type: 'block-end', index: 0, block: { type: 'text', text: '你好呀' } };
        yield { type: 'finish', reason: { kind: 'stop' } };
    },
};
const host = { get: (name) => (name === 'llm' ? llm : { prompt: async () => '角色' }) };
const logger = { info() {}, warn: (m) => console.warn('warn:', m) };
const manager = { getEffectiveModel: () => ({ provider: 'relay', model: 'm' }), getEffectivePreset: () => 'custom.role' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const statePath = join(dir, '.dsh-qqbot', 'proactive-reply-state.json');
const readState = async () => JSON.parse(await readFile(statePath, 'utf8'));
const msg = (i) => ({ kind: 'group', groupOpenid: 'G1', senderId: 'u', senderName: '小明', content: `第${i}条消息`, messageId: `m${i}` });

// 1. 关闭状态下也记上下文；测试请求能用最近一条消息发出被动回复
const mw = proactiveReply(host, bot, { requireMention: true }, logger, manager);
for (let i = 0; i < 2; i++) await mw({ message: msg(i) }, async () => {});
await sleep(50);
await writeFile(join(dir, '.dsh-qqbot', 'proactive-reply-test.json'), JSON.stringify({ id: 't1', group: 'G1' }));
await sleep(4000);
let state = await readState();
assert.equal(state.requireMention, true);
assert.equal(typeof state.timeZone, 'string');
assert.equal(Number.isFinite(state.utcOffsetMinutes), true);
assert.equal(state.groups.G1.lastTestId, 't1');
assert.match(state.groups.G1.lastTestResult, /^测试已发送/, state.groups.G1.lastTestResult);
assert.equal(sent.length, 1);
assert.equal(sent[0].target.msgId, 'm1');
assert.equal(state.groups.G1.count, 0, '测试不计入每日次数');

// 2. 开启 100%，sinceReply 写入状态文件；发送后清零
await writeFile(join(dir, '.dsh-qqbot', 'proactive-reply.json'), JSON.stringify({ schemaVersion: 1, global: { enabled: true, probability: 0, minMessages: 3, cooldownSeconds: 0, quietHoursEnabled: false, requireRecentActivitySeconds: 0 }, groups: {} }));
await sleep(2100);
for (let i = 2; i < 4; i++) await mw({ message: msg(i) }, async () => {});
await sleep(1600);
state = await readState();
assert.equal(state.groups.G1.sinceReply, 2);

// 3. 新实例（模拟 Runtime 重启）继承 sinceReply
const mw2 = proactiveReply(host, bot, { requireMention: true }, logger, manager);
await writeFile(join(dir, '.dsh-qqbot', 'proactive-reply.json'), JSON.stringify({ schemaVersion: 1, global: { enabled: true, probability: 100, minMessages: 3, cooldownSeconds: 0, quietHoursEnabled: false, requireRecentActivitySeconds: 0 }, groups: {} }));
await mw2({ message: msg(4) }, async () => {});
await sleep(1600);
state = await readState();
assert.equal(sent.length, 2, '重启后第 3 条触发');
assert.equal(state.groups.G1.sinceReply, 0);
assert.equal(state.groups.G1.count, 1);

// 4. requireMention=false 时测试请求给出明确失败
// 用独立目录，避免前面两个实例的轮询抢走测试请求
const dir2 = await mkdtemp(join(tmpdir(), 'proactive-'));
await mkdir(join(dir2, '.dsh-qqbot'), { recursive: true });
process.env.SHINY_APP_FILES_DIR = dir2;
const statePath2 = join(dir2, '.dsh-qqbot', 'proactive-reply-state.json');
const mw3 = proactiveReply(host, bot, { requireMention: false }, logger, manager);
await sleep(1600);
assert.equal(JSON.parse(await readFile(statePath2, 'utf8')).requireMention, false);
await writeFile(join(dir2, '.dsh-qqbot', 'proactive-reply-test.json'), JSON.stringify({ id: 't2', group: 'G1' }));
await sleep(4000);
state = JSON.parse(await readFile(statePath2, 'utf8'));
assert.equal(state.groups.G1.lastTestId, 't2');
assert.match(state.groups.G1.lastTestResult, /群聊必须@/);
void mw3;
console.log('PASS proactive reply smoke test');
process.exit(0);
