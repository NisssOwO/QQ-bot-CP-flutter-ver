import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { QuietHours } from './quiet-hours.mjs';
import { MessageDeduplicator } from './message-guard.mjs';
import { OfficialMessagePipeline } from './official-message-pipeline.mjs';
import { OfficialBotOrchestrator } from './official-orchestrator.mjs';
import { RoleRegistry } from './role-registry.mjs';
import { SessionRoleStore } from './session-role-store.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const presetDir = fs.mkdtempSync(path.join(os.tmpdir(), 'orchestrator-presets-'));
for (const [id, displayName] of [['nanoka', 'Nanoka'], ['hazuki', 'Hazuki'], ['tooru', 'Tooru']]) {
  const dir = path.join(presetDir, id);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'agent.cordis.yml'), `id: ${id}\n`);
  fs.writeFileSync(path.join(presetDir, `preset.${id}.json`), JSON.stringify({ id, displayName, aliases: [id] }));
}
const registry = new RoleRegistry({ presetDir });
const store = new SessionRoleStore({ file: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'orchestrator-')), 'roles.json') });
const pipeline = new OfficialMessagePipeline({ quietHours: new QuietHours({ config: { enabled: false }, stateDir: root }), deduplicator: new MessageDeduplicator() });
const orchestrator = new OfficialBotOrchestrator({ pipeline, registry, roleStore: store, isOwner: (m) => m.userId === 'owner' });

const group = (content, id = 'm1', user = 'owner', mentioned = true) => ({ t: 'GROUP_AT_MESSAGE_CREATE', d: { id, seq: 1, group_openid: 'g1', content, author: { user_openid: user }, mentions: mentioned ? [{ id: 'bot' }] : [] } });
const switched = orchestrator.ingest(group('/role hazuki'));
assert.equal(switched.action, 'command');
assert.equal(switched.command.role.id, 'hazuki');
const prompt = orchestrator.ingest(group('你好', 'm2'));
assert.equal(prompt.action, 'prompt');
assert.equal(prompt.role.id, 'hazuki');
assert.equal(prompt.sessionKey, 'qqbot:group:g1');
assert.equal(prompt.text, '你好');
const group2 = (content, id = 'g2m1') => ({ t: 'GROUP_AT_MESSAGE_CREATE', d: { id, seq: 1, group_openid: 'g2', content, author: { user_openid: 'owner' }, mentions: [{ id: 'bot' }] } });
const isolated = orchestrator.ingest(group2('另一个群'));
assert.equal(isolated.role.id, 'nanoka');
const privateMessage = (content, id = 'pm1') => ({ t: 'C2C_MESSAGE_CREATE', d: { id, seq: 1, author: { user_openid: 'owner' }, content } });
const privateSwitched = orchestrator.ingest(privateMessage('/preset tooru'));
assert.equal(privateSwitched.command.role.id, 'tooru');
const privatePrompt = orchestrator.ingest(privateMessage('私聊上下文', 'pm2'));
assert.equal(privatePrompt.role.id, 'tooru');
assert.equal(orchestrator.ingest(group2('群组仍是默认角色', 'g2m2')).role.id, 'nanoka');

const duplicate = orchestrator.ingest(group('你好', 'm2'));
assert.equal(duplicate.action, 'ignore');
assert.equal(duplicate.reason, 'duplicate');
const quietGroup = orchestrator.ingest(group('未 @ 的消息', 'm3', 'other', false));
assert.equal(quietGroup.action, 'ignore');
assert.equal(quietGroup.reason, 'mention-required');

console.log('PASS official bot orchestration');

