import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';

const root = process.env.SHINY_RUNTIME_ROOT ?? process.cwd();
const profile = process.env.DSH_HOME ?? `${root}/.dsh-home`;
const nodeBin = process.env.SHINY_NODE_BIN ?? process.execPath;
if (!existsSync(nodeBin)) throw new Error(`runtime node binary not found: ${nodeBin}`);

const child = spawn(nodeBin, ['node_modules/@deepseek-ai/dsh/lib/bin.js', '--profile', 'qqbot'], {
  cwd: root,
  env: {
    ...process.env,
    DSH_HOME: profile,
    DSH_CWD: root,
    // Android's app-private filesystem can reject hard links even within one
    // directory. Preload a small compatibility shim for atomic writers.
    NODE_OPTIONS: [process.env.NODE_OPTIONS, `--require=${root}/android-fs-compat.cjs`].filter(Boolean).join(' '),
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});
const redact = text => text
  .replace(/(APPSECRET|API[_-]?KEY|TOKEN|SECRET)=\S+/gi, '$1=[redacted]')
  .replace(/("(?:api[_-]?key|app[_-]?secret|token|authorization|bearer)"\s*:\s*")[^"]*(")/gi, '$1[redacted]$2')
  .replace(/(Bearer\s+)[A-Za-z0-9._~+\-/]+=*/gi, '$1[redacted]');
child.stdout.on('data', chunk => process.stdout.write(redact(String(chunk))));
child.stderr.on('data', chunk => process.stderr.write(redact(String(chunk))));
child.on('exit', (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
process.on('SIGTERM', () => child.kill('SIGTERM'));
process.on('SIGINT', () => child.kill('SIGINT'));
