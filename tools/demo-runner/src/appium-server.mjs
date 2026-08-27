import { spawn } from 'node:child_process';
import path from 'node:path';
import { createRequire } from 'node:module';
import { poll } from './time.mjs';
import { RUNNER_ROOT } from './demo-runner-config.mjs';
import { sanitizedChildEnvironment } from './redaction.mjs';

const require = createRequire(import.meta.url);

function appiumMainPath() {
  const packagePath = require.resolve('appium/package.json');
  return path.join(path.dirname(packagePath), 'build', 'lib', 'main.js');
}

async function serverReady(url) {
  try {
    const response = await fetch(new URL('/status', url), { signal: AbortSignal.timeout(1_000) });
    return response.ok;
  } catch {
    return false;
  }
}

function pipeSanitized(stream, logger, level) {
  let buffered = '';
  stream?.setEncoding('utf8');
  stream?.on('data', (chunk) => {
    buffered += chunk;
    const lines = buffered.split(/\r?\n/);
    buffered = lines.pop() ?? '';
    for (const line of lines) {
      if (line.trim()) logger[level](`[appium] ${line}`);
    }
  });
}

export class LocalAppiumServer {
  constructor({ url, environment, logger }) {
    this.url = new URL(url);
    this.environment = environment;
    this.logger = logger;
    this.process = null;
    this.owned = false;
  }

  async start() {
    if (await serverReady(this.url)) {
      throw new Error(
        `Refusing to reuse an unknown Appium server at ${this.url.origin}. Stop it or choose another --appium-url port.`,
      );
    }
    if (this.url.hostname !== '127.0.0.1' && this.url.hostname !== 'localhost') {
      throw new Error(`External Appium server is unavailable: ${this.url.origin}`);
    }

    const args = [
      appiumMainPath(),
      '--address', this.url.hostname,
      '--port', this.url.port || '4723',
      '--base-path', this.url.pathname === '/' ? '/' : this.url.pathname,
      '--log-level', 'error',
      '--log-no-colors',
    ];
    this.process = spawn(process.execPath, args, {
      cwd: RUNNER_ROOT,
      env: sanitizedChildEnvironment(this.environment),
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    this.owned = true;
    pipeSanitized(this.process.stdout, this.logger, 'info');
    pipeSanitized(this.process.stderr, this.logger, 'error');

    let exitError;
    this.process.once('exit', (code, signal) => {
      if (code !== 0 && signal !== 'SIGTERM') {
        exitError = new Error(`Appium exited before readiness (code=${code}, signal=${signal}).`);
      }
    });
    await poll(async () => {
      if (exitError) throw exitError;
      return serverReady(this.url);
    }, { timeoutMs: 45_000, intervalMs: 500, description: 'local Appium server' });
    this.logger.info(`[appium] local server ready at ${this.url.origin}`);
  }

  async stop() {
    if (!this.owned || !this.process || this.process.killed) return;
    this.process.kill();
    await Promise.race([
      new Promise((resolve) => this.process.once('exit', resolve)),
      new Promise((resolve) => setTimeout(resolve, 5_000)),
    ]);
  }
}
