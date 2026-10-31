import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const runtimeDir = path.dirname(fileURLToPath(import.meta.url));
const patch = fs.readFileSync(path.join(runtimeDir, '..', '.dsh-home', 'profiles', 'qqbot', 'cordis.patch.yml'), 'utf8');
assert.match(patch, /compat:\s*!!js\s+"process\.env\.LLM_API === 'openai-completions'/);
assert.doesNotMatch(patch, /^\s+thinkingFormat:\s+qwen\s*$/m);

const compatFor = api => api === 'openai-completions' ? { thinkingFormat: 'qwen' } : {};
assert.deepEqual(compatFor('openai-completions'), { thinkingFormat: 'qwen' });
assert.deepEqual(compatFor('openai-responses'), {});
assert.deepEqual(compatFor('anthropic-messages'), {});

console.log('PASS protocol compatibility guard');
