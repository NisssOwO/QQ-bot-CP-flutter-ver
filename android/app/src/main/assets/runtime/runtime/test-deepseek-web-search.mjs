import assert from 'node:assert/strict';
import { shouldInjectDeepSeekWebSearch } from '../node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js';

// DeepSeek 服务端联网搜索（deepseek_web_search）的注入开关。
// 关键约束：只有真正支持这个字段的端点才发，否则聚合站会返回 400，
// 一条消息都发不出去——所以默认关闭、且默认只认 DeepSeek 官方域名。

const deepseek = { baseUrl: 'https://api.deepseek.com' };
const relay = { baseUrl: 'https://api.hualong-ai.com/v1' };

delete process.env.DEEPSEEK_WEB_SEARCH;
delete process.env.DEEPSEEK_WEB_SEARCH_ANY;

// 未设置环境变量时必须不注入：升级后的旧配置不会突然开始发未知字段。
assert.equal(shouldInjectDeepSeekWebSearch(deepseek), false, '默认必须关闭');
assert.equal(shouldInjectDeepSeekWebSearch(relay), false, '默认必须关闭');

process.env.DEEPSEEK_WEB_SEARCH = '1';

// 打开开关后，只对 DeepSeek 官方端点注入。
assert.equal(shouldInjectDeepSeekWebSearch(deepseek), true, '官方端点应注入');
assert.equal(shouldInjectDeepSeekWebSearch({ baseUrl: 'https://api.deepseek.com/v1' }), true, '带路径也识别');
assert.equal(shouldInjectDeepSeekWebSearch(relay), false, '第三方聚合站不得注入');
assert.equal(shouldInjectDeepSeekWebSearch({ baseUrl: '' }), false, '空 baseUrl 不得注入');
assert.equal(shouldInjectDeepSeekWebSearch({}), false, '缺 baseUrl 不得注入');

// 自建兼容网关确实支持该字段时，可以显式放行。
process.env.DEEPSEEK_WEB_SEARCH_ANY = '1';
assert.equal(shouldInjectDeepSeekWebSearch(relay), true, 'ANY 开关应放行任意端点');

// 关闭开关的优先级高于强制放行。
process.env.DEEPSEEK_WEB_SEARCH = '0';
assert.equal(shouldInjectDeepSeekWebSearch(deepseek), false, '关闭开关必须生效');

delete process.env.DEEPSEEK_WEB_SEARCH;
delete process.env.DEEPSEEK_WEB_SEARCH_ANY;

console.log('test-deepseek-web-search: PASS');
