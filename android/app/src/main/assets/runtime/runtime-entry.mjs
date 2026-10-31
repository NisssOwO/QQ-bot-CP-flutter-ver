import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';

const root = process.env.SHINY_RUNTIME_ROOT ?? process.cwd();

const redact = text => text
  .replace(/(APPSECRET|API[_-]?KEY|TOKEN|SECRET)=\S+/gi, '$1=[redacted]')
  .replace(/("(?:api[_-]?key|app[_-]?secret|token|authorization|bearer)"\s*:\s*")[^"]*(")/gi, '$1[redacted]$2')
  .replace(/(Bearer\s+)[A-Za-z0-9._~+\-/]+=*/gi, '$1[redacted]');

let child = null;
let childSeenOutput = false;
process.on('uncaughtException', error => {
  process.stderr.write(`runtime-entry failed: ${redact(String(error?.stack ?? error))}\n`);
  child?.kill('SIGTERM');
  process.exit(1);
});

try {
  const profile = process.env.DSH_HOME ?? `${root}/dsh-home`;
  const nodeBin = process.env.SHINY_NODE_BIN ?? process.execPath;
  if (!existsSync(nodeBin)) throw new Error(`runtime node binary not found: ${nodeBin}`);

  child = spawn(nodeBin, ['node_modules/@deepseek-ai/dsh/lib/bin.js', '--profile', 'qqbot'], {
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
  // The host waits for this first line to distinguish "node started" from a
  // silent process, so it must not wait for DSH to finish booting.
  process.stdout.write(`QQBOT_BOOTING pid=${child.pid ?? 'unknown'}\n`);
  child.stdout.on('data', chunk => {
    childSeenOutput = true;
    process.stdout.write(redact(String(chunk)));
  });
  child.stderr.on('data', chunk => {
    childSeenOutput = true;
    process.stderr.write(redact(String(chunk)));
  });
  child.on('error', error => {
    process.stderr.write(`DSH spawn error: ${error?.code ?? ''} ${redact(String(error?.message ?? error))}\n`);
    process.exit(1);
  });
  child.on('exit', (code, signal) => {
    // Nothing is usually printed when DSH exits this early, so the host gets a
    // reason it can show instead of an empty stderr sample.
    if (!childSeenOutput) process.stderr.write(`DSH exited before any output (code=${code ?? 'null'} signal=${signal ?? 'none'})\n`);
    process.exit(code ?? (signal ? 1 : 0));
  });
  process.on('SIGTERM', () => child?.kill('SIGTERM'));
  process.on('SIGINT', () => child?.kill('SIGINT'));
} catch (error) {
  process.stderr.write(`runtime-entry failed: ${redact(String(error?.stack ?? error))}\n`);
  process.exit(1);
}