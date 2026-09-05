// Real HTTP journeys against the application and a disposable local database.
// No mocked controllers, guards, repositories or financial commands.
const assert = require('node:assert/strict');
const { randomUUID, randomBytes, createHash } = require('node:crypto');
const { spawn, execFileSync } = require('node:child_process');
const { once } = require('node:events');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const { createRequire } = require('node:module');

const root = path.resolve(__dirname, '..');
const server = path.join(root, 'server');
function sourceFingerprint() {
  const names = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard',
    'lib', 'server/src', 'server/db', 'integration_test', 'scripts',
    'pubspec.yaml', 'pubspec.lock', 'server/package.json', 'server/package-lock.json'], { cwd: root })
    .toString().split('\0').filter(Boolean).sort();
  const hash = createHash('sha256');
  for (const name of names) {
    if (!fs.existsSync(path.join(root, name))) continue;
    hash.update(name).update('\0').update(fs.readFileSync(path.join(root, name))).update('\0');
  }
  return hash.digest('hex');
}
const testedSource = sourceFingerprint();
const revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root }).toString().trim();
const dependency = createRequire(path.join(server, 'package.json'));
dependency('ts-node').register({ project: path.join(server, 'tsconfig.json'), transpileOnly: true });
const { Pool } = dependency('pg');
const { MigrationRunner } = require(path.join(server, 'src/db/migration-runner'));
const { PasswordService } = require(path.join(server, 'src/auth/password.service'));
const runId = randomUUID().replaceAll('-', '');
const databaseName = `magiccrm_http_test_${runId}`;
const output = path.join(root, 'dist', 'http-journeys', runId);
fs.mkdirSync(output, { recursive: true });
const results = [];
let token;
let baseUrl;
let api;
let pool;
let admin;
let created = false;
let requestCount = 0;
let serverErrorCount = 0;

async function stopApi() {
  const child = api;
  api = undefined;
  if (child && child.exitCode === null && child.signalCode === null) {
    const stopped = once(child, 'exit');
    child.kill();
    await stopped;
  }
}

async function check(name, work) {
  try {
    const detail = await work();
    results.push({ name, status: 'PASS', ...(detail ? { detail } : {}) });
    console.log(`PASS ${name}`);
  } catch (error) {
    // Synthetic fixture data only; never print request headers or login bodies.
    const detail = String(error.message).replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, ':id');
    results.push({ name, status: 'FAIL', detail });
    console.log(`FAIL ${name}: ${detail}`);
  }
}

async function request(method, endpoint, body, expected = 200, options = {}) {
  requestCount++;
  const headers = { 'content-type': 'application/json', 'x-request-id': randomUUID() };
  if (token && options.auth !== false) headers.authorization = `Bearer ${token}`;
  if (method !== 'GET') headers['idempotency-key'] = options.key ?? randomUUID();
  const response = await fetch(`${baseUrl}${endpoint}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const data = await response.json();
  if (response.status >= 500) serverErrorCount++;
  const allowed = Array.isArray(expected) ? expected : [expected];
  assert(allowed.includes(response.status),
    `${method} ${endpoint}: expected ${allowed.join('/')}, got ${response.status} (${data.code ?? data.message ?? 'no detail'})`);
  return data;
}

async function seed() {
  const email = `http-${runId}@example.test`;
  const employeeEmail = `employee-${runId}@example.test`;
  const password = `Test-${randomBytes(18).toString('hex')}!`;
  const passwordHash = await new PasswordService().hash(password);
  async function person(role, name, credentials = false, loginEmail = email) {
    const user = (await pool.query(
      `insert into app.users (email, role, email_verified_at, is_app_account, password_hash)
       values ($1,$2,now(),true,$3) returning id`,
      [credentials ? loginEmail : `${name}-${runId}@example.test`, role, credentials ? passwordHash : null],
    )).rows[0].id;
    const profile = (await pool.query(
      `insert into app.profiles (user_id, first_name, last_name) values ($1,$2,'HTTP test') returning id`,
      [user, name],
    )).rows[0].id;
    return { user, profile };
  }
  await person('system_admin', 'Operator', true);
  await person('director', 'Employee', true, employeeEmail);
  const branch = (await pool.query(
    `insert into app.branches (name, timezone_name) values ('HTTP test','Europe/Moscow') returning id`,
  )).rows[0].id;
  await pool.query(`insert into app.branch_hours (branch_id, weekday, open_local, close_local)
    select $1, day, '08:00', '22:00' from generate_series(1,7) day`, [branch]);
  const rooms = [];
  const teachers = [];
  const students = [];
  const subscriptions = [];
  for (let index = 0; index < 2; index++) {
    rooms.push((await pool.query(`insert into app.rooms (branch_id,name) values ($1,$2) returning id`,
      [branch, `Room ${index}`])).rows[0].id);
    const teacher = await person('teacher', `Teacher${index}`);
    const teacherId = (await pool.query(`insert into app.teachers (profile_id) values ($1) returning id`,
      [teacher.profile])).rows[0].id;
    teachers.push(teacherId);
    await pool.query(`insert into app.teacher_branches (teacher_id,branch_id,active_from,active_until)
      values ($1,$2,'2020-01-01','2100-12-31')`, [teacherId, branch]);
    await pool.query(`insert into app.teacher_availability_rules
      (teacher_id,kind,available,timezone_name,weekday,local_start,local_end,valid_from,valid_until)
      select $1,'recurring',true,'Europe/Moscow',day,'08:00','22:00','2020-01-01','2100-12-31'
      from generate_series(1,7) day`, [teacherId]);
    await pool.query(`insert into app.teacher_rates (teacher_id,rate,effective_from)
      values ($1,$2,'2020-01-01')`, [teacherId, 700 + index * 100]);
    const student = await person('client', `Student${index}`);
    const studentId = (await pool.query(`insert into app.students (profile_id,branch_id) values ($1,$2) returning id`,
      [student.profile, branch])).rows[0].id;
    students.push(studentId);
    subscriptions.push((await pool.query(`insert into app.subscriptions
      (student_id,payer_student_id,funding_mode,lessons_total,lessons_used,status)
      values ($1,$1,'legacy',12,0,'active') returning id`, [studentId])).rows[0].id);
  }
  return { email, employeeEmail, password, branch, rooms, teachers, students, subscriptions };
}

async function startApi(fixture, completionWorker = false) {
  const listener = net.createServer();
  listener.listen(0, '127.0.0.1');
  await once(listener, 'listening');
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  // Empty working directory prevents ConfigModule from loading a developer's .env.
  const working = path.join(output, 'runtime');
  fs.mkdirSync(working, { recursive: true });
  const env = {};
  for (const key of ['SystemRoot', 'WINDIR', 'PATH', 'Path', 'TEMP', 'TMP', 'HOME', 'USERPROFILE']) {
    if (process.env[key]) env[key] = process.env[key];
  }
  Object.assign(env, {
    NODE_ENV: 'test', PORT: String(port), DATABASE_URL: pool.options.connectionString,
    JWT_ACCESS_SECRET: randomBytes(32).toString('hex'),
    MANAGED_PASSWORD_ENCRYPTION_KEY: randomBytes(32).toString('hex'),
    AUTH_OTP_BYPASS_EMAILS: `${fixture.email},${fixture.employeeEmail}`,
    TS_NODE_PROJECT: path.join(server, 'tsconfig.json'),
    V4_ACCESS_MODE: 'v4', V4_ACCESS_KILL_SWITCH: 'false',
    V4_SCHEDULE_MODE: 'v4', V4_SCHEDULE_KILL_SWITCH: 'false', V4_PARITY_UNEXPLAINED_DIFFS: '0',
    PLATFORM_OUTBOX_WORKER_ENABLED: 'false', LESSON_COMPLETION_WORKER_ENABLED: String(completionWorker),
    LESSON_COMPLETION_WORKER_POLL_MS: '1000',
    INSTALLMENT_DUE_WORKER_ENABLED: 'false', LESSON_REMINDERS_ENABLED: 'false',
    TASK_REMINDERS_ENABLED: 'false', SCHEDULE_SERIES_AUTOEXTEND: 'false',
    FILE_STORAGE_ROOT: path.join(working, 'storage'),
  });
  fs.mkdirSync(env.FILE_STORAGE_ROOT, { recursive: true });
  const log = fs.openSync(path.join(output, 'api.log'), 'w');
  api = spawn(process.execPath, ['-r', dependency.resolve('ts-node/register/transpile-only'),
    path.join(server, 'src/main.ts')], { cwd: working, env, windowsHide: true, stdio: ['ignore', log, log] });
  fs.closeSync(log);
  baseUrl = `http://127.0.0.1:${port}/api`;
  for (let attempt = 0; attempt < 100; attempt++) {
    if (api.exitCode !== null) throw Error(`Local API exited with ${api.exitCode}; inspect synthetic api.log`);
    try {
      const response = await fetch(`${baseUrl}/health/live`, { signal: AbortSignal.timeout(500) });
      if (response.ok) return;
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  throw Error('Local API did not start within 20 seconds');
}

async function journeys(f) {
  const login = await request('POST', '/auth/login', { email: f.email, password: f.password }, 200, { auth: false });
  assert(login.session?.accessToken, 'Local fixture login must issue a session');
  token = login.session.accessToken;
  await check('HTTP authentication and current capabilities', async () => {
    const access = await request('GET', '/access/me');
    assert.equal(access.role, 'system_admin');
    await request('GET', '/access/me', undefined, 401, { auth: false });
  });
  const source = await request('POST', '/crm/client-config/sources', { canonicalName: `http_${runId}`, displayName: 'HTTP fixture' }, 201);
  const field = await request('POST', '/crm/client-config/fields', { key: `http_${runId}`, label: 'HTTP fixture', valueType: 'text' }, 201);
  for (const [endpoint, fieldName] of [[`sources/${source.id}`, 'displayName'], [`fields/${field.id}`, 'label']]) {
    await check(`Reject null ${fieldName} without HTTP 500`, () => request('PATCH', `/crm/client-config/${endpoint}`,
      { expectedVersion: 1, [fieldName]: null }, [400, 422]));
    await check(`Reject blank ${fieldName} without HTTP 500`, () => request('PATCH', `/crm/client-config/${endpoint}`,
      { expectedVersion: 1, [fieldName]: '   ' }, [400, 422]));
  }
  await check('Reject null names on a system source without changing it', async () => {
    const original = (await pool.query(`select id,canonical_name,display_name,version from app.lead_sources
      where is_system=true order by id limit 1`)).rows[0];
    assert(original, 'Migrations must provide the system source');
    for (const name of ['canonicalName', 'displayName']) {
      await request('PATCH', `/crm/client-config/sources/${original.id}`,
        { expectedVersion: Number(original.version), [name]: null }, 400);
    }
    const unchanged = (await pool.query(`select id,canonical_name,display_name,version
      from app.lead_sources where id=$1`, [original.id])).rows[0];
    assert.deepEqual(unchanged, original);
  });
  await check('Malformed IDs return HTTP 400', () => request('PATCH', '/crm/client-config/fields/not-a-uuid', { expectedVersion: 1, label: 'New' }, 400));

  const now = new Date();
  const year = now.getUTCFullYear() + (now.getUTCMonth() > 8 ? 1 : 0);
  const activeFrom = `${year}-09-01`;
  const activeUntil = `${year}-12-01`;
  const decision = { settlementTypeKey: 'lesson', teacherCompensationRuleKey: 'standard',
    clientDecisions: [{ clientId: f.students[0], payerStudentId: f.students[0],
      chargeType: 'subscription', subscriptionId: f.subscriptions[0] }] };
  let standalone;
  const standaloneDraft = {
    clientRef: { type: 'student', id: f.students[1] }, teacherId: f.teachers[0],
    roomId: f.rooms[0], branchId: f.branch, scheduledAt: `${year}-09-07T10:00:00Z`,
    durationMinutes: 60, isTrial: false, completionType: 'standard.success',
    clientChargeType: 'personal_account', clientChargeValue: 1000,
    teacherCompensationType: 'hourly', teacherCompensationValue: 700,
    financialDecision: { ...decision, clientDecisions: [{ clientId: f.students[1],
      payerStudentId: f.students[1], chargeType: 'personal_account', basePriceMinor: '100000' }] },
  };
  await check('Create individual lesson and safely replay creation', async () => {
    const key = randomUUID();
    standalone = await request('POST', '/crm/lessons', standaloneDraft, 201, { key });
    const replay = await request('POST', '/crm/lessons', standaloneDraft, 201, { key });
    assert.equal(replay.id, standalone.id);
    assert.equal(replay.replayed, true);
  });
  if (standalone) {
    await check('Update and clear lesson notes with safe replay and unchanged financial data', async () => {
      const unchangedData = async () => (await pool.query(`select
        to_jsonb(l) - 'notes' - 'version' - 'updated_at' as lesson, p.decision
        from app.lessons l join app.lesson_settlement_plans p on p.lesson_id=l.id
        where l.id=$1`, [standalone.id])).rows[0];
      const before = await unchangedData();
      const body = { expectedVersion: 1, notes: 'Updated note' };
      const key = randomUUID();
      const updated = await request('PATCH', `/crm/lessons/${standalone.id}`, body, 200, { key });
      assert.equal(updated.version, 2);
      const saved = (await pool.query('select notes from app.lessons where id=$1', [standalone.id])).rows[0];
      assert.equal(saved.notes, body.notes);
      const replay = await request('PATCH', `/crm/lessons/${standalone.id}`, body, 200, { key });
      assert.equal(replay.version, 2);
      assert.equal(replay.replayed, true);
      await request('PATCH', `/crm/lessons/${standalone.id}`, { expectedVersion: 2, notes: null });
      const cleared = (await pool.query('select notes,version from app.lessons where id=$1', [standalone.id])).rows[0];
      assert.equal(cleared.notes, null);
      assert.equal(Number(cleared.version), 3);
      assert.deepEqual(await unchangedData(), before);
      const effects = (await pool.query(`select
        (select count(*)::int from app.audit_events where entity_id=$1 and action='crm.lesson_updated') audits,
        (select count(*)::int from app.platform_outbox_events where aggregate_id=$1 and aggregate_version>1) events`,
      [standalone.id])).rows[0];
      assert.deepEqual(effects, { audits: 2, events: 2 });
    });
    await check('Concurrent saves reject the stale version without HTTP 500', async () => {
      const version = Number((await pool.query('select version from app.lessons where id=$1', [standalone.id])).rows[0].version);
      const body = { expectedVersion: version, financialDecision: standaloneDraft.financialDecision, reasonText: 'Concurrent save' };
      const preview = await request('POST', `/crm/lessons/${standalone.id}/planned-settlement/preview`, body, 201);
      const command = { ...body, confirm: true, previewToken: preview.previewToken };
      const responses = await Promise.all([0, 1].map(() =>
        request('PUT', `/crm/lessons/${standalone.id}/planned-settlement`, command, [200, 409])));
      assert.equal(responses.filter(row => row.statusCode === 409).length, 1);
      assert.equal(responses.filter(row => row.version === version + 1).length, 1);
    });
    await check('Null completion type returns validation error instead of 500', () =>
      request('PATCH', `/crm/lessons/${standalone.id}`, { expectedVersion: 2, completionType: null }, [400, 422]));
    await check('Conflicting individual lesson is rejected without HTTP 500', () =>
      request('POST', '/crm/lessons', standaloneDraft, [409, 422]));
  }
  const planDraft = {
    kind: 'individual', title: 'HTTP recurring journey', studentId: f.students[0], subscriptionId: f.subscriptions[0],
    activeFrom, activeUntil,
    rows: [{ teacherId: f.teachers[0], roomId: f.rooms[0], branchId: f.branch, weekday: 5,
      beginTime: '15:00', durationMinutes: 60, financialDecision: decision }],
  };
  let plan;
  let lessons;
  await check('Create full September–December schedule and replay', async () => {
    const preview = await request('POST', '/crm/schedule-plans/constraints/preview', planDraft, 201);
    const body = preview.historical?.previewToken
      ? { ...planDraft, previewToken: preview.historical.previewToken, confirmHistorical: true } : planDraft;
    const key = randomUUID();
    plan = await request('POST', '/crm/schedule-plans', body, 201, { key });
    const replay = await request('POST', '/crm/schedule-plans', body, 201, { key });
    assert.equal(replay.id, plan.id);
    lessons = (await pool.query(`select l.id,l.version,l.scheduled_at from app.lessons l
      join app.schedule_series s on s.id=l.series_id where s.plan_id=$1 order by scheduled_at`, [plan.id])).rows;
    let expected = 0;
    for (const day = new Date(`${activeFrom}T12:00:00Z`); day <= new Date(`${activeUntil}T12:00:00Z`); day.setUTCDate(day.getUTCDate() + 1)) {
      if (day.getUTCDay() === 5) expected++;
    }
    assert.equal(lessons.length, expected);
    assert(new Date(lessons.at(-1).scheduled_at) - new Date(lessons[0].scheduled_at) > 60 * 86400000);
    return { activeFrom, activeUntil, lessons: lessons.length };
  });
  if (!lessons?.length) return;
  const first = lessons[0].id;
  async function fingerprint() {
    const result = await pool.query(`select jsonb_build_object(
      'reservations',(select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]') from app.lesson_reservations r),
      'snapshots',(select coalesce(jsonb_agg(to_jsonb(s) order by lesson_id),'[]') from app.lesson_snapshots s),
      'clientFacts',(select count(*) from app.lesson_client_charge_facts),
      'teacherFacts',(select count(*) from app.lesson_teacher_compensation_facts)) as value`);
    return JSON.stringify(result.rows[0].value);
  }
  async function amend(id, financialDecision, resources) {
    const version = Number((await pool.query('select version from app.lessons where id=$1', [id])).rows[0].version);
    const body = { expectedVersion: version, financialDecision, reasonText: 'Автоматическая проверка изменения', ...(resources ? { resources } : {}) };
    const before = await fingerprint();
    const preview = await request('POST', `/crm/lessons/${id}/planned-settlement/preview`, body, 201);
    assert.equal(await fingerprint(), before, 'Preview must preserve reservations, immutable snapshots and financial facts');
    const command = { ...body, previewToken: preview.previewToken, confirm: true };
    const key = randomUUID();
    const saved = await request('PUT', `/crm/lessons/${id}/planned-settlement`, command, 200, { key });
    const replay = await request('PUT', `/crm/lessons/${id}/planned-settlement`, command, 200, { key });
    assert.equal(saved.version, version + 1);
    assert.equal(replay.version, saved.version);
    assert.equal(replay.replayed, true);
    return preview;
  }
  await check('12 reservations and standard teacher pay on every created lesson', async () => {
    const count = (await pool.query(`select count(*)::int n from app.lesson_reservations where state='reserved'`)).rows[0].n;
    assert.equal(count, 12);
    const plans = (await pool.query(`select decision from app.lesson_settlement_plans`)).rows;
    assert.equal(plans.length, lessons.length + (standalone ? 1 : 0));
    assert(plans.every(row => row.decision.teacherCompensationRuleKey === 'standard'));
  });
  await check('Lesson tray shows the whole explicit range', async () => {
    const tray = await request('GET', `/crm/schedule-plans/${plan.id}/tray?limit=40`);
    assert.equal(tray.items.length, lessons.length);
  });
  await check('Change teacher and room with pure preview and idempotent save', async () => {
    await amend(first, decision, { teacherId: f.teachers[1], branchId: f.branch, roomId: f.rooms[1] });
    const lesson = (await pool.query(`select teacher_id,room_id from app.lessons where id=$1`, [first])).rows[0];
    assert.equal(lesson.teacher_id, f.teachers[1]);
    assert.equal(lesson.room_id, f.rooms[1]);
  });
  await check('Edit an uncovered lesson without consuming a subscription unit', async () => {
    const uncovered = (await pool.query(`select l.id from app.lessons l where l.series_id=any($1::uuid[])
      and not exists(select 1 from app.lesson_reservations r where r.lesson_id=l.id and r.state='reserved')
      order by scheduled_at desc limit 1`, [plan.seriesIds])).rows[0];
    assert(uncovered, 'An uncovered lesson must exist');
    await amend(uncovered.id, decision);
    const reserves = (await pool.query(`select count(*)::int n from app.lesson_reservations where lesson_id=$1 and state='reserved'`, [uncovered.id])).rows[0].n;
    assert.equal(reserves, 0);
  });
  await check('Change payer to personal account with discount and surcharge', async () => {
    await amend(first, { ...decision, clientDecisions: [{ clientId: f.students[0], payerStudentId: f.students[1],
      chargeType: 'personal_account', basePriceMinor: '100000',
      discount: { type: 'percent', percent: 10, reason: 'Скидка' }, surcharge: { amountMinor: '2000', reason: 'Доплата' } }] });
    const count = (await pool.query(`select count(*)::int n from app.lesson_reservations where lesson_id=$1 and state='reserved'`, [first])).rows[0].n;
    assert.equal(count, 0);
  });
  await check('Switch to another payer subscription and return to original reservation', async () => {
    await amend(first, { ...decision, clientDecisions: [{ clientId: f.students[0], payerStudentId: f.students[1],
      chargeType: 'subscription', subscriptionId: f.subscriptions[1] }] });
    await amend(first, { ...decision, clientDecisions: [{ clientId: f.students[0], payerStudentId: f.students[0],
      chargeType: 'subscription', subscriptionId: f.subscriptions[0] }] });
    const history = (await pool.query('select state,subscription_id from app.lesson_reservations where lesson_id=$1', [first])).rows;
    assert(history.some(row => row.state === 'released'));
    assert.equal(history.filter(row => row.state === 'reserved').length, 1);
    assert.equal(history.find(row => row.state === 'reserved').subscription_id, f.subscriptions[0]);
  });
  await check('Stale lesson version returns HTTP 409', () => request('POST', `/crm/lessons/${first}/planned-settlement/preview`,
    { expectedVersion: 1, financialDecision: decision, reasonText: 'Устаревшая версия' }, 409));
  await check('Missing financial decision returns validation error instead of 500', async () => {
    const version = Number((await pool.query('select version from app.lessons where id=$1', [first])).rows[0].version);
    await request('POST', `/crm/lessons/${first}/planned-settlement/preview`, { expectedVersion: version, reasonText: 'Нет решения' }, [400, 422]);
  });
  await check('Planned edits never create actual client charges or teacher accruals', async () => {
    const counts = (await pool.query(`select (select count(*) from app.lesson_client_charge_facts)::int clients,
      (select count(*) from app.lesson_teacher_compensation_facts)::int teachers`)).rows[0];
    assert.deepEqual(counts, { clients: 0, teachers: 0 });
  });
}

async function windowsJourney(fixture) {
  assert.equal(process.platform, 'win32', '--windows requires a Windows host');
  const scheduled = new Date();
  scheduled.setUTCDate(scheduled.getUTCDate() + 1);
  scheduled.setUTCHours(16, 0, 0, 0);
  const input = { baseUrl, email: fixture.email, password: fixture.password,
    studentId: fixture.students[1], teacherId: fixture.teachers[0],
    branchId: fixture.branch, roomId: fixture.rooms[0], scheduledAt: scheduled.toISOString() };
  await runDeviceTest('lesson_live_http_device_test.dart', 'windows.log', {
    HTTP_JOURNEY_FIXTURE: JSON.stringify(input), EVIDENCE_SCREENSHOT_DIR: output,
  });
  const persisted = (await pool.query(`select l.id, p.decision from app.lessons l
    join app.lesson_settlement_plans p on p.lesson_id=l.id
    where l.student_id=$1 and l.scheduled_at=$2`, [fixture.students[1], scheduled.toISOString()])).rows;
  assert.equal(persisted.length, 1, 'The lesson created in Windows must be persisted exactly once');
  assert.equal(persisted[0].decision.teacherCompensationRuleKey, 'standard');
  const charge = persisted[0].decision.clientDecisions[0];
  assert.equal(charge.payerStudentId, fixture.students[1]);
  assert.equal(charge.chargeType, 'personal_account');
  assert.equal(charge.basePriceMinor, '150000');
}

async function runDeviceTest(testFile, logName, extraEnv = {}) {
  assert(['lesson_live_http_device_test.dart', 'lesson_settlement_device_test.dart', 'employee_journey_live_test.dart'].includes(testFile));
  const log = fs.openSync(path.join(output, logName), 'w');
  // Fixed command text; fixture values travel in the child environment, never argv.
  const flutter = spawn('cmd.exe', ['/d', '/s', '/c',
    `C:\\Flutter\\bin\\flutter.bat test integration_test/${testFile} -d windows --no-pub --reporter expanded`], {
    cwd: root, windowsHide: true, stdio: ['ignore', log, log],
    env: { ...process.env, EVIDENCE_SCREENSHOT_DIR: output, ...extraEnv },
  });
  fs.closeSync(log);
  const [code] = await once(flutter, 'exit');
  assert.equal(code, 0, `Windows device test failed; inspect ${logName}`);
}

async function main() {
  for (const argument of process.argv.slice(2)) {
    assert(['--windows', '--restore', '--release-journeys'].includes(argument), `Unknown gate option: ${argument}`);
  }
  if (process.argv.includes('--release-journeys')) assert.equal(process.platform, 'win32', 'Employee release journeys require Windows');
  const adminUrl = new URL(process.env.HTTP_JOURNEY_ADMIN_URL ?? 'postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/postgres');
  assert(['127.0.0.1', 'localhost', '[::1]'].includes(adminUrl.hostname) && adminUrl.pathname === '/postgres',
    'Only a local PostgreSQL maintenance database is permitted');
  admin = new Pool({ connectionString: adminUrl.toString() });
  await admin.query(`create database ${databaseName}`);
  created = true;
  const databaseUrl = new URL(adminUrl);
  databaseUrl.pathname = `/${databaseName}`;
  pool = new Pool({ connectionString: databaseUrl.toString() });
  await new MigrationRunner(pool, path.join(server, 'db/migrations')).up();
  const fixture = await seed();
  await startApi(fixture);
  await journeys(fixture);
  if (process.argv.includes('--release-journeys')) {
    await stopApi();
    await startApi(fixture, true);
    await check('Employee UI journey with real persistence and failure recovery', async () => {
      const scheduled = new Date();
      scheduled.setUTCDate(scheduled.getUTCDate() + 1);
      scheduled.setUTCHours(16, 0, 0, 0);
      await runDeviceTest('employee_journey_live_test.dart', 'employee-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, email: fixture.employeeEmail, password: fixture.password,
          branchId: fixture.branch, roomId: fixture.rooms[0], scheduledAt: scheduled.toISOString() }),
      });
      const result = JSON.parse(fs.readFileSync(path.join(output, 'employee-result.json'), 'utf8'));
      const { verifyEmployeeResult } = require('./release-journey-verification.cjs');
      await verifyEmployeeResult(pool, result);
      return { scenarios: result.scenarios, verified: 'UI → HTTP → PostgreSQL' };
    });
  }
  if (process.argv.includes('--windows')) {
    await check('Windows form → real HTTP → persisted lesson, payer, price and standard pay', () => windowsJourney(fixture));
    await check('Five Windows financial form scenarios with controlled API responses', () =>
      runDeviceTest('lesson_settlement_device_test.dart', 'windows-forms.log'));
  }
  if (process.argv.includes('--restore') || process.argv.includes('--release-journeys')) {
    await stopApi();
    await check('Backup restores into a fresh isolated database with identical persisted facts', async () => {
      const { verifyLocalRestore } = require('./release-journey-verification.cjs');
      return verifyLocalRestore({ pool, admin, output, databaseUrl: pool.options.connectionString });
    });
  }
}

main().catch(error => {
  results.push({ name: 'Journey setup or execution', status: 'FAIL', detail: String(error.message) });
  console.error(String(error.message));
}).finally(async () => {
  await stopApi();
  if (pool) await pool.end();
  // Remove only the fresh database created by this invocation, never an input database.
  if (created) await admin.query(`drop database ${databaseName} with (force)`);
  if (admin) await admin.end();
  if (testedSource !== sourceFingerprint()) {
    results.push({ name: 'Candidate source remained unchanged', status: 'FAIL', detail: 'Source changed during the gate; rerun the final candidate.' });
  }
  const report = { finishedAt: new Date().toISOString(), requestCount, serverErrorCount,
    revision, sourceSha256: testedSource,
    passed: results.filter(r => r.status === 'PASS').length, failed: results.filter(r => r.status === 'FAIL').length,
    scope: 'Real HTTP/PostgreSQL and synthetic fixtures. Employee mode uses native Flutter product surfaces and the real completion worker; realtime delivery is disabled. No production requests.',
    employeeUiRequired: process.argv.includes('--release-journeys'),
    restoreRequired: process.argv.includes('--restore') || process.argv.includes('--release-journeys'), results };
  fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(report, null, 2));
  console.log(`RESULT ${report.passed} passed, ${report.failed} failed; ${requestCount} HTTP requests; ${serverErrorCount} server errors`);
  console.log(`REPORT ${path.join(output, 'result.json')}`);
  if (report.failed) process.exitCode = 1;
});
