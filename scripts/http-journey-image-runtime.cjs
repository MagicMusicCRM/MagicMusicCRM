// Run the actual local image against the existing disposable HTTP fixture.
const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const { once } = require('node:events');
const fs = require('node:fs');
const path = require('node:path');

function imageEnvironment(env) {
  const database = new URL(env.DATABASE_URL);
  assert(['127.0.0.1', 'localhost', '[::1]'].includes(database.hostname), 'Image gate requires loopback database');
  assert(/^\/magiccrm_http_test_[a-f0-9]{32}$/.test(database.pathname), 'Only a gate-owned disposable database is allowed');
  database.hostname = 'host.docker.internal';
  const mapped = Object.fromEntries(Object.entries(env).filter(([key]) =>
    !['SystemRoot', 'WINDIR', 'PATH', 'Path', 'TEMP', 'TMP', 'HOME', 'USERPROFILE', 'TS_NODE_PROJECT'].includes(key)));
  return { ...mapped, DATABASE_URL: database.toString(), PORT: '3000', FILE_STORAGE_ROOT: '/opt/magicmusiccrm/storage/private' };
}

function startImageRuntime({ image, env, port, runId, output, log }) {
  assert(/^magicmusiccrm-server:[a-zA-Z0-9_.+-]+$/.test(image), 'Only a local CRM image tag is permitted');
  assert(/^[a-f0-9]{32}$/.test(runId));
  const config = imageEnvironment(env);
  const metadata = JSON.parse(execFileSync('docker', ['image', 'inspect', image], { windowsHide: true }))[0];
  assert(/^sha256:[a-f0-9]{64}$/.test(metadata.Id));
  const name = `magiccrm-http-${runId}`;
  // Pass synthetic credentials through the process environment, not argv or files.
  const args = ['run', '--rm', '--pull', 'never', '--name', name,
    '--label', `com.magicmusiccrm.http-journey=${runId}`,
    '--publish', `127.0.0.1:${port}:3000`,
    ...Object.keys(config).flatMap(key => ['--env', key]), metadata.Id];
  const evidencePath = path.join(output, 'image-runtime.json');
  const history = fs.existsSync(evidencePath) ? JSON.parse(fs.readFileSync(evidencePath, 'utf8')) : [];
  history.push({
    image, imageId: metadata.Id, labels: metadata.Config.Labels,
    scope: 'Exact image runtime; synthetic local database, loopback HTTP; no production connection.',
  });
  fs.writeFileSync(evidencePath, JSON.stringify(history, null, 2));
  const child = spawn('docker', args, {
    env: { ...process.env, ...config }, windowsHide: true, stdio: ['ignore', log, log],
  });
  child.on('error', error => { fs.appendFileSync(path.join(output, 'api.log'), `Docker launch failed: ${error.code}\n`); });
  return { child, async stop() {
    if (child.exitCode !== null || child.signalCode !== null) return;
    const stopped = once(child, 'exit');
    const owned = JSON.parse(execFileSync('docker', ['container', 'inspect', name], { windowsHide: true }))[0];
    assert.equal(owned.Config.Labels['com.magicmusiccrm.http-journey'], runId, 'Container ownership mismatch');
    execFileSync('docker', ['stop', '--time', '10', owned.Id], { windowsHide: true });
    await stopped;
  } };
}
module.exports = { imageEnvironment, startImageRuntime };
