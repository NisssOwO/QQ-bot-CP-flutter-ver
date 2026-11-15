import assert from 'node:assert/strict';
import { clampReplyText } from '../node_modules/@tencent-connect/dsh-qqbot/dist/middleware/proactive-reply.js';

// 「回复最长字数」曾经只用于过滤入站消息，真正生成回复时被硬编码 slice(0,500)，
// 于是改成多少都不生效。这里守住出站截断这一层。

// 1) 没超长时原样返回（只去首尾空白）
assert.equal(clampReplyText('  好呀，我也去  ', 100), '好呀，我也去');

// 2) 超长按配置截断，而不是写死的 500
assert.equal(clampReplyText('一'.repeat(1200), 100).length, 100);
assert.equal(clampReplyText('一'.repeat(700), 500).length, 500);

// 3) 小限制也要生效（以前 100 字的回复设成 20 仍然整条发出去）
assert.equal(clampReplyText('一'.repeat(100), 20), '一'.repeat(20));

// 3b) 超长时优先在句末收尾，不切出半句话
assert.equal(clampReplyText('今天天气不错。我们出去玩吧超级好玩', 8), '今天天气不错。');
assert.equal(clampReplyText('那我去准备一下。好的呀好的呀', 10), '那我去准备一下。');
// 句号太靠前（不足上限一半）时硬切，避免回复变得过短
assert.equal(clampReplyText('好。然后又说了很多很多很多很多很多很多', 12).length, 12);

// 4) 空值兜底
assert.equal(clampReplyText('', 20), '');
assert.equal(clampReplyText(undefined, 20), '');
assert.equal(clampReplyText(null, 20), '');

// 5) 非法上限回落默认值 500，不会把回复清空
assert.equal(clampReplyText('一'.repeat(900), 0).length, 500);
assert.equal(clampReplyText('一'.repeat(900), -5).length, 500);
assert.equal(clampReplyText('一'.repeat(900), Number.NaN).length, 500);

console.log('PASS proactive reply max text length');
