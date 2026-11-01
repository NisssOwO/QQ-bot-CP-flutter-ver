import assert from 'node:assert/strict';
import {
  assertPublicUrl,
  decodeEntities,
  htmlTitle,
  htmlToText,
  parseRss,
  webFetchTool,
  webSearchTool,
} from '../assets-dsh-home/profiles/qqbot/node_modules/@shiny-colors/web-tools/index.js';

assert.equal(decodeEntities('a &amp; b &#39;c&#39; &#x4e2d;'), "a & b 'c' 中");
assert.equal(htmlToText('<p>Hello&nbsp;world</p><script>evil()</script>'), 'Hello world');
assert.equal(htmlToText('<div>one</div><div>two</div>'), 'one\ntwo');
assert.equal(htmlTitle('<html><head><title> 页面 标题 </title></head></html>'), '页面 标题');

const rss = '<rss><item><title>A &amp; B</title><link>https://a.example/x</link><description><![CDATA[摘要 <b>一</b>]]></description></item><item><title></title><link>https://skip.example</link></item></rss>';
assert.deepEqual(parseRss(rss), [{ title: 'A & B', url: 'https://a.example/x', snippet: '摘要 <b>一</b>' }]);

assert.equal(assertPublicUrl('https://example.com/a').hostname, 'example.com');
assert.throws(() => assertPublicUrl('http://127.0.0.1/'), /公网/);
assert.throws(() => assertPublicUrl('http://192.168.1.5/'), /公网/);
assert.throws(() => assertPublicUrl('http://localhost:3000/'), /公网/);
assert.throws(() => assertPublicUrl('file:///etc/passwd'), /http/);
assert.throws(() => assertPublicUrl('nonsense'), /有效的网址/);

assert.deepEqual(webSearchTool.parameters.required, ['query']);
assert.deepEqual(webFetchTool.parameters.required, ['url']);
const searchText = webSearchTool.output.render({}, { results: [{ title: 'T', url: 'https://u', snippet: 'S' }] })[0].text;
assert.match(searchText, /1\. T\nhttps:\/\/u\nS/);
const fetchText = webFetchTool.output.render({}, { url: 'https://u', status: 200, title: 'T', text: 'body', truncated: false })[0].text;
assert.match(fetchText, /GET https:\/\/u → HTTP 200/);
assert.match(fetchText, /# T\nbody/);

console.log('PASS web tools');