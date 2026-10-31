import assert from 'node:assert/strict';
import { presetCommand } from '../node_modules/@tencent-connect/dsh-qqbot/dist/commands/preset.js';

const context = { command: { raw: 'next' }, message: { kind: 'c2c', senderId: 'u1' } };
const manager = {
  getSessionRecord: () => ({ agentPreset: 'old' }),
  getEffectivePreset: () => 'old',
  setPresetOverride: async () => ({ ok: true }),
  clearPresetOverride: async () => ({ ok: true }),
  listPresets: async () => [],
};
const command = presetCommand({ manager, config: { textChunkLimit: 2000 } });
assert.match(await command.handler(context), /old → next/);
context.command.raw = 'reset';
assert.match(await command.handler(context), /old → 默认/);
console.log('PASS /preset transition feedback');
