const assert = require('node:assert/strict');
const { spawn, execFileSync } = require('node:child_process');
const { once } = require('node:events');
const fs = require('node:fs');
const path = require('node:path');

function androidConfig(serial, raw) {
  assert(/^emulator-\d+$/.test(serial), 'An explicit emulator serial is required');
  const fixture = JSON.parse(raw);
  const url = new URL(fixture.baseUrl);
  assert(url.hostname === '127.0.0.1' && url.protocol === 'http:' && url.port,
    'Android QA only permits an explicit loopback HTTP port');
  return { serial, port: url.port, fixture };
}

async function runAndroidJourney({ root, output, raw }) {
  const { serial, port, fixture } = androidConfig(process.env.HTTP_JOURNEY_ANDROID_SERIAL, raw);
  const sdk = process.env.ANDROID_HOME;
  assert(sdk, 'ANDROID_HOME is required');
  const adb = path.join(sdk, 'platform-tools', 'adb.exe');
  const runAdb = (...args) => execFileSync(adb, ['-s', serial, ...args], {
    windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], timeout: 20000,
  });
  assert(runAdb('emu', 'avd', 'name').toString().includes('MagicMusicCRM_QA222_AUTH_20260915'),
    'Only the dedicated QA emulator is allowed');
  assert(runAdb('shell', 'dumpsys', 'connectivity').toString().includes('Active default network: none'),
    'The QA emulator must have external networking disabled');
  if (process.env.HTTP_JOURNEY_ANDROID_MAIN === '1') {
    return require('./android-main-journey-runtime.cjs').runMainJourney({ root, output, fixture, runAdb, port });
  }
  const defines = path.join(output, 'android-fixture.json');
  const relativeDefines = path.relative(root, defines).replaceAll('\\', '/');
  assert(/^dist\/http-journeys\/[a-f0-9]{32}\/android-fixture\.json$/.test(relativeDefines));
  fs.writeFileSync(defines, JSON.stringify({ HTTP_JOURNEY_FIXTURE: raw }));
  runAdb('reverse', `tcp:${port}`, `tcp:${port}`);
  const log = fs.openSync(path.join(output, 'customer-revisions-android.log'), 'w');
  try {
    const child = spawn('cmd.exe', ['/d', '/s', '/c',
      `C:\\Flutter\\bin\\flutter.bat build apk --debug --target-platform android-x64 --target=integration_test/customer_revisions_live_test.dart --no-pub --dart-define-from-file=${relativeDefines}`],
    { cwd: root, windowsHide: true, stdio: ['ignore', log, log], env: process.env });
    const [code] = await once(child, 'exit');
    assert.equal(code, 0, 'Android build failed; inspect customer-revisions-android.log');
    runAdb('install', '-r', path.join(root, 'build/app/outputs/flutter-apk/app-debug.apk'));
    runAdb('shell', 'am', 'force-stop', 'magic.crm');
    runAdb('reverse', `tcp:${port}`, `tcp:${port}`);
    runAdb('shell', 'am', 'start', '-n', 'magic.crm/com.magicmusiccrm.magic_music_crm.MainActivity');
    const deadline = Date.now() + 240000;
    let completed = false;
    while (Date.now() < deadline) {
      try {
        const report = JSON.parse(runAdb('exec-out', 'run-as', 'magic.crm', 'cat',
          'code_cache/magic-evidence/customer-revisions-admin.json').toString());
        if (report.fixtureLessonId === fixture.lessonId && report.completed) {
          completed = true;
          break;
        }
      } catch (_) { /* The report does not exist until the first check finishes. */ }
      await new Promise(resolve => setTimeout(resolve, 3000));
    }
    assert(completed, 'Autonomous Android tests did not finish in 240 seconds');
  } finally {
    fs.closeSync(log);
    // This invocation owns this synthetic credential file only.
    fs.unlinkSync(defines);
    try {
      runAdb('reverse', '--remove', `tcp:${port}`);
    } catch (_) {
      // A disconnected emulator must not hide the original test failure.
    }
    try {
      const names = runAdb('shell', 'run-as', 'magic.crm', 'ls', 'code_cache/magic-evidence')
        .toString().trim().split(/\s+/);
      for (const name of names.filter(name => /^customer-revisions-admin-[\w.-]+\.png$|^customer-revisions-admin\.json$/.test(name))) {
        fs.writeFileSync(path.join(output, name), runAdb('exec-out', 'run-as', 'magic.crm', 'cat', `code_cache/magic-evidence/${name}`));
      }
      fs.writeFileSync(path.join(output, 'android-crash.log'), runAdb('logcat', '-b', 'crash', '-d'));
      fs.writeFileSync(path.join(output, 'android-flutter.log'), runAdb('logcat', '-d', '-s', 'flutter'));
    } catch (error) {
      fs.writeFileSync(path.join(output, 'android-evidence-error.txt'), String(error.message));
    }
  }
  const report = JSON.parse(fs.readFileSync(path.join(output, 'customer-revisions-admin.json'), 'utf8'));
  assert(report.steps.length >= 7 && report.steps.every(step => step.status === 'PASS'),
    'Android evidence must contain every passing feature check');
}
module.exports = { androidConfig, runAndroidJourney };
