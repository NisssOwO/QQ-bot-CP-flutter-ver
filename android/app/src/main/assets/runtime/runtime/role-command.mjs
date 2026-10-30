/** 角色命令解析；权限判断交给调用方，避免把 QQ 身份规则写死在业务层。 */
export function parseRoleCommand(text = '') {
  const input = String(text).trim();
  if (!input.startsWith('/')) return null;
  const match = /^\/(role|preset|角色|预设)(?:\s+(.+))?$/iu.exec(input);
  if (match) {
    const value = String(match[2] ?? '').trim();
    return value ? { action: 'set', value } : { action: 'show' };
  }
  if (/^\/(roles|presets|角色列表|预设列表)$/iu.test(input)) return { action: 'list' };
  if (/^\/(role-reset|preset-reset|角色重置|预设重置)$/iu.test(input)) return { action: 'reset' };
  return null;
}

export function executeRoleCommand({ text, scope, isOwner, registry, store } = {}) {
  const command = parseRoleCommand(text);
  if (!command) return null;
  if (!registry || !store || !scope) return { ok: false, message: '角色命令缺少运行上下文' };
  if (command.action === 'list') {
    const roles = registry.list().map(({ id, displayName, aliases }) => ({ id, displayName, aliases }));
    return {
      ok: true,
      action: 'list',
      roles,
      message: roles.length > 0 ? '可用角色：' : '暂无角色卡，请在 QQ-bot-CP 的角色页新建或导入角色卡。',
    };
  }
  if (command.action === 'show') {
    const role = registry.resolve(store.get(scope));
    return { ok: true, action: 'show', role };
  }
  if (!isOwner) return { ok: false, message: '只有机器人管理员可以切换角色' };
  if (command.action === 'reset') {
    store.remove(scope);
    return { ok: true, action: 'reset', role: registry.resolve() };
  }
  const role = registry.get(command.value);
  if (!role) return { ok: false, message: `未知角色「${command.value}」` };
  store.set(scope, role.id);
  return { ok: true, action: 'set', role };
}
