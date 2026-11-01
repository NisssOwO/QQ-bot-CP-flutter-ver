/**
 * Appends everything the DSH runtime prints to `${SHINY_RUNTIME_ROOT}/logs/runtime.log`.
 *
 * The app can only read what the child process writes to its stdout pipe, and the pipe
 * goes quiet once DSH installs its own output sink. Loading this file with --require into
 * the DSH process keeps a file copy that survives a silent pipe, a restart or a detached
 * reader, which is what makes post-boot failures debuggable.
 *
 * Line format: <ISO-8601 time>|<stdout|stderr|host>|<raw text>
 */
const fs = require('node:fs');
const path = require('node:path');

const root = process.env.SHINY_RUNTIME_ROOT || process.cwd();
const logDir = path.join(root, 'logs');
const logFile = path.join(logDir, 'runtime.log');
const maxBytes = 4 * 1024 * 1024;

let usable = false;
try {
  fs.mkdirSync(logDir, { recursive: true });
  const stat = fs.statSync(logFile, { throwIfNoEntry: false });
  if (stat && stat.size > maxBytes) {
    fs.rmSync(`${logFile}.1`, { force: true });
    fs.renameSync(logFile, `${logFile}.1`);
  }
  usable = true;
} catch {
  usable = false;
}

if (usable) {
  const pending = new Map();
  let writing = false;

  const append = text => {
    // A failed append reports through console.error, which our own hook would capture
    // again; the guard keeps that from recursing forever.
    if (writing) return;
    writing = true;
    try {
      fs.appendFileSync(logFile, text);
    } catch {
      usable = false;
    } finally {
      writing = false;
    }
  };

  const tap = (stream, chunk) => {
    if (!usable) return;
    const text = typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8');
    const buffered = (pending.get(stream) || '') + text;
    const lines = buffered.split('\n');
    pending.set(stream, lines.pop() || '');
    if (lines.length === 0) return;
    const stamp = new Date().toISOString();
    append(`${lines.map(line => `${stamp}|${stream}|${line.replace(/\r$/, '')}`).join('\n')}\n`);
  };

  for (const stream of ['stdout', 'stderr']) {
    const write = process[stream].write.bind(process[stream]);
    process[stream].write = function patched(chunk, ...rest) {
      try {
        tap(stream, chunk);
      } catch {
        // Never let logging break the runtime's own output.
      }
      return write(chunk, ...rest);
    };
  }
}