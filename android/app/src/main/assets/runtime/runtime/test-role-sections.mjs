// 角色段替换：一个会话里只能出现当前生效的那一段角色卡。
// 会话创建时 preset 的 mount() 会把角色卡写进 systemPrompt，这段之后删不掉；
// 在 QQ 里 /preset 换角色时若不处理，prompt 里会同时存在新旧两个人格，
// 模型就会串味。applyRoleSections 负责每轮只留当前角色一段。
import assert from 'node:assert/strict';
import { applyRoleSections } from '../node_modules/@tencent-connect/dsh-qqbot/dist/session/session-manager.js';

const oldRole = { name: 'shiny-colors:role:alpha', order: 88, text: '你是阿尔法。' };
const other = { name: 'qqbot:scope-prompt', order: 90, text: '群聊规则。' };

{
    const out = applyRoleSections([oldRole, other], '你是贝塔。');
    assert.equal(out.length, 2, '旧角色段必须被移除，只留新角色段和无关段');
    assert.equal(out[0].name, 'qqbot:scope-prompt', '非角色段必须原样保留');
    assert.equal(out[1].name, 'qqbot:role-current');
    assert.equal(out[1].text, '你是贝塔。');
    assert.equal(out[1].order, 88);
    assert.equal(out.filter((s) => s.name.startsWith('shiny-colors:role:')).length, 0);
}

{
    // 只有角色段时，替换后也应只剩一段
    const out = applyRoleSections([oldRole], '你是贝塔。');
    assert.equal(out.length, 1);
    assert.equal(out[0].text, '你是贝塔。');
}

{
    // roleText 为空表示「不注入人格」，此时只做过滤，不追加
    const out = applyRoleSections([oldRole, other], '');
    assert.equal(out.length, 1, '空 roleText 时不追加新段');
    assert.equal(out[0].name, 'qqbot:scope-prompt');
}

{
    // 没有 sections / 非法项时不崩
    assert.deepEqual(applyRoleSections(undefined, ''), []);
    assert.doesNotThrow(() => applyRoleSections([null, { name: 123 }], '你是贝塔。'));
}

console.log('test-role-sections: OK');
