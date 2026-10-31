import assert from 'node:assert/strict';
import { newCommand } from '../node_modules/@tencent-connect/dsh-qqbot/dist/commands/session.js';

const context = { command: { raw: '' }, message: { kind: 'c2c', senderId: 'u1' } };
const command = newCommand({ manager: { remove: async () => false } });
const noSession = await command.handler(context);
assert.match(noSession, /没有活跃会话/);
const activeCommand = newCommand({ manager: { remove: async () => true } });
const active = await activeCommand.handler(context);
assert.match(active, /已开启新会话/);
console.log('PASS /new command feedback');
