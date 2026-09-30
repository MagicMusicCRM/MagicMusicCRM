// Test-only clock for one disposable journey database and its local API process.
// No product endpoint, host clock change, or mocked business response.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

if (process.env.HTTP_JOURNEY_CLOCK_FILE) {
  assert.equal(process.env.NODE_ENV, 'test');
  const url = new URL(process.env.DATABASE_URL);
  assert(['localhost', '127.0.0.1'].includes(url.hostname));
  assert(/^\/magiccrm_http_test_[a-f0-9]+$/.test(url.pathname));
  const NativeDate = Date;
  const now = () => Number(JSON.parse(fs.readFileSync(process.env.HTTP_JOURNEY_CLOCK_FILE, 'utf8')).ms);
  global.Date = new Proxy(NativeDate, {
    construct(target, args) { return Reflect.construct(target, args.length ? args : [now()]); },
    apply() { return new NativeDate(now()).toString(); },
    get(target, key) { return key === 'now' ? now : Reflect.get(target, key); },
  });
}

async function prepareClock({pool, databaseName, output}) {
  assert(/^magiccrm_http_test_[a-f0-9]+$/.test(databaseName));
  const controlDir = path.join(output, 'midnight-control');
  fs.mkdirSync(controlDir);
  const clockFile = path.join(controlDir, 'clock.json');
  const start = new Date();
  start.setUTCHours(20, 59, 50, 0);
  fs.writeFileSync(clockFile, JSON.stringify({ms: start.getTime()}));
  await pool.query('create schema audit_clock');
  await pool.query('create table audit_clock.instant (at timestamptz not null)');
  await pool.query('insert into audit_clock.instant values ($1)', [start.toISOString()]);
  await pool.query(`create function audit_clock.now() returns timestamptz language sql stable
    as 'select at from audit_clock.instant'`);
  await pool.query(`alter database ${databaseName} set search_path = audit_clock, app, public, pg_catalog`);
  return {clockFile, controlDir};
}

async function runClockJourney({pool, clock, runDeviceTest, input}) {
  let finished = false;
  const device = runDeviceTest('task_midnight_live_test.dart', 'task-midnight-windows.log', {
    HTTP_JOURNEY_FIXTURE: JSON.stringify({...input, ...clock}),
  }).finally(() => { finished = true; });
  const control = (async () => {
    const trigger = path.join(clock.controlDir, 'advance');
    while (!fs.existsSync(trigger)) {
      if (finished) return;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    const before = JSON.parse(fs.readFileSync(clock.clockFile, 'utf8')).ms;
    const ms = before + 11_000;
    await pool.query('update audit_clock.instant set at=$1', [new Date(ms).toISOString()]);
    fs.writeFileSync(clock.clockFile + '.tmp', JSON.stringify({ms}));
    fs.renameSync(clock.clockFile + '.tmp', clock.clockFile);
    const sql = (await pool.query('select audit_clock.now() as now')).rows[0].now;
    assert.equal(sql.getTime(), ms);
    fs.writeFileSync(path.join(clock.controlDir, 'advanced.json'), JSON.stringify({ms, sqlNow: sql}));
  })();
  const results = await Promise.allSettled([device, control]);
  for (const result of results) if (result.status === 'rejected') throw result.reason;
}

module.exports = {prepareClock, runClockJourney};
