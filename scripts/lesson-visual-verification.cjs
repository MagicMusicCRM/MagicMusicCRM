const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

async function runLessonVisualAudit({pool, fixture, request, restartWithCompletion, runDeviceTest, output, check}) {
  const kinds = ['lesson', 'trial_lesson', 'partially_paid_lesson', 'free_lesson', 'paid_miss', 'unpaid_miss'];
  const studentId = fixture.students[0];
  await request('POST', `/crm/students/${studentId}/payment-records`, {
    amountMinor: '10000000', currencyCode: 'RUB', status: 'paid', method: 'cash',
    reason: 'Синтетическое покрытие визуальной матрицы', externalIdentifier: 'VISUAL-COVERAGE',
    branchId: fixture.branch, occurredAt: new Date().toISOString(),
  }, 201);
  const monday = new Date();
  monday.setUTCHours(11, 0, 0, 0);
  const weekday = monday.getUTCDay() || 7;
  monday.setUTCDate(monday.getUTCDate() - weekday + 1);
  const lessons = [];
  for (const [state, offset] of [['completed', -7], ['scheduled', 7]]) {
    for (const [index, kind] of kinds.entries()) {
      const at = new Date(monday);
      at.setUTCDate(at.getUTCDate() + offset + index);
      const free = ['trial_lesson', 'free_lesson', 'unpaid_miss'].includes(kind);
      const partial = kind === 'partially_paid_lesson';
      const decision = {settlementTypeKey: kind,
        teacherCompensationRuleKey: kind === 'trial_lesson' ? 'trial_lesson' : partial ? 'percent' : free ? 'none' : 'standard',
        ...(partial ? {teacherCreditedDurationMinutes: 30} : {}),
        clientDecisions: [{clientId: studentId,
          chargeType: free ? 'none' : 'personal_account',
          ...(!free ? {payerStudentId: studentId, basePriceMinor: '100000'} : {}),
          ...(partial ? {chargeDurationMinutes: 30} : {})}]};
      const lesson = await request('POST', '/crm/lessons', {
        clientRef: {type: 'student', id: studentId}, branchId: fixture.branch,
        teacherId: fixture.teachers[0], roomId: fixture.rooms[0],
        scheduledAt: at.toISOString(), durationMinutes: 60, isTrial: kind === 'trial_lesson',
        plannedSettlementReason: 'Синтетическая матрица типов и длительности расчёта',
        completionType: 'standard.success', clientChargeType: free ? 'none' : 'personal_account',
        clientChargeValue: free ? 0 : 1000, teacherCompensationType: free ? 'none' : 'hourly',
        teacherCompensationValue: free ? 0 : 700, financialDecision: decision,
      }, 201);
      lessons.push({id: lesson.id, kind, state, studentId, scheduledAt: at.toISOString()});
    }
  }
  const unpaidAt = new Date(monday);
  unpaidAt.setUTCDate(unpaidAt.getUTCDate() - 1);
  const unpaid = await request('POST', '/crm/lessons', {
    clientRef: {type: 'student', id: fixture.students[1]}, branchId: fixture.branch,
    teacherId: fixture.teachers[0], roomId: fixture.rooms[0], scheduledAt: unpaidAt.toISOString(),
    durationMinutes: 60, completionType: 'standard.success', clientChargeType: 'personal_account',
    clientChargeValue: 1000, teacherCompensationType: 'hourly', teacherCompensationValue: 700,
    financialDecision: {settlementTypeKey: 'lesson', teacherCompensationRuleKey: 'standard',
      clientDecisions: [{clientId: fixture.students[1], payerStudentId: fixture.students[1],
        chargeType: 'personal_account', basePriceMinor: '100000'}]},
  }, 201);
  lessons.push({id: unpaid.id, kind: 'lesson', state: 'settlement_pending', studentId: fixture.students[1], scheduledAt: unpaidAt.toISOString()});
  const baseUrl = await restartWithCompletion();
  const pastIds = lessons.filter(row => row.state === 'completed').map(row => row.id);
  let states;
  for (let retry = 0; retry < 60; retry++) {
    states = (await pool.query('select id,status from app.lessons where id=any($1::uuid[])', [pastIds])).rows;
    if (states.every(row => row.status === 'completed')) break;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert(states.every(row => row.status === 'completed'), `Completion states: ${JSON.stringify(states)}`);
  let deficit;
  for (let retry = 0; retry < 60; retry++) {
    deficit = (await pool.query('select lifecycle_state from app.lessons where id=$1', [unpaid.id])).rows[0];
    if (deficit.lifecycle_state === 'settlement_pending') break;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert.equal(deficit.lifecycle_state, 'settlement_pending');
  await check('Six live settlement types keep their fill and one lifecycle icon across four surfaces', () =>
    runDeviceTest('lesson_visuals_live_test.dart', 'lesson-visuals-windows.log', {
      HTTP_JOURNEY_FIXTURE: JSON.stringify({baseUrl, password: fixture.password,
        accounts: fixture.clientAuditAccounts, branchId: fixture.branch,
        teacherId: fixture.teachers[0], studentId, lessons}),
    }));
  const persisted = (await pool.query(`select l.id,l.status,l.lifecycle_state,p.decision,
    (select count(*)::int from app.lesson_client_charge_facts f where f.lesson_id=l.id) client_facts,
    (select count(*)::int from app.lesson_teacher_compensation_facts f where f.lesson_id=l.id) teacher_facts
    from app.lessons l join app.lesson_settlement_plans p on p.lesson_id=l.id
    where l.id=any($1::uuid[]) order by l.scheduled_at`, [lessons.map(row => row.id)])).rows;
  for (const row of persisted) {
    const expected = lessons.find(lesson => lesson.id === row.id);
    assert.equal(expected.state === 'settlement_pending' ? row.lifecycle_state : row.status, expected.state);
    assert.equal(row.decision.settlementTypeKey, expected.kind);
    assert.equal(row.client_facts, expected.state === 'completed' ? 1 : 0);
    assert.equal(row.teacher_facts, expected.state === 'completed' ? 1 : 0);
  }
  fs.writeFileSync(path.join(output, 'lesson-visuals-db.json'), JSON.stringify({lessons, persisted}, null, 2));
}
module.exports = {runLessonVisualAudit};
