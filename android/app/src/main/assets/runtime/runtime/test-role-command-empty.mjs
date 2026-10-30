import assert from 'node:assert/strict';
import { executeRoleCommand } from './role-command.mjs';

const result = executeRoleCommand({
  text: '/presets',
  scope: 'private:1',
  isOwner: false,
  registry: { list: () => [], resolve: () => ({ id: 'none' }), get: () => undefined },
  store: { get: () => undefined, remove: () => {}, set: () => {} },
});
assert.equal(result.ok, true);
assert.deepEqual(result.roles, []);
assert.match(result.message, /暂无角色卡/);
console.log('PASS empty /presets response');
