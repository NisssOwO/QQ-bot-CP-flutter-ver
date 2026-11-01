import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

// Android TurboModule finder expressions use \p{Control}; a Node build compiled
// with a regexp backend that rejects that property fails to boot the app.
const controlSafe = /[^\w#$*+\-./:?@\\\u{80}-\u{10FFFF}]|^\p{Control}$/u;
assert.equal(controlSafe.test('\u0000'), true);
assert.equal(controlSafe.test('\u007f'), true);
assert.equal(controlSafe.test('ok'), false);

// The Android launcher stages a copy of bin/node under code_cache and executes it
// there, so the staged binary must be able to run a script by absolute path.
assert.ok(path.isAbsolute(process.execPath));
const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'shiny-colors-exec-'));
const script = path.join(sandbox, 'check.mjs');
fs.writeFileSync(script, 'console.log(process.argv[2]);\n');
const output = await new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [script, 'staged-ok'], { stdio: ['ignore', 'pipe', 'inherit'] });
  let text = '';
  child.stdout.on('data', (chunk) => { text += chunk; });
  child.on('error', reject);
  child.on('exit', (code) => (code === 0 ? resolve(text.trim()) : reject(new Error(`exit=${code}`))));
});
assert.equal(output, 'staged-ok');

console.log('PASS android node bootstrap');