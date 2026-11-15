import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const runtimeDir = path.dirname(fileURLToPath(import.meta.url));
// assets-dsh-home is the only profile tree that reaches the APK (aapt drops
// dot-directories such as ".dsh-home"); the root patch then overwrites the
// profile's cordis.patch.yml on install. Both must stay in sync.
const patchFiles = [
  path.join(runtimeDir, '..', 'assets-dsh-home', 'profiles', 'qqbot', 'cordis.patch.yml'),
  path.join(runtimeDir, '..', 'qqbot-android.patch.yml'),
];
const patches = [];
for (const patchFile of patchFiles) {
  const patch = fs.readFileSync(patchFile, 'utf8');
  assert.match(patch, /compat:\s*!!js\s+"process\.env\.LLM_API === 'openai-completions'/);
  assert.doesNotMatch(patch, /^\s+thinkingFormat:\s+qwen\s*$/m);
  patches.push(patch.replace(/\r\n/g, '\n'));
}
assert.equal(patches[0], patches[1], 'assets-dsh-home 与根 patch 必须保持完全一致');

const compatFor = api => api === 'openai-completions' ? { thinkingFormat: 'qwen' } : {};
assert.deepEqual(compatFor('openai-completions'), { thinkingFormat: 'qwen' });
assert.deepEqual(compatFor('openai-responses'), {});
assert.deepEqual(compatFor('anthropic-messages'), {});

console.log('PASS protocol compatibility guard');
