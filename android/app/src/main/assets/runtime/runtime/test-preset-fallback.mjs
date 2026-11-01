/**
 * 会话建好之后才选角色、或建会话时 preset 服务还没就绪时，
 * 每轮 assemble 必须补上角色卡正文，否则群聊会一直用宿主默认人格。
 */
import assert from 'node:assert/strict';
import { SessionManager } from '../node_modules/@tencent-connect/dsh-qqbot/dist/session/session-manager.js';

const handlers = new Map();
const fakePresets = {
  calls: [],
  async prompt(id) {
    this.calls.push(id);
    return id === 'custom.role' ? '# 角色卡：测试角色' : '';
  },
};
const ctx = {
  on(event, handler) { handlers.set(event, handler); },
  get(name) { return name === 'agentPresets' ? fakePresets : undefined; },
};
const logger = { info() {}, warn() {}, debug() {}, error() {} };
const config = { appId: '100000000', preset: 'custom.role', groupPrompt: '', directPrompt: '', sessionIdleTimeout: 0 };
const manager = new SessionManager(ctx, { get: () => undefined }, config, logger);

const assemble = handlers.get('system-prompt/assemble');
assert.ok(assemble, 'assemble hook must be registered');

const groupAgent = { name: 'group-agent' };
manager.sessions.set('qqbot:100000000:group:AAA', {
  sessionKey: 'qqbot:100000000:group:AAA',
  sessionId: 'group-session',
  agent: groupAgent,
  scope: 'group',
  peerId: 'AAA',
  agentPreset: undefined,
  lastActivity: Date.now(),
});

const assembled = await assemble({}, { agent: groupAgent }, async () => ({ sections: [{ name: 'base', order: 0, text: 'base' }] }));
const names = assembled.sections.map((section) => section.name);
assert.ok(names.includes('qqbot:preset-fallback'), `expected fallback section, got ${names.join(',')}`);
const fallbackText = assembled.sections.find((s) => s.name === 'qqbot:preset-fallback').text;
assert.ok(fallbackText.startsWith('# 角色卡：测试角色'), fallbackText);
assert.ok(fallbackText.includes('角色切换提示'), 'fallback must ask the model to drop the earlier generic tone');
assert.equal(assembled.sections[0].name, 'base', 'existing sections must stay');
assert.deepEqual(fakePresets.calls, ['custom.role'], 'preset body resolved once per assembly');

// 会话已经挂了同一个 preset 时不能再重复注入，否则角色正文会在 request 里出现两遍。
const boundAgent = { name: 'bound-agent' };
manager.sessions.set('qqbot:100000000:c2c:BBB', {
  sessionKey: 'qqbot:100000000:c2c:BBB',
  sessionId: 'c2c-session',
  agent: boundAgent,
  scope: 'c2c',
  peerId: 'BBB',
  agentPreset: 'custom.role',
  lastActivity: Date.now(),
});
const second = await assemble({}, { agent: boundAgent }, async () => ({ sections: [] }));
assert.equal(second.sections.length, 0, `bound session must not duplicate the role: ${JSON.stringify(second.sections)}`);

// 没有 preset 可用时保持原样，不能塞空 section。
const third = await assemble({}, { agent: boundAgent }, async () => ({ sections: [{ name: 'base', order: 0, text: 'base' }] }));
assert.equal(third.sections.length, 1);

manager.evictor?.dispose?.();
console.log('preset fallback ok');