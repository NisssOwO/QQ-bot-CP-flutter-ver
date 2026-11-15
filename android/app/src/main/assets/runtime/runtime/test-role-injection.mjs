/**
 * 一个会话里只能出现当前生效的那一段角色卡。
 *
 * 背景：会话创建时 preset 的 mount() 会把角色卡写进 systemPrompt，这段之后删不掉；
 * 在 QQ 里 /preset 换角色时若不处理，prompt 里就会同时存在新旧两个人格，
 * 模型会顺着旧语气说话（串味）。所以每轮 assemble 都统一替换成当前角色一段，
 * 同时对话记忆（同一个 sessionId）完全保留。
 */
import assert from 'node:assert/strict';
import { SessionManager } from '../node_modules/@tencent-connect/dsh-qqbot/dist/session/session-manager.js';

const handlers = new Map();
let promptText = '# 角色卡：测试角色';
const promptCalls = [];
const fakePresets = {
    async prompt(id) {
        promptCalls.push(id);
        return promptText;
    },
};
const ctx = {
    on(event, handler) { handlers.set(event, handler); },
    get(name) { return name === 'agentPresets' ? fakePresets : undefined; },
};
const logger = { info() {}, warn() {}, debug() {}, error() {} };
const config = { appId: '100000000', preset: 'custom.demo', groupPrompt: '', directPrompt: '', sessionIdleTimeout: 0 };
const manager = new SessionManager(ctx, { get: () => undefined }, config, logger);

const assemble = handlers.get('system-prompt/assemble');
assert.ok(assemble, 'assemble hook must be registered');

function addSession(key, preset) {
    const agent = { name: key };
    manager.sessions.set(key, {
        sessionKey: key,
        sessionId: `sid-${key}`,
        agent,
        scope: 'group',
        peerId: 'P',
        agentPreset: preset,
        lastActivity: Date.now(),
    });
    return agent;
}

// 1) 普通情况：追加当前角色一段，原有无关 section 保持原样
{
    const agent = addSession('qqbot:100000000:group:A', undefined);
    const out = await assemble({}, { agent }, async () => ({ sections: [{ name: 'base', order: 0, text: 'base' }] }));
    assert.deepEqual(out.sections.map((s) => s.name), ['base', 'qqbot:role-current']);
    assert.equal(out.sections[1].text, '# 角色卡：测试角色');
    assert.equal(out.sections[1].order, 88);
    assert.deepEqual(promptCalls, ['custom.demo'], '每轮只解析一次角色正文');
}

// 2) 换角色：旧的角色段必须消失，只留当前角色；不再靠「请忽略上面的语气」提示词
{
    const agent = addSession('qqbot:100000000:group:B', 'alpha');
    const out = await assemble({}, { agent }, async () => ({
        sections: [
            { name: 'base', order: 0, text: 'base' },
            { name: 'shiny-colors:role:alpha', order: 88, text: '你是阿尔法。' },
        ],
    }));
    const names = out.sections.map((s) => s.name);
    assert.ok(!names.includes('shiny-colors:role:alpha'), `旧角色段必须被移除，实际: ${names.join(',')}`);
    assert.deepEqual(names, ['base', 'qqbot:role-current']);
    assert.equal(out.sections[1].text, '# 角色卡：测试角色');
    assert.ok(!out.sections[1].text.includes('角色切换提示'), '不再追加切换提示词');
}

// 3) 角色服务取不到正文时保持原 prompt 不动（宁可沿用旧段，也不把人设清空）
{
    promptText = '';
    const agent = addSession('qqbot:100000000:group:C', 'alpha');
    const out = await assemble({}, { agent }, async () => ({
        sections: [{ name: 'shiny-colors:role:alpha', order: 88, text: '你是阿尔法。' }],
    }));
    assert.equal(out.sections.length, 1);
    assert.equal(out.sections[0].name, 'shiny-colors:role:alpha');
    promptText = '# 角色卡：测试角色';
}

// 4) 没有 per-peer 覆盖也没有配置 preset 时，角色由 role-presets 的 default 决定
//    （mount 用的就是 default），所以要无参调用 prompt() 让服务自己回落，
//    否则默认角色换掉了也带不出变化。
{
    config.preset = '';
    const agent = addSession('qqbot:100000000:group:D', undefined);
    const before = promptCalls.length;
    const out = await assemble({}, { agent }, async () => ({ sections: [{ name: 'base', order: 0, text: 'base' }] }));
    assert.deepEqual(out.sections.map((s) => s.name), ['base', 'qqbot:role-current']);
    assert.equal(out.sections[1].text, '# 角色卡：测试角色');
    assert.equal(promptCalls.length, before + 1);
    assert.equal(promptCalls.at(-1), undefined, '没有生效 preset 时应无参调用，交给服务回落 default');
    config.preset = 'custom.demo';
}

// 5) 没有 agent 时原样返回
{
    const out = await assemble({}, {}, async () => ({ sections: [{ name: 'base', order: 0, text: 'base' }] }));
    assert.equal(out.sections.length, 1);
}

console.log('role injection ok');
