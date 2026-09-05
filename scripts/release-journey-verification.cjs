const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const dependency = createRequire(path.join(__dirname, '../server/package.json'));
const { Pool } = dependency('pg');
const run = promisify(execFile);

const scenarios = ['student-created', 'network-loss-draft-preserved', 'payment-retried-once',
  'lesson-booked', 'lesson-completed', 'lesson-cancelled', 'refund-balanced',
  'concurrent-edit-conflict', 'reopened-saved-state'];

async function verifyEmployeeResult(pool, result) {
  assert.deepEqual(result.scenarios, scenarios, 'Every required UI checkpoint must execute');
  assert.equal(result.paymentAttempts, 2);
  const counts = (await pool.query(`select
    (select count(*)::int from app.client_payment_records where student_id=$1) records,
    (select count(*)::int from app.payments where student_id=$1) payments,
    (select count(*)::int from app.account_adjustments where student_id=$1) refunds,
    (select count(*)::int from app.lessons where student_id=$1) lessons`, [result.studentId])).rows[0];
  assert.deepEqual(counts, { records: 1, payments: 1, refunds: 1, lessons: 2 });
  const money = (await pool.query(`select actual_payments_minor::text, adjustments_minor::text,
    balance_minor::text from app.commerce_student_account_projection where student_id=$1`, [result.studentId])).rows;
  assert.equal(money.length, 1);
  assert.equal(money[0].actual_payments_minor, '500000');
  assert.equal(money[0].adjustments_minor, '-350000');
  assert.equal(money[0].balance_minor, '0');
  const charges = (await pool.query(`select lesson_id, amount_minor::text from app.lesson_client_charge_facts
    where lesson_id=any($1::uuid[]) order by lesson_id`, [[result.completedLessonId, result.cancelledLessonId]])).rows;
  assert.equal(charges.length, 2);
  assert.equal(charges.find(r => r.lesson_id === result.completedLessonId).amount_minor, '150000');
  assert.equal(charges.find(r => r.lesson_id === result.cancelledLessonId).amount_minor, '0');
  const teachers = (await pool.query(`select lesson_id, amount_minor::text from app.lesson_teacher_compensation_facts
    where lesson_id=any($1::uuid[])`, [[result.completedLessonId, result.cancelledLessonId]])).rows;
  assert.equal(teachers.length, 2);
  assert.equal(teachers.find(r => r.lesson_id === result.completedLessonId).amount_minor, '70000');
  assert.equal(teachers.find(r => r.lesson_id === result.cancelledLessonId).amount_minor, '0');
  const histories = (await pool.query(`select
    (select count(*)::int from app.client_payment_status_events where payment_record_id=$1) payment_events,
    (select count(*)::int from app.audit_events where entity_id=$2) student_audits`, [result.paymentId, result.studentId])).rows[0];
  assert.equal(histories.payment_events, 1);
  assert(histories.student_audits >= 2, 'Creation and accepted edit must be audited');
}

// Hash all application table rows, including financial/audit/outbox histories.
// Only names, counts and hashes enter evidence; no row payload is written.
async function fingerprint(pool) {
  const tables = (await pool.query(`select tablename from pg_tables where schemaname='app' order by tablename`)).rows;
  const result = {};
  for (const { tablename } of tables) {
    assert(/^[a-z0-9_]+$/.test(tablename));
    const rows = (await pool.query(`select to_jsonb(t)::text as value from app."${tablename}" t order by to_jsonb(t)::text`)).rows;
    const hash = createHash('sha256');
    for (const row of rows) hash.update(row.value).update('\n');
    result[tablename] = { count: rows.length, sha256: hash.digest('hex') };
  }
  return result;
}

async function verifyLocalRestore({ pool, admin, output, databaseUrl }) {
  const source = new URL(databaseUrl);
  assert(['localhost', '127.0.0.1'].includes(source.hostname));
  assert(/^\/magiccrm_http_test_[a-f0-9]{32}$/.test(source.pathname));
  const name = `magiccrm_restore_test_${randomUUID().replaceAll('-', '')}`;
  const target = new URL(source); target.pathname = `/${name}`;
  const bin = process.env.POSTGRES_BIN ?? path.join(process.env.LOCALAPPDATA, 'MagicMusicCRMToolchain/postgresql-17/bin');
  const dump = path.join(output, 'synthetic-restore.dump');
  const env = { ...process.env, PGHOST: source.hostname, PGPORT: source.port,
    PGUSER: decodeURIComponent(source.username), PGPASSWORD: decodeURIComponent(source.password) };
  const before = await fingerprint(pool);
  const started = Date.now();
  let restored;
  let created = false;
  try {
    await run(path.join(bin, 'pg_dump.exe'), ['--format=custom', '--no-owner', '--no-acl',
      '--file', dump, '--dbname', source.pathname.slice(1)], { env, windowsHide: true, timeout: 120000 });
    await admin.query(`create database ${name}`); created = true;
    await run(path.join(bin, 'pg_restore.exe'), ['--exit-on-error', '--no-owner', '--no-acl',
      '--dbname', name, dump], { env, windowsHide: true, timeout: 120000 });
    restored = new Pool({ connectionString: target.toString() });
    const after = await fingerprint(restored);
    assert.deepEqual(after, before, 'Restored data and every history row must match the quiescent source');
    const issues = (await restored.query('select * from app.reconcile_v7_commerce()')).rows;
    assert.equal(issues.length, 0, 'Restored commerce must reconcile');
    const resultFile = path.join(output, 'employee-result.json');
    if (fs.existsSync(resultFile)) await verifyEmployeeResult(restored, JSON.parse(fs.readFileSync(resultFile, 'utf8')));
    const evidence = { status: 'PASS', scope: 'Fresh synthetic local backup, not production archive',
      durationMs: Date.now() - started, tableCount: Object.keys(after).length, tables: after };
    fs.writeFileSync(path.join(output, 'restore-result.json'), JSON.stringify(evidence, null, 2));
    return { tableCount: evidence.tableCount, durationMs: evidence.durationMs };
  } finally {
    if (restored) await restored.end();
    if (created) await admin.query(`drop database ${name} with (force)`);
    if (fs.existsSync(dump)) fs.unlinkSync(dump);
  }
}

module.exports = { verifyEmployeeResult, verifyLocalRestore, fingerprint };
