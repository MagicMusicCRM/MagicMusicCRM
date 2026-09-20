const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { once } = require('node:events');

function validateMainEvidence(evidence, lessonId) {
  assert.equal(evidence.fixtureLessonId, lessonId);
  assert.equal(evidence.completed, true);
  for (const step of ['LOGIN', 'NAVIGATION', 'MOVE', 'REOPEN']) {
    assert(evidence.steps.includes(step), `Missing main-app UI evidence: ${step}`);
  }
}

function validatePersistedMove(data, fixture, evidence) {
  const rows = Array.isArray(data) ? data : data.items;
  const active = rows.filter(row => row.status === 'scheduled');
  assert.equal(active.length, 1);
  const row = active[0];
  assert.equal(row.roomId, fixture.rooms[1]);
  assert.equal(new Date(row.scheduledAt).toISOString(), evidence.scheduledAt);
  assert.equal(row.durationMinutes, 45);
  assert.notEqual(row.id, fixture.lessonId, 'Move must create its lifecycle successor');
  assert.equal(row.settlementTypeKey, 'trial_lesson');
  assert.equal(row.teacherCompensationRuleKey, 'trial_lesson');
  assert.equal(row.clientChargeType, 'none');
  return row;
}

// ADB-driven acceptance of the unmodified production entrypoint. The caller
// enforces the dedicated emulator and disabled external networking first.
async function runMainJourney({ root, output, fixture, runAdb, port }) {
  const defines = path.join(output, 'android-main-defines.json');
  const credentials = path.join(output, 'android-main-fixture.json');
  const evidencePath = path.join(output, 'android-main-complete.json');
  const relative = path.relative(root, defines).replaceAll('\\', '/');
  assert(/^dist\/http-journeys\/[a-f0-9]{32}\/android-main-defines\.json$/.test(relative));
  fs.writeFileSync(defines, JSON.stringify({ MAGIC_API_BASE_URL: fixture.baseUrl,
    MAGIC_PROFILE: `android-main-${fixture.lessonId}` }));
  fs.writeFileSync(credentials, JSON.stringify(fixture));
  const log = fs.openSync(path.join(output, 'android-main-build.log'), 'w');
  try {
    const child = spawn('cmd.exe', ['/d', '/s', '/c',
      `C:\\Flutter\\bin\\flutter.bat build apk --debug --target-platform android-x64 --target=lib/main.dart --no-pub --dart-define-from-file=${relative}`],
    { cwd: root, windowsHide: true, stdio: ['ignore', log, log], env: process.env });
    const [code] = await once(child, 'exit');
    assert.equal(code, 0, 'Main Android build failed');
    runAdb('install', '-r', path.join(root, 'build/app/outputs/flutter-apk/app-debug.apk'));
    runAdb('shell', 'am', 'force-stop', 'magic.crm');
    runAdb('reverse', `tcp:${port}`, `tcp:${port}`);
    runAdb('logcat', '-c');
    runAdb('shell', 'am', 'start', '-n', 'magic.crm/com.magicmusiccrm.magic_music_crm.MainActivity');
    console.log(`ANDROID_MAIN_READY ${output}`);
    const deadline = Date.now() + 1200000;
    while (!fs.existsSync(evidencePath) && Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 3000));
    }
    assert(fs.existsSync(evidencePath), 'ADB acceptance evidence was not completed within 20 minutes');
    const evidence = JSON.parse(fs.readFileSync(evidencePath, 'utf8'));
    validateMainEvidence(evidence, fixture.lessonId);
    // Independently verify durable backend state after UI save and reopen.
    const account = fixture.accounts.find(account => account.role === 'admin');
    const login = await fetch(`${fixture.baseUrl}/auth/login`, { method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: account.email, password: fixture.password }) });
    assert.equal(login.status, 200);
    const accessToken = (await login.json()).session.accessToken;
    const query = new URLSearchParams({ branchId: fixture.branchId, studentId: fixture.studentId,
      from: '2027-01-12T00:00:00Z', to: '2027-01-13T00:00:00Z', limit: '100' });
    const response = await fetch(`${fixture.baseUrl}/crm/lessons?${query}`, {
      headers: { authorization: `Bearer ${accessToken}` } });
    assert.equal(response.status, 200);
    const data = await response.json();
    fs.writeFileSync(path.join(output, 'android-main-response.json'), JSON.stringify(data, null, 2));
    const persisted = validatePersistedMove(data, fixture, evidence);
    fs.writeFileSync(path.join(output, 'android-main-persisted.json'), JSON.stringify(persisted, null, 2));
    console.log('PASS Android main login, navigation, move and reopened server state');
  } finally {
    fs.closeSync(log);
    for (const owned of [defines, credentials]) if (fs.existsSync(owned)) fs.unlinkSync(owned);
    try {
      fs.writeFileSync(path.join(output, 'android-main-flutter.log'), runAdb('logcat', '-d', '-s', 'flutter'));
      fs.writeFileSync(path.join(output, 'android-main-crash.log'), runAdb('logcat', '-b', 'crash', '-d'));
      runAdb('reverse', '--remove', `tcp:${port}`);
    } catch (_) { /* Preserve the primary failure if the emulator disconnected. */ }
  }
}
module.exports = { runMainJourney, validateMainEvidence, validatePersistedMove };
