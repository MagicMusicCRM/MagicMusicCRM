const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// Only invoked with the disposable runner's Pool and synthetic fixture.
async function runClientArchiveAudit({ pool, output, check, fixture, baseUrl, runDeviceTest }) {
  async function snapshot() {
    const result = {};
    for (const [key, table] of Object.entries({ subscriptions: 'subscriptions',
      lessonSnapshots: 'lesson_snapshots', clientFacts: 'lesson_client_charge_facts',
      teacherFacts: 'lesson_teacher_compensation_facts' })) {
      result[key] = (await pool.query(`select to_jsonb(t) as value from app.${table} t order by to_jsonb(t)::text`)).rows.map(row => row.value);
    }
    result.lessonIdentities = (await pool.query('select id,student_id from app.lessons order by id')).rows;
    return result;
  }
  const before = await snapshot();
  await check('Archive UI: staff access, preview cancellation, commit and replay', () =>
    runDeviceTest('client_archive_live_test.dart', 'client-archive-windows.log', {
      HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
        branchId: fixture.branch, accounts: fixture.clientAuditAccounts, studentId: fixture.students[0] }),
    }));
  const after = await snapshot();
  const evidence = { before, after, states: [] };
  await check('Archive preserves lesson identities, subscriptions and existing immutable facts', async () => {
    assert(before.lessonIdentities.length > 0, 'Fixture must contain linked lessons');
    assert(before.subscriptions.length > 0, 'Fixture must contain subscriptions');
    assert.deepEqual(after, before);
    return Object.fromEntries(Object.entries(before).map(([key, rows]) => [key, rows.length]));
  });
  await check('Archived entities remain in SQL with one audit record per archive', async () => {
    const native = JSON.parse(fs.readFileSync(path.join(output, 'archive-director.json'), 'utf8'));
    for (const entity of ['lead', 'student']) {
      const fact = native.facts.find(item => item.step === `${entity}-COMMIT`);
      assert(fact, `${entity}: no successful native commit evidence`);
      const table = entity === 'lead' ? 'leads' : 'students';
      const row = (await pool.query(`select id,version,deleted_at from app.${table} where id=$1`, [fact.id])).rows[0];
      const audit = (await pool.query(`select action,entity_type,entity_id,reason from app.audit_events
        where entity_id=$1 and action='crm.client_archived'`, [fact.id])).rows;
      evidence.states.push({ entity, row, audit });
      assert(row?.deleted_at, 'Entity must be archived, not physically deleted');
      assert.equal(Number(row.version), fact.after.version);
      assert.equal(audit.length, 1, 'Replay must not append a duplicate archive audit');
    }
  });
  fs.writeFileSync(path.join(output, 'client-archive-db.json'), JSON.stringify(evidence, null, 2));
}
module.exports = { runClientArchiveAudit };
