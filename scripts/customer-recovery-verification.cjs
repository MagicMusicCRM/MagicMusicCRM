const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

function automaticTrialDraft(stored) {
  return { settlementTypeKey: stored.settlementTypeKey,
    clientDecisions: stored.clientDecisions,
    teacherCompensationRuleKey: 'trial_lesson', teacherCompensationSource: 'automatic' };
}

async function verifyRecovery({ pool, fixture, request, check, restart, exportReport, completeCandidate }) {
  const tables = ['lessons', 'lesson_snapshots', 'lesson_settlement_plans',
    'lesson_settlement_plan_revisions', 'lesson_client_charge_facts',
    'lesson_teacher_compensation_facts', 'lesson_reservations'];
  async function fingerprint() {
    const result = {};
    for (const table of tables) result[table] = (await pool.query(
      `select count(*)::int count, md5(coalesce(string_agg(to_jsonb(t)::text, '' order by to_jsonb(t)::text), '')) hash from app.${table} t`,
    )).rows[0];
    return result;
  }
  async function current() {
    const rows = (await pool.query(`select l.id,l.version,l.scheduled_at,l.duration_minutes,p.decision
      from app.lessons l join app.lesson_settlement_plans p on p.lesson_id=l.id
      where l.branch_id=$1 and l.lifecycle_state='scheduled'
        and p.decision->>'settlementTypeKey'='trial_lesson'`, [fixture.branch])).rows;
    assert.equal(rows.length, 1, 'Exactly one current synthetic trial is required');
    return rows[0];
  }
  // Real completed facts distinguish filtering from merely accepting a query.
  const reportIds = {};
  for (const [index, rule] of ['trial_lesson', 'standard'].entries()) {
    const financialDecision = { settlementTypeKey: 'trial_lesson',
      teacherCompensationRuleKey: rule, teacherCompensationSource: 'manual',
      clientDecisions: [{ clientId: fixture.students[0], chargeType: 'none' }] };
    const lesson = await request('POST', '/crm/lessons', {
      clientRef: { type: 'student', id: fixture.students[0] },
      teacherId: fixture.teachers[0], roomId: fixture.rooms[0], branchId: fixture.branch,
      scheduledAt: `2026-09-14T${index ? '10' : '08'}:00:00Z`, durationMinutes: 60,
      completionType: 'standard.success', clientChargeType: 'none', clientChargeValue: 0,
      teacherCompensationType: 'none', teacherCompensationValue: 0, financialDecision,
      plannedSettlementReason: 'Проверка совместимости отчёта',
    }, 201);
    reportIds[rule] = lesson.id;
    const snapshot = (await pool.query(
      'select teacher_compensation_type, teacher_compensation_value from app.lesson_snapshots where lesson_id=$1',
      [lesson.id],
    )).rows[0];
    assert.equal(snapshot.teacher_compensation_type, 'hourly', 'Administrator creation must snapshot the effective teacher rate');
    assert.equal(Number(snapshot.teacher_compensation_value), 700, 'Report fixture must contain the real standard rate before completion');
  }
  await completeCandidate();
  let completed = false;
  for (let attempt = 0; attempt < 60; attempt++) {
    completed = Number((await pool.query("select count(*) from app.lessons where id=any($1::uuid[]) and lifecycle_state='successfully_completed'",
      [Object.values(reportIds)])).rows[0].count) === 2;
    if (completed) break;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert(completed, 'The real completion worker must create both report facts');
  async function reports() {
    const result = {};
    for (const rule of ['trial_lesson', 'standard']) {
      const query = new URLSearchParams({ from: '2026-09-14T00:00:00Z', to: '2026-09-15T00:00:00Z',
        branchId: fixture.branch, teacherId: fixture.teachers[0], compensationRuleKey: rule });
      const report = await request('GET', `/crm/reports/teacher-stats?${query}`);
      assert.equal(report.totals.completedLessons, 1);
      assert.equal(report.totals.accruedTotal, rule === 'trial_lesson' ? 0 : 700);
      assert.deepEqual(report.items.flatMap(item => item.units.flatMap(unit => unit.lessonIds)), [reportIds[rule]]);
      result[rule] = { report, export: await exportReport(query.toString()) };
    }
    return result;
  }
  const candidateReports = await reports();
  const source = await current();
  assert.equal(source.decision.teacherCompensationRuleKey, 'standard');
  assert.equal(source.decision.teacherCompensationSource, 'manual');
  const beforeSwitch = await fingerprint();
  await restart();
  await check('Recovery preserves populated trial/standard teacher totals, lesson IDs and XLSX export', async () => {
    assert.deepEqual(await reports(), candidateReports);
    assert.deepEqual(await fingerprint(), beforeSwitch, 'Reports and export must not change financial history');
  });
  await check('Recovery image reads candidate trial and preserves all lesson history at startup', async () => {
    assert.deepEqual(await fingerprint(), beforeSwitch);
    await request('GET', `/crm/lessons?lessonId=${source.id}&branchId=${fixture.branch}`);
    assert.deepEqual((await current()).decision, source.decision);
  });
  const successorAt = new Date(new Date(source.scheduled_at).getTime() + 3600000).toISOString();
  // Persisted plans also contain server-owned fields, which are not API input.
  const automaticDecision = automaticTrialDraft(source.decision);
  const body = { expectedVersion: Number(source.version), reasonText: 'Проверка аварийного переноса',
    successor: { scheduledAt: successorAt }, successorFinancialDecision: automaticDecision };
  await check('Recovery rejects arbitrary administrator rates without changing facts', async () => {
    const before = await fingerprint();
    await request('POST', `/crm/lessons/${source.id}/reschedule/preview`, {
      ...body, successorFinancialDecision: { ...automaticDecision, teacherCompensationRuleKey: 'fixed',
        teacherCompensationSource: 'manual', teacherCompensationValueMinor: '999999' },
    }, 403);
    assert.deepEqual(await fingerprint(), before);
  });
  await check('Recovery reschedules candidate manual trial with pure preview and idempotent commit', async () => {
    const before = await fingerprint();
    const preview = await request('POST', `/crm/lessons/${source.id}/reschedule/preview`, body, 201);
    assert.equal(preview.canConfirm, true);
    assert.deepEqual(await fingerprint(), before);
    const command = { ...body, previewToken: preview.previewToken, confirm: true };
    const key = randomUUID();
    await request('POST', `/crm/lessons/${source.id}/reschedule`, command, 201, { key });
    const afterCommit = await fingerprint();
    await request('POST', `/crm/lessons/${source.id}/reschedule`, command, 201, { key });
    assert.deepEqual(await fingerprint(), afterCommit, 'Retry must not append duplicate facts');
    const moved = await current();
    assert.equal(new Date(moved.scheduled_at).toISOString(), successorAt);
    assert.equal(moved.duration_minutes, source.duration_minutes);
    for (const field of ['teacherCompensationRuleKey', 'teacherCompensationSource',
      'teacherCompensationValueMinor', 'teacherCreditedDurationMinutes']) {
      assert.equal(moved.decision[field], source.decision[field], `Preserve ${field}`);
    }
    for (const decision of moved.decision.clientDecisions) {
      assert.equal(decision.chargeType, 'none');
      assert.equal(decision.chargeDurationMinutes, 0);
      assert.equal(decision.subscriptionId, undefined);
    }
  });
}
module.exports = { verifyRecovery, automaticTrialDraft };
