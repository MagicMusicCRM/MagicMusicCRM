// API boundaries against the existing local runtime and disposable database.
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

async function runFamilyBoundaryAudit({ pool, fixture, baseUrl, output, check }) {
  assert.equal(new URL(baseUrl).hostname, '127.0.0.1');
  const tokens = {}, requests = [], steps = [];
  let currentStep = 'setup';
  async function call(role, method, endpoint, body) {
    const response = await fetch(baseUrl + endpoint, {
      method, headers: { 'content-type': 'application/json',
        ...(tokens[role] ? { authorization: 'Bearer ' + tokens[role] } : {}),
        'idempotency-key': randomUUID() },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    const data = await response.json();
    requests.push({ step: currentStep, role, method, endpoint, status: response.status,
      ...(endpoint === '/auth/login' ? {} : { data }) });
    return { status: response.status, data };
  }
  async function verify(id, role, description, work) {
    currentStep = id;
    const start = requests.length;
    await check(id + ': ' + description, async () => {
      try {
        await work();
        steps.push({ id, role, description, status: 'PASS', requestStart: start, requestEnd: requests.length });
      } catch (error) {
        steps.push({ id, role, description, status: 'FAIL', failure: error.message, requestStart: start, requestEnd: requests.length });
        throw error;
      }
    });
  }
  const denied = result => assert([403, 404].includes(result.status), 'Expected scope denial 403/404, got ' + result.status);
  const ok = result => { assert([200, 201].includes(result.status), 'Setup expected success, got ' + result.status); return result.data; };
  for (const account of fixture.clientAuditAccounts) {
    const login = ok(await call(account.role, 'POST', '/auth/login', { email: account.email, password: fixture.password }));
    tokens[account.role] = login.session.accessToken;
    assert(tokens[account.role]);
  }
  const foreignBranch = (await pool.query("insert into app.branches(name,timezone_name) values ('FAMILY-BOUNDARY foreign','Europe/Moscow') returning id")).rows[0].id;
  const staffScope = (await pool.query(`select u.role, u.id as user_id, a.branch_id
    from app.users u join app.profiles p on p.user_id=u.id
    join app.staff_members s on s.profile_id=p.id
    join app.staff_branch_assignments a on a.staff_member_id=s.id
    where u.role in ('admin','manager') order by u.role, a.branch_id`)).rows;
  assert.equal(staffScope.length, 2);
  assert(staffScope.every(row => row.branch_id === fixture.branch && row.branch_id !== foreignBranch));
  const foreignLead = (await pool.query("insert into app.leads(first_name,last_name,branch_id) values ('Граница','FAMILY-BOUNDARY',$1) returning id", [foreignBranch])).rows[0].id;
  const ownFamily = ok(await call('director', 'POST', '/crm/families', { name: 'FAMILY-BOUNDARY own', branchId: fixture.branch }));
  const unrelatedUser = (await pool.query("insert into app.users(email,role,is_app_account) values ($1,'client',false) returning id", ['family-' + randomUUID() + '@example.test'])).rows[0].id;
  const unrelatedProfile = (await pool.query("insert into app.profiles(user_id,first_name,last_name) values ($1,'Чужой','FAMILY-BOUNDARY') returning id", [unrelatedUser])).rows[0].id;
  const unrelatedStudent = (await pool.query('insert into app.students(profile_id,branch_id) values ($1,$2) returning id', [unrelatedProfile, fixture.branch])).rows[0].id;
  const otherStudentFamily = ok(await call('director', 'POST', '/crm/families', { name: 'FAMILY-BOUNDARY other student', branchId: fixture.branch }));
  ok(await call('director', 'POST', '/crm/families/' + otherStudentFamily.id + '/members',
    { entityType: 'student', entityId: unrelatedStudent, role: 'child' }));
  const teacherLinkCount = (await pool.query('select count(*)::int n from app.lessons where teacher_id=$1 and student_id=$2 and deleted_at is null',
    [fixture.teachers[0], unrelatedStudent])).rows[0].n;
  assert.equal(teacherLinkCount, 0, 'Unassigned student fixture must have no lessons with this teacher');
  for (const role of ['client', 'teacher']) {
    await verify('FAMILY-' + role + '-FOREIGN-STUDENT', role, 'Чужая семья ученика недоступна', async () => {
      denied(await call(role, 'GET', '/crm/families/by-entity/student/' + unrelatedStudent));
    });
    await verify('FAMILY-' + role + '-WRITE-DENIED', role, 'Создание семьи запрещено роли', async () => {
      denied(await call(role, 'POST', '/crm/families', { name: 'FAMILY-BOUNDARY forbidden' }));
    });
  }
  for (const role of ['admin', 'manager']) {
    const roleForeignLead = (await pool.query("insert into app.leads(first_name,last_name,branch_id) values ($1,'FAMILY-BOUNDARY',$2) returning id", [role, foreignBranch])).rows[0].id;
    const family = ok(await call('director', 'POST', '/crm/families', { name: 'FAMILY-BOUNDARY ' + role, branchId: foreignBranch }));
    const member = ok(await call('director', 'POST', '/crm/families/' + family.id + '/members',
      { entityType: 'lead', entityId: roleForeignLead, role: 'parent' }));
    await verify('FAMILY-' + role + '-FOREIGN-READ', role, 'Семья чужого филиала недоступна', async () => {
      denied(await call(role, 'GET', '/crm/families/by-entity/lead/' + roleForeignLead));
    });
    await verify('FAMILY-' + role + '-FOREIGN-CREATE', role, 'Нельзя создать семью в чужом филиале', async () => {
      denied(await call(role, 'POST', '/crm/families', { name: 'FAMILY-BOUNDARY foreign attempt', branchId: foreignBranch }));
    });
    await verify('FAMILY-' + role + '-FOREIGN-LINK', role, 'Нельзя связать запись чужого филиала', async () => {
      denied(await call(role, 'POST', '/crm/families/' + ownFamily.id + '/members',
        { entityType: 'lead', entityId: roleForeignLead, role: 'parent' }));
    });
    await verify('FAMILY-' + role + '-FOREIGN-PAYER', role, 'Нельзя назначить плательщика в чужой семье', async () => {
      denied(await call(role, 'POST', '/crm/families/' + family.id + '/primary-payer/' + member.id));
    });
    await verify('FAMILY-' + role + '-FOREIGN-REMOVE', role, 'Нельзя удалить связь чужой семьи', async () => {
      denied(await call(role, 'DELETE', '/crm/family-members/' + member.id));
    });
  }
  await verify('FAMILY-MISSING-ENTITY', 'director', 'Нельзя добавить несуществующего участника', async () => {
    const result = await call('director', 'POST', '/crm/families/' + ownFamily.id + '/members',
      { entityType: 'student', entityId: randomUUID(), role: 'child' });
    assert([400, 404, 409].includes(result.status), 'Expected missing entity rejection, got ' + result.status);
  });
  const payerFamily = ok(await call('director', 'POST', '/crm/families', { name: 'FAMILY-BOUNDARY payer', branchId: fixture.branch }));
  const payer = ok(await call('director', 'POST', '/crm/families/' + payerFamily.id + '/members',
    { entityType: 'student', entityId: fixture.students[0], role: 'payer' }));
  const secondLead = (await pool.query("insert into app.leads(first_name,last_name,branch_id) values ('Второй','FAMILY-BOUNDARY',$1) returning id", [fixture.branch])).rows[0].id;
  ok(await call('director', 'POST', '/crm/families/' + payerFamily.id + '/members', { entityType: 'lead', entityId: secondLead, role: 'child' }));
  ok(await call('director', 'POST', '/crm/families/' + payerFamily.id + '/primary-payer/' + payer.id));
  await verify('FAMILY-PAYER-REMOVE-CONSISTENCY', 'director', 'После удаления плательщик не указывает на удалённую связь', async () => {
    ok(await call('director', 'DELETE', '/crm/family-members/' + payer.id));
    const value = ok(await call('director', 'GET', '/crm/families/by-entity/lead/' + secondLead));
    assert.equal(value.family.id, payerFamily.id);
    assert(value.family.primaryPayerMemberId === null || value.members.some(member => member.id === value.family.primaryPayerMemberId),
      'Family primary payer points to removed member');
  });
  const db = {};
  for (const table of ['families', 'family_members']) {
    db[table] = (await pool.query('select to_jsonb(row) value from app.' + table + ' row order by id')).rows.map(row => row.value);
  }
  fs.writeFileSync(path.join(output, 'family-boundary.json'), JSON.stringify({
    scope: 'Direct authenticated local HTTP; no UI claim; synthetic records only', fixture: { ownBranch: fixture.branch, foreignBranch, foreignLead, unrelatedStudent, teacherLinkCount, staffScope },
    steps, requests, db }, null, 2));
}
module.exports = { runFamilyBoundaryAudit };
