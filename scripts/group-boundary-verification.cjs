const assert = require('node:assert/strict'), { randomUUID } = require('node:crypto');
const fs = require('node:fs'), path = require('node:path');

async function runGroupBoundaryAudit({ pool, fixture, baseUrl, output, check }) {
  assert.equal(new URL(baseUrl).hostname, '127.0.0.1');
  const tokens = {}, requests = [], steps = [], facts = []; let currentStep = 'setup';
  async function call(role, method, endpoint, body, key = randomUUID()) {
    const response = await fetch(baseUrl + endpoint, { method,
      headers: { 'content-type': 'application/json', 'idempotency-key': key, 'x-request-id': randomUUID(), ...(tokens[role] ? { authorization: 'Bearer ' + tokens[role] } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000) });
    const data = await response.json(); requests.push({ step: currentStep, role, method, endpoint, status: response.status, ...(endpoint === '/auth/login' ? {} : { data }) });
    fs.writeFileSync(path.join(output, 'group-boundaries.json'), JSON.stringify({ steps, requests, facts }, null, 2));
    return { status: response.status, data };
  }
  const ok = r => { assert([200, 201].includes(r.status), `Expected success, got ${r.status}`); return r.data; };
  const denied = r => assert([403, 404].includes(r.status), `Expected denied scope, got ${r.status}`);
  async function verify(id, role, description, work) {
    currentStep = id; const start = requests.length;
    await check(id + ': ' + description, async () => {
      try { await work(); steps.push({ id, role, description, status: 'PASS', requestStart: start, requestEnd: requests.length }); }
      catch (error) { steps.push({ id, role, description, status: 'FAIL', failure: error.message, requestStart: start, requestEnd: requests.length }); throw error; }
    });
    fs.writeFileSync(path.join(output, 'group-boundaries.json'), JSON.stringify({ steps, requests, facts }, null, 2));
  }
  for (const account of fixture.clientAuditAccounts) {
    const login = ok(await call(account.role, 'POST', '/auth/login', { email: account.email, password: fixture.password })); tokens[account.role] = login.session.accessToken;
  }
  const foreignBranch = ok(await call('director', 'POST', '/crm/branches', { name: 'GROUP-FOREIGN-BRANCH', weeklyHours: [{ weekday: 1, open: '08:00', close: '22:00' }] }));
  const foreignRoom = ok(await call('director', 'POST', '/crm/rooms', { name: 'GROUP-FOREIGN-ROOM', branchId: foreignBranch.id, capacity: 8 }));
  // Assignment belongs only to this disposable fixture and enables valid foreign references.
  await pool.query("insert into app.teacher_branches(teacher_id,branch_id,active_from,active_until) values ($1,$2,'2020-01-01','2100-12-31')", [fixture.teachers[0], foreignBranch.id]);
  const foreign = ok(await call('director', 'POST', '/crm/groups', { name: 'GROUP-BOUNDARY-FOREIGN', teacherId: fixture.teachers[0], branchId: foreignBranch.id, roomId: foreignRoom.id, pricePerLesson: 1000 }));
  const own = ok(await call('director', 'POST', '/crm/groups', { name: 'GROUP-BOUNDARY-OWN', teacherId: fixture.teachers[0], branchId: fixture.branch, roomId: fixture.rooms[0], pricePerLesson: 1000 }));
  for (const [id, method, endpoint, body] of [
    ['FOREIGN-GET', 'GET', `/crm/groups/${foreign.id}`], ['FOREIGN-MEMBERS', 'GET', `/crm/groups/${foreign.id}/students`],
    ['FOREIGN-ADD', 'POST', `/crm/groups/${foreign.id}/students`, { studentId: fixture.students[0] }],
    ['FOREIGN-REMOVE', 'DELETE', `/crm/groups/${foreign.id}/students/${fixture.students[0]}`],
    ['FOREIGN-PREVIEW', 'POST', `/crm/groups/${foreign.id}/archive-preview`, {}],
    ['FOREIGN-ARCHIVE', 'POST', `/crm/groups/${foreign.id}/archive`, { expectedVersion: 1, confirm: true, reasonText: 'FOREIGN-REJECTED', effectiveDate: new Date().toISOString().slice(0, 10) }],
    ['FOREIGN-UPDATE', 'PATCH', `/crm/groups/${foreign.id}`, { name: 'FORBIDDEN-CHANGE' }],
  ]) await verify(id, 'manager', 'Управляющий: чужая группа недоступна для ' + method + ' ' + id, async () => denied(await call('manager', method, endpoint, body)));
  await verify('FOREIGN-LIST', 'manager', 'Список управляющего исключает чужую группу', async () => {
    const result = ok(await call('manager', 'GET', '/crm/groups')); assert(!result.items.some(g => g.id === foreign.id));
  });
  await verify('FOREIGN-CREATE', 'manager', 'Создание группы в чужом филиале отклонено', async () => denied(await call('manager', 'POST', '/crm/groups', { name: 'FORBIDDEN-CREATE', teacherId: fixture.teachers[0], branchId: foreignBranch.id, roomId: foreignRoom.id })));
  for (const role of ['client', 'teacher']) {
    await verify(`MEMBER-WRITE-${role}`, role, 'Роль не меняет состав произвольной группы', async () => denied(await call(role, 'POST', `/crm/groups/${own.id}/students`, { studentId: fixture.students[0] })));
    await verify(`GROUP-CREATE-${role}`, role, 'Роль не создаёт учебные группы', async () => denied(await call(role, 'POST', '/crm/groups', { name: `FORBIDDEN-${role}`, teacherId: fixture.teachers[0], branchId: fixture.branch, roomId: fixture.rooms[0] })));
  }
  await verify('MISSING-STUDENT', 'director', 'Несуществующий ученик отклонён без HTTP 500', async () => {
    assert.equal((await call('director', 'POST', `/crm/groups/${own.id}/students`, { studentId: randomUUID() })).status, 404);
  });
  await verify('MEMBER-REJOIN', 'director', 'Повторное добавление не дублирует состав, после выхода можно вступить снова', async () => {
    const endpoint = `/crm/groups/${own.id}/students`, body = { studentId: fixture.students[1] };
    ok(await call('director', 'POST', endpoint, body)); ok(await call('director', 'POST', endpoint, body));
    assert.equal(ok(await call('director', 'GET', endpoint)).items.length, 1);
    ok(await call('director', 'DELETE', `${endpoint}/${fixture.students[1]}`)); assert.equal(ok(await call('director', 'GET', endpoint)).items.length, 0);
    ok(await call('director', 'POST', endpoint, body)); assert.equal(ok(await call('director', 'GET', endpoint)).items.length, 1);
    const rows = (await pool.query('select id,left_at from app.group_students where group_id=$1', [own.id])).rows;
    assert.equal(rows.length, 1); assert.equal(rows[0].left_at, null); facts.push({ step: currentStep, memberships: rows });
  });
  currentStep = 'setup-future-plan';
  const day = new Date(Date.UTC(new Date().getUTCFullYear() + 1, 0, 15, 10));
  const nextDay = new Date(day.getTime() + 86400000);
  const plan = ok(await call('director', 'POST', '/crm/schedule-plans', { kind: 'group', title: 'GROUP-BLOCKER-PLAN', groupId: own.id,
    activeFrom: day.toISOString().slice(0, 10), activeUntil: nextDay.toISOString().slice(0, 10),
    participants: [{ studentId: fixture.students[1], subscriptionId: fixture.subscriptions[1] }],
    rows: [{ teacherId: fixture.teachers[0], roomId: fixture.rooms[0], branchId: fixture.branch, weekday: day.getUTCDay() || 7,
      beginTime: '13:00', durationMinutes: 60,
      financialDecision: { settlementTypeKey: 'lesson', teacherCompensationRuleKey: 'standard', clientDecisions: [{ clientId: fixture.students[1], payerStudentId: fixture.students[1], chargeType: 'subscription', subscriptionId: fixture.subscriptions[1] }] } }] }));
  const lessons = (await pool.query('select l.id from app.lessons l join app.schedule_series s on s.id=l.series_id where s.plan_id=$1', [plan.id])).rows;
  assert.equal(lessons.length, 1); const lesson = lessons[0];
  await verify('FUTURE-LESSON-BLOCKER', 'director', 'Будущее занятие блокирует архивирование группы', async () => {
    const preview = ok(await call('director', 'POST', `/crm/groups/${own.id}/archive-preview`, {}));
    assert.equal(preview.canArchive, false); assert(preview.blockers.some(b => b.code === 'FUTURE_LESSONS' && b.count === 1));
    assert(preview.blockers.some(b => b.code === 'ACTIVE_RECURRING_SERIES' && b.count === 1));
    assert(preview.blockers.some(b => b.code === 'ACTIVE_SCHEDULE_PLANS' && b.count === 1));
    const response = await call('director', 'POST', `/crm/groups/${own.id}/archive`, { expectedVersion: 1, confirm: true, reasonText: 'BLOCKED-ARCHIVE', effectiveDate: new Date().toISOString().slice(0, 10) });
    assert.equal(response.status, 422);
    const row = (await pool.query('select lifecycle_state,deleted_at from app.groups where id=$1', [own.id])).rows[0]; assert.equal(row.lifecycle_state, 'active'); assert.equal(row.deleted_at, null);
  });
  await verify('FUTURE-ASSIGNMENT-BLOCKER', 'director', 'При будущем занятии нельзя сменить аудиторию группы через API', async () => {
    assert.equal((await call('director', 'PATCH', `/crm/groups/${own.id}`, { roomId: fixture.rooms[1] })).status, 422);
    const row = (await pool.query('select room_id from app.groups where id=$1', [own.id])).rows[0]; assert.equal(row.room_id, fixture.rooms[0]);
  });
  await verify('SQL-PRESERVED', 'director', 'Запреты сохранили чужую группу и исходные ссылки будущего занятия', async () => {
    const group = (await pool.query('select name,lifecycle_state from app.groups where id=$1', [foreign.id])).rows[0]; assert.equal(group.name, 'GROUP-BOUNDARY-FOREIGN'); assert.equal(group.lifecycle_state, 'active');
    const row = (await pool.query('select group_id,room_id,lifecycle_state,deleted_at from app.lessons where id=$1', [lesson.id])).rows[0]; assert.equal(row.group_id, own.id); assert.equal(row.deleted_at, null); assert.equal(row.lifecycle_state, 'scheduled');
    facts.push({ step: currentStep, group, lesson: row });
  });
  fs.writeFileSync(path.join(output, 'group-boundaries.json'), JSON.stringify({ steps, requests, facts, ownGroupId: own.id, foreignGroupId: foreign.id, lessonId: lesson.id }, null, 2));
}
module.exports = { runGroupBoundaryAudit };
