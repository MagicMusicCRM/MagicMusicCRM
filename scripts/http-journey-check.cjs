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
    'lib', 'server/src', 'server/db', 'integration_test', 'test', 'scripts',
    'android', 'windows', 'windows_installer.iss', 'analysis_options.yaml', 'assets/release_history.json',
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
let smtp;
let pool;
let admin;
let created = false;
let requestCount = 0;
let serverErrorCount = 0;
let imageRuntime;
const integratedCandidateMode = process.argv.includes('--audit-integrated-candidate');
const notificationSourceMode = integratedCandidateMode || process.argv.includes('--audit-notification-source');
const installmentCycleMode = integratedCandidateMode || process.argv.includes('--audit-installment-cycle');
let integratedLeadId;
let integratedStudentId;
const taskMidnightMode = process.argv.includes('--audit-task-midnight');
const teacherCompensationMode = process.argv.includes('--audit-teacher-compensation');
const lessonVisualMode = process.argv.includes('--audit-lesson-visuals');
let taskClock;
const leadWebhookSecret = notificationSourceMode ? randomBytes(32).toString('hex') : null;

async function stopApi() {
  if (imageRuntime) {
    await imageRuntime.stop();
    imageRuntime = undefined;
    api = undefined;
    return;
  }
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
  const clientAuditAccounts = [{ role: 'director', email: employeeEmail }];
  if (notificationSourceMode || installmentCycleMode || taskMidnightMode || teacherCompensationMode || lessonVisualMode || process.argv.some(arg => ['--client-persistence', '--client-persistence-api', '--client-autosave', '--audit-navigation', '--audit-card-fields', '--audit-archive', '--audit-tasks', '--audit-tasks-advanced', '--audit-plan-lifecycle', '--audit-finance-advanced', '--audit-payroll', '--audit-replacement', '--audit-subscription-coverage', '--audit-plan-rows', '--audit-homework-files', '--audit-account-purchase', '--audit-profile-avatar', '--audit-reports-deep', '--audit-schedule-views', '--audit-schedule-context', '--audit-workspace-runtime', '--audit-boards', '--audit-board-workflows', '--audit-attachment-runtime', '--audit-lesson-guard', '--audit-lesson-funding', '--audit-group-plan', '--audit-purchase-retry', '--audit-deep-link', '--audit-overview-runtime', '--audit-access-runtime', '--audit-finance-access', '--audit-task-navigation', '--audit-plan-timeline', '--audit-x03', '--audit-client-extended', '--audit-auth-runtime', '--audit-access-credentials', '--audit-plan-create', '--audit-messenger-inbox', '--audit-students-pagination', '--audit-messenger-structure', '--audit-update-center', '--audit-context', '--audit-notes', '--audit-collaboration', '--audit-collaboration-recovery', '--audit-family-boundaries', '--audit-account-link', '--audit-client-link-invite', '--audit-client-portal', '--audit-dynamic-fields', '--audit-statuses', '--audit-purchase', '--audit-partial-purchase', '--audit-subscription-cancel', '--audit-teacher-card', '--audit-profile', '--audit-profile-date', '--audit-auth-methods', '--audit-auth-email', '--audit-account-deletion', '--audit-package-catalog', '--audit-reference-catalog', '--audit-branch-discipline', '--audit-branch-rooms', '--audit-org-lifecycle', '--audit-manager-org', '--audit-branch-hours', '--audit-teacher-availability', '--audit-groups', '--audit-group-lifecycle', '--audit-staff-forms', '--audit-ui-usability', '--audit-teacher-forms', '--audit-person-lifecycle', '--audit-organization-edges', '--audit-teacher-offboard', '--audit-notification-preferences', '--audit-messenger-text', '--audit-voice-runtime', '--audit-group-boundaries', '--audit-deletion-queue', '--audit-expenses', '--audit-notifications-inbox', '--audit-messenger-extras', '--audit-phone-review', '--audit-lead-merge', '--audit-client-payments', '--audit-access-editor', '--audit-configuration', '--audit-report-exports', '--audit-report-async', '--audit-data-quality-boundaries', '--audit-auth-delivery', '--audit-messenger-lifecycle', '--audit-responsible', '--audit-comment-rules', '--audit-task-delivery', '--audit-payroll-export', '--audit-customer-revisions'].includes(arg))) {
    for (const role of ['admin', 'manager', 'teacher', 'client']) {
      const loginEmail = `${role}-${runId}@example.test`;
      let account;
      if (role === 'teacher' || role === 'client') {
        const entityType = role === 'teacher' ? 'teacher' : 'student';
        const entityId = role === 'teacher' ? teachers[0] : students[0];
        account = (await pool.query(`select p.id profile,p.user_id as "user" from app.${entityType}s e
          join app.profiles p on p.id=e.profile_id where e.id=$1`, [entityId])).rows[0];
        await pool.query(`update app.users set email=$2,password_hash=$3 where id=$1`, [account.user, loginEmail, passwordHash]);
        await pool.query(`insert into app.user_crm_links (user_id,entity_type,entity_id,link_source,confirmed_at)
          values ($1,$2,$3,'import',now())`, [account.user, entityType, entityId]);
      } else {
        account = await person(role, `Audit-${role}`, true, loginEmail);
      }
      if (role === 'admin' || role === 'manager') {
        const staff = (await pool.query(`insert into app.staff_members (profile_id,role)
          values ($1,$2) returning id`, [account.profile, role])).rows[0].id;
        await pool.query(`insert into app.staff_branch_assignments (staff_member_id,branch_id)
          values ($1,$2)`, [staff, branch]);
        await pool.query(`insert into app.user_crm_links (user_id,entity_type,entity_id,link_source,confirmed_at)
          values ($1,'staff',$2,'import',now())`, [account.user, staff]);
      }
      clientAuditAccounts.push({ role, email: loginEmail });
    }
  }
  let foreignBranch;
  if (notificationSourceMode || process.argv.includes('--audit-customer-revisions') || process.argv.includes('--audit-tasks')) {
    foreignBranch = (await pool.query(
      `insert into app.branches (name,timezone_name) values ('Foreign HTTP test','Europe/Moscow') returning id`,
    )).rows[0].id;
    const loginEmail = `foreign-manager-${runId}@example.test`;
    const account = await person('manager', 'Audit-foreign-manager', true, loginEmail);
    const staff = (await pool.query(
      `insert into app.staff_members (profile_id,role) values ($1,'manager') returning id`,
      [account.profile],
    )).rows[0].id;
    await pool.query(
      `insert into app.staff_branch_assignments (staff_member_id,branch_id) values ($1,$2)`,
      [staff, foreignBranch],
    );
    await pool.query(
      `insert into app.user_crm_links (user_id,entity_type,entity_id,link_source,confirmed_at)
       values ($1,'staff',$2,'import',now())`,
      [account.user, staff],
    );
    clientAuditAccounts.push({ role: 'foreign-manager', email: loginEmail });
  }
  let linkAccount;
  if (process.argv.includes('--audit-account-link')) {
    const row = (await pool.query('select p.user_id from app.students s join app.profiles p on p.id=s.profile_id where s.id=$1', [students[0]])).rows[0];
    linkAccount = { userId: row.user_id, phone: '+79999999998' };
    await pool.query('update app.profiles set phone=$2 where user_id=$1', [linkAccount.userId, linkAccount.phone]);
  }
  return { email, employeeEmail, password, branch, foreignBranch, rooms, teachers, students, subscriptions, clientAuditAccounts, linkAccount };
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
    AUTH_OTP_BYPASS_EMAILS: [fixture.email, ...fixture.clientAuditAccounts.map(a => a.email),
      ...(process.argv.includes('--audit-auth-email') ? fixture.clientAuditAccounts.map(a => `updated-${a.email}`) : []),
      ...(process.argv.includes('--audit-person-lifecycle') ? [`offboard-${runId}@example.test`] : [])].join(','),
    TS_NODE_PROJECT: path.join(server, 'tsconfig.json'),
    V4_ACCESS_MODE: 'v4', V4_ACCESS_KILL_SWITCH: 'false',
    V4_SCHEDULE_MODE: 'v4', V4_SCHEDULE_KILL_SWITCH: 'false', V4_PARITY_UNEXPLAINED_DIFFS: '0',
    PLATFORM_OUTBOX_WORKER_ENABLED: String(notificationSourceMode || process.argv.includes('--audit-tasks') || process.argv.includes('--audit-collaboration') || process.argv.includes('--audit-collaboration-recovery') || process.argv.includes('--audit-x03')), LESSON_COMPLETION_WORKER_ENABLED: String(completionWorker),
    LESSON_COMPLETION_WORKER_POLL_MS: '1000',
    INSTALLMENT_DUE_WORKER_ENABLED: String(installmentCycleMode),
    INSTALLMENT_DUE_WORKER_POLL_MS: '1000', LESSON_REMINDERS_ENABLED: 'false',
    TASK_REMINDERS_ENABLED: String(process.argv.includes('--audit-task-delivery') || notificationSourceMode), SCHEDULE_SERIES_AUTOEXTEND: 'false',
    FILE_STORAGE_ROOT: path.join(working, 'storage'),
  });
  if (process.argv.includes('--audit-auth-delivery') || process.argv.includes('--audit-client-link-invite')) {
    if (!smtp) smtp = await require('./local-smtp-capture.cjs').startLocalSmtpCapture();
    Object.assign(env, { SMTP_FALLBACK_HOST: '127.0.0.1', SMTP_FALLBACK_PORT: String(smtp.port), SMTP_FALLBACK_SECURE: 'false', SMTP_FALLBACK_FROM_EMAIL: 'audit@example.com' });
  }
  if (leadWebhookSecret) env.LEAD_WEBHOOK_SECRET = leadWebhookSecret;
  if (taskClock) env.HTTP_JOURNEY_CLOCK_FILE = taskClock.clockFile;
  fs.mkdirSync(env.FILE_STORAGE_ROOT, { recursive: true });
  const log = fs.openSync(path.join(output, 'api.log'), 'w');
  if (process.env.HTTP_JOURNEY_IMAGE) {
    imageRuntime = require('./http-journey-image-runtime.cjs').startImageRuntime({
      image: process.env.HTTP_JOURNEY_IMAGE, env, port, runId, output, log,
    });
    api = imageRuntime.child;
  } else {
    api = spawn(process.execPath, [
      ...(taskClock ? ['-r', path.join(__dirname, 'task-midnight-clock.cjs')] : []),
      '-r', dependency.resolve('ts-node/register/transpile-only'),
      path.join(server, 'src/main.ts')], { cwd: working, env, windowsHide: true, stdio: ['ignore', log, log] });
  }
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
  if (process.env.HTTP_JOURNEY_ANDROID_SERIAL) {
    assert.equal(testFile, 'customer_revisions_live_test.dart', 'Android scope is customer revisions only');
    return require('./android-journey-runtime.cjs').runAndroidJourney({
      root, output, raw: extraEnv.HTTP_JOURNEY_FIXTURE,
    });
  }
  assert(['lesson_visuals_live_test.dart', 'teacher_compensation_live_test.dart', 'task_midnight_live_test.dart', 'notification_source_live_test.dart', 'notification_task_close_live_test.dart'].includes(testFile) || ['customer_revisions_live_test.dart', 'lesson_live_http_device_test.dart', 'lesson_settlement_device_test.dart', 'employee_journey_live_test.dart', 'client_persistence_live_test.dart', 'role_navigation_live_test.dart', 'client_fields_live_test.dart', 'client_archive_live_test.dart', 'tasks_live_test.dart', 'tasks_advanced_live_test.dart', 'schedule_plan_lifecycle_live_test.dart', 'finance_advanced_live_test.dart', 'payroll_live_test.dart', 'subscription_coverage_live_test.dart', 'subscription_replacement_live_test.dart', 'plan_rows_live_test.dart', 'homework_files_live_test.dart', 'account_purchase_live_test.dart', 'profile_avatar_live_test.dart', 'reports_deep_live_test.dart', 'schedule_context_live_test.dart', 'schedule_views_live_test.dart', 'workspace_runtime_live_test.dart', 'task_navigation_live_test.dart', 'finance_access_live_test.dart', 'access_runtime_live_test.dart', 'overview_runtime_live_test.dart', 'deep_link_live_test.dart', 'purchase_retry_live_test.dart', 'group_plan_live_test.dart', 'lesson_funding_live_test.dart', 'lesson_guard_live_test.dart', 'attachment_runtime_live_test.dart', 'board_workflows_live_test.dart', 'boards_live_test.dart', 'plan_timeline_live_test.dart', 'x03_live_test.dart', 'client_extended_live_test.dart', 'auth_runtime_live_test.dart', 'access_credentials_live_test.dart', 'plan_create_live_test.dart', 'messenger_inbox_live_test.dart', 'students_pagination_live_test.dart', 'messenger_structure_live_test.dart', 'update_center_live_test.dart', 'client_context_live_test.dart', 'client_collaboration_live_test.dart', 'client_link_invite_live_test.dart', 'client_account_link_live_test.dart', 'client_portal_live_test.dart', 'client_dynamic_fields_live_test.dart', 'client_statuses_live_test.dart', 'client_purchase_live_test.dart', 'partial_purchase_live_test.dart', 'teacher_card_live_test.dart', 'profile_fields_live_test.dart', 'profile_date_roundtrip_live_test.dart', 'auth_methods_live_test.dart', 'auth_email_routed_live_test.dart', 'account_deletion_live_test.dart', 'package_catalog_live_test.dart', 'reference_catalog_live_test.dart', 'branch_discipline_live_test.dart', 'branch_rooms_live_test.dart', 'organization_lifecycle_live_test.dart', 'manager_organization_live_test.dart', 'branch_hours_live_test.dart', 'teacher_availability_live_test.dart', 'group_membership_live_test.dart', 'group_lifecycle_live_test.dart', 'staff_forms_live_test.dart', 'ui_usability_live_test.dart', 'teacher_forms_live_test.dart', 'organization_edges_live_test.dart', 'person_lifecycle_live_test.dart', 'teacher_offboard_live_test.dart', 'notification_preferences_live_test.dart', 'voice_runtime_live_test.dart', 'messenger_text_live_test.dart', 'deletion_queue_live_test.dart', 'expenses_live_test.dart', 'notifications_inbox_live_test.dart', 'messenger_extras_live_test.dart', 'phone_review_live_test.dart', 'lead_merge_live_test.dart', 'client_payment_live_test.dart', 'access_editor_live_test.dart', 'configuration_live_test.dart', 'report_async_live_test.dart', 'report_exports_live_test.dart'].includes(testFile));
  const log = fs.openSync(path.join(output, logName), 'w');
  // Fixed command text; fixture values travel in the child environment, never argv.
  const flutter = spawn('cmd.exe', ['/d', '/s', '/c',
    `C:\\Flutter\\bin\\flutter.bat test integration_test/${testFile} -d windows --no-pub --reporter expanded${process.argv.includes('--audit-collaboration-recovery') ? ' --plain-name recovery' : ''}`], {
    cwd: root, windowsHide: true, stdio: ['ignore', log, log],
    env: { ...process.env, EVIDENCE_SCREENSHOT_DIR: output, ...extraEnv },
  });
  fs.closeSync(log);
  const [code] = await once(flutter, 'exit');
  assert.equal(code, 0, `Windows device test failed; inspect ${logName}`);
}

async function main() {
  for (const argument of process.argv.slice(2)) {
    if (argument === '--audit-integrated-candidate' || argument === '--audit-lesson-visuals') continue;
    if (argument === '--audit-notification-source' || argument === '--audit-installment-cycle' || argument === '--audit-task-midnight' || argument === '--audit-teacher-compensation') continue;
    assert(['--windows', '--restore', '--release-journeys', '--client-persistence', '--client-persistence-api', '--client-autosave', '--audit-navigation', '--audit-card-fields', '--audit-archive', '--audit-tasks', '--audit-tasks-advanced', '--audit-plan-lifecycle', '--audit-finance-advanced', '--audit-payroll', '--audit-replacement', '--audit-subscription-coverage', '--audit-plan-rows', '--audit-homework-files', '--audit-account-purchase', '--audit-profile-avatar', '--audit-reports-deep', '--audit-schedule-views', '--audit-schedule-context', '--audit-workspace-runtime', '--audit-boards', '--audit-board-workflows', '--audit-attachment-runtime', '--audit-lesson-guard', '--audit-lesson-funding', '--audit-group-plan', '--audit-purchase-retry', '--audit-deep-link', '--audit-overview-runtime', '--audit-access-runtime', '--audit-finance-access', '--audit-task-navigation', '--audit-plan-timeline', '--audit-x03', '--audit-client-extended', '--audit-auth-runtime', '--audit-access-credentials', '--audit-plan-create', '--audit-messenger-inbox', '--audit-students-pagination', '--audit-messenger-structure', '--audit-update-center', '--audit-context', '--audit-notes', '--audit-collaboration', '--audit-collaboration-recovery', '--audit-family-boundaries', '--audit-account-link', '--audit-client-link-invite', '--audit-client-portal', '--audit-dynamic-fields', '--audit-statuses', '--audit-purchase', '--audit-partial-purchase', '--audit-subscription-cancel', '--audit-teacher-card', '--audit-profile', '--audit-profile-date', '--audit-auth-methods', '--audit-auth-email', '--audit-account-deletion', '--audit-package-catalog', '--audit-reference-catalog', '--audit-branch-discipline', '--audit-branch-rooms', '--audit-org-lifecycle', '--audit-manager-org', '--audit-branch-hours', '--audit-teacher-availability', '--audit-groups', '--audit-group-lifecycle', '--audit-staff-forms', '--audit-ui-usability', '--audit-teacher-forms', '--audit-person-lifecycle', '--audit-organization-edges', '--audit-teacher-offboard', '--audit-notification-preferences', '--audit-messenger-text', '--audit-voice-runtime', '--audit-group-boundaries', '--audit-deletion-queue', '--audit-expenses', '--audit-notifications-inbox', '--audit-messenger-extras', '--audit-phone-review', '--audit-lead-merge', '--audit-client-payments', '--audit-access-editor', '--audit-configuration', '--audit-report-exports', '--audit-report-async', '--audit-data-quality-boundaries', '--audit-auth-delivery', '--audit-messenger-lifecycle', '--audit-responsible', '--audit-comment-rules', '--audit-task-delivery', '--audit-payroll-export', '--audit-customer-revisions'].includes(argument), `Unknown gate option: ${argument}`);
  }
  const clientAuditModes = ['--client-persistence', '--client-persistence-api', '--client-autosave', '--audit-navigation', '--audit-card-fields', '--audit-archive', '--audit-tasks', '--audit-tasks-advanced', '--audit-plan-lifecycle', '--audit-finance-advanced', '--audit-payroll', '--audit-replacement', '--audit-subscription-coverage', '--audit-plan-rows', '--audit-homework-files', '--audit-account-purchase', '--audit-profile-avatar', '--audit-reports-deep', '--audit-schedule-views', '--audit-schedule-context', '--audit-workspace-runtime', '--audit-boards', '--audit-board-workflows', '--audit-attachment-runtime', '--audit-lesson-guard', '--audit-lesson-funding', '--audit-group-plan', '--audit-purchase-retry', '--audit-deep-link', '--audit-overview-runtime', '--audit-access-runtime', '--audit-finance-access', '--audit-task-navigation', '--audit-plan-timeline', '--audit-x03', '--audit-client-extended', '--audit-auth-runtime', '--audit-access-credentials', '--audit-plan-create', '--audit-messenger-inbox', '--audit-students-pagination', '--audit-messenger-structure', '--audit-update-center', '--audit-context', '--audit-notes', '--audit-collaboration', '--audit-collaboration-recovery', '--audit-family-boundaries', '--audit-account-link', '--audit-client-link-invite', '--audit-client-portal', '--audit-dynamic-fields', '--audit-statuses', '--audit-purchase', '--audit-partial-purchase', '--audit-subscription-cancel', '--audit-teacher-card', '--audit-profile', '--audit-profile-date', '--audit-auth-methods', '--audit-auth-email', '--audit-account-deletion', '--audit-package-catalog', '--audit-reference-catalog', '--audit-branch-discipline', '--audit-branch-rooms', '--audit-org-lifecycle', '--audit-manager-org', '--audit-branch-hours', '--audit-teacher-availability', '--audit-groups', '--audit-group-lifecycle', '--audit-staff-forms', '--audit-ui-usability', '--audit-teacher-forms', '--audit-person-lifecycle', '--audit-organization-edges', '--audit-teacher-offboard', '--audit-notification-preferences', '--audit-messenger-text', '--audit-voice-runtime', '--audit-group-boundaries', '--audit-deletion-queue', '--audit-expenses', '--audit-notifications-inbox', '--audit-messenger-extras', '--audit-phone-review', '--audit-lead-merge', '--audit-client-payments', '--audit-access-editor', '--audit-configuration', '--audit-report-exports', '--audit-report-async', '--audit-data-quality-boundaries', '--audit-auth-delivery', '--audit-messenger-lifecycle', '--audit-responsible', '--audit-comment-rules', '--audit-task-delivery', '--audit-payroll-export', '--audit-customer-revisions']
    .filter(argument => process.argv.includes(argument));
  if (notificationSourceMode) clientAuditModes.push('--audit-notification-source');
  if (installmentCycleMode) clientAuditModes.push('--audit-installment-cycle');
  if (taskMidnightMode) clientAuditModes.push('--audit-task-midnight');
  if (teacherCompensationMode) clientAuditModes.push('--audit-teacher-compensation');
  if (lessonVisualMode) clientAuditModes.push('--audit-lesson-visuals');
  assert(clientAuditModes.length <= (integratedCandidateMode ? 2 : 1), 'Run client audit modes separately unless using the explicit integrated candidate journey.');
  if (clientAuditModes.some(argument => !['--client-persistence-api', '--audit-family-boundaries', '--audit-group-boundaries', '--audit-data-quality-boundaries', '--audit-auth-delivery', '--audit-messenger-lifecycle', '--audit-responsible', '--audit-comment-rules', '--audit-task-delivery', '--audit-payroll-export'].includes(argument))) {
    assert.equal(process.platform, 'win32', 'Native client audit requires Windows');
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
  if (taskMidnightMode) taskClock = await require('./task-midnight-clock.cjs').prepareClock({pool, databaseName, output});
  await startApi(fixture);
  await journeys(fixture);
  if (lessonVisualMode) {
    await require('./lesson-visual-verification.cjs').runLessonVisualAudit({pool, fixture, request,
      restartWithCompletion: async () => {
        await stopApi();
        await startApi(fixture, true);
        token = (await request('POST', '/auth/login', {email: fixture.email, password: fixture.password}, 200, {auth:false})).session.accessToken;
        return baseUrl;
      }, runDeviceTest, output, check});
  }
  if (teacherCompensationMode) {
    await check('Every teacher pay rule survives native save/reopen, error and version conflict', () =>
      runDeviceTest('teacher_compensation_live_test.dart', 'teacher-compensation-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          branchId: fixture.branch, teacherId: fixture.teachers[0], roomId: fixture.rooms[0], studentId: fixture.students[0]}),
      }));
    const evidence = JSON.parse(fs.readFileSync(path.join(output, 'teacher-compensation-director.json'), 'utf8'));
    const lessonId = evidence.facts.find(fact => fact.matrixLessonId)?.matrixLessonId;
    await check('Pay-rule edits preserve the lesson and concurrent note', async () => {
      assert(lessonId, 'Native matrix did not record its lesson');
      const lesson = await request('GET', `/crm/lessons?lessonId=${lessonId}&limit=1`);
      fs.writeFileSync(path.join(output, 'teacher-compensation-persisted.json'), JSON.stringify(lesson, null, 2));
      assert.equal(lesson.items[0].notes, 'Concurrent note');
    });
  }
  if (taskMidnightMode) {
    await check('Moscow day rolls over in native workspace, SQL badge and API task counters', () =>
      require('./task-midnight-clock.cjs').runClockJourney({pool, clock: taskClock, runDeviceTest,
        input: {baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, branchId: fixture.branch}}));
    const tasks = (await pool.query("select id,title,state,start_at,end_at,all_day from app.shared_tasks where title like 'MIDNIGHT-%' order by title")).rows;
    fs.writeFileSync(path.join(output, 'task-midnight-db.json'), JSON.stringify(tasks, null, 2));
    await check('Clock fixture preserves all five tasks without changing their dates', async () => {
      assert.equal(tasks.length, 5);
      assert(tasks.every(task => task.state === 'open'));
      assert.equal(tasks.filter(task => !task.all_day).length, 1);
    });
  }
  if (process.argv.includes('--audit-client-portal')) {
    const clientUserId = (await pool.query('select p.user_id from app.students s join app.profiles p on p.id=s.profile_id where s.id=$1', [fixture.students[0]])).rows[0].user_id;
    await request('POST', `/crm/clients/student/${fixture.students[1]}/link-user`, { userId: clientUserId }, 201);
    const portalSubscriptions = [];
    const purchases = [];
    for (const [index, studentId] of fixture.students.entries()) {
      const amount = 800000 + index * 400000;
      const subscriptionPackage = await request('POST', '/crm/subscription-packages', {
        name: `PORTAL-PACKAGE-${index}`, branchId: fixture.branch, unitCount: 8 + index * 4,
        basePriceMinor: String(amount), currencyCode: 'RUB', validityDays: 90,
      }, 201);
      const input = { packageId: subscriptionPackage.id, payerStudentId: studentId, fundingMode: 'installment',
        purchaseReason: 'Синтетический абонемент для проверки кабинета',
        installments: [30, 60].map(days => ({ dueAt: new Date(Date.now() + days * 86400000).toISOString(), amountMinor: String(amount / 2) })),
      };
      const preview = await request('POST', `/crm/students/${studentId}/subscriptions/purchase/preview`, input, 201);
      assert.equal(preview.canCommit, true);
      const purchased = await request('POST', `/crm/students/${studentId}/subscriptions/purchase`, { ...input, previewToken: preview.previewToken, confirm: true }, 201);
      purchases.push(purchased);
      portalSubscriptions.push(purchased.subscription.id);
    }
    const homeworks = [];
    for (const [index, studentId] of fixture.students.entries()) {
      homeworks.push(await request('POST', '/crm/homeworks', { studentId, title: `PORTAL-HOMEWORK-${index}`, description: 'Тестовое задание без файла' }, 201));
    }
    await check('Client portal: linked students, lessons, subscription and homework submission', () =>
      runDeviceTest('client_portal_live_test.dart', 'client-portal-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, students: fixture.students,
          subscriptions: portalSubscriptions, homeworks, accounts: fixture.clientAuditAccounts }),
      }));
    const rows = (await pool.query('select to_jsonb(hw) value from app.lesson_homeworks hw where id=any($1::uuid[]) order by title', [homeworks.map(row => row.id)])).rows.map(row => row.value);
    const subscriptions = (await pool.query('select to_jsonb(s) value from app.subscriptions s where id=any($1::uuid[]) order by id', [portalSubscriptions])).rows.map(row => row.value);
    fs.writeFileSync(path.join(output, 'client-portal-db.json'), JSON.stringify({ homeworks: rows, subscriptions, purchases }, null, 2));
  }
  if (process.argv.includes('--audit-account-link')) {
    await check('Account linking UI and subsequent card save with current version', () =>
      runDeviceTest('client_account_link_live_test.dart', 'account-link-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, linkAccount: fixture.linkAccount,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
    const links = (await pool.query('select to_jsonb(link) value from app.user_crm_links link where user_id=$1 order by entity_type,entity_id', [fixture.linkAccount.userId])).rows.map(row => row.value);
    const leads = (await pool.query("select id,first_name,version from app.leads where last_name like 'ACCOUNT-%' order by id")).rows;
    const students = (await pool.query("select s.id,p.first_name,s.version from app.students s join app.profiles p on p.id=s.profile_id where p.last_name like 'ACCOUNT-%' order by s.id")).rows;
    fs.writeFileSync(path.join(output, 'account-link-db.json'), JSON.stringify({ links, leads, students }, null, 2));
  }
  if (process.argv.includes('--audit-family-boundaries')) {
    const { runFamilyBoundaryAudit } = require('./family-boundary-verification.cjs');
    await runFamilyBoundaryAudit({ pool, fixture, baseUrl, output, check });
  }
  if (process.argv.includes('--audit-collaboration') || process.argv.includes('--audit-collaboration-recovery')) {
    await check(process.argv.includes('--audit-collaboration-recovery')
      ? 'Real CRM socket loss and student card recovery through native UI'
      : 'Card family and comments: actual UI commands with persisted readback', () =>
      runDeviceTest('client_collaboration_live_test.dart', 'collaboration-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, students: fixture.students, teachers: fixture.teachers,
          rooms: fixture.rooms, accounts: fixture.clientAuditAccounts }),
      }));
    if (process.argv.includes('--audit-collaboration')) {
      const snapshots = {};
      for (const table of ['families', 'family_members', 'entity_comments', 'lead_comments']) {
        snapshots[table] = (await pool.query(`select to_jsonb(row) as value from app.${table} row order by id`)).rows.map(row => row.value);
      }
      fs.writeFileSync(path.join(output, 'collaboration-db.json'), JSON.stringify(snapshots, null, 2));
    }
  }
  if (process.argv.includes('--audit-context') || process.argv.includes('--audit-notes')) {
    const notesOnly = process.argv.includes('--audit-notes');
    const evidencePrefix = notesOnly ? 'client-notes' : 'client-context';
    await check(notesOnly ? 'Card notes: create, edit, clear and reopen under three real staff roles'
      : 'Card context UI: notes and contact person create/edit/remove/readback', () =>
      runDeviceTest('client_context_live_test.dart', `${evidencePrefix}-windows.log`, {
        CLIENT_CONTEXT_NOTES_ONLY: notesOnly ? '1' : '0',
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
    const notes = (await pool.query('select to_jsonb(note) as value from app.client_internal_notes note order by id')).rows.map(row => row.value);
    const contacts = {
      leads: (await pool.query(`select id,custom_data from app.leads where last_name like 'CONTEXT-%' order by last_name`)).rows,
      students: (await pool.query(`select s.id,s.custom_data from app.students s join app.profiles p on p.id=s.profile_id
        where p.last_name like 'CONTEXT-%' order by p.last_name`)).rows,
    };
    fs.writeFileSync(path.join(output, `${evidencePrefix}-db.json`), JSON.stringify({ notes, contacts }, null, 2));
  }
  if (process.argv.includes('--audit-tasks')) {
    const legacy = await request('POST', '/crm/shared-tasks', {
      title: 'TASK-X08-LEGACY', allDay: true, startAt: new Date().toISOString(),
      audiences: [{ type: 'branch', targetId: fixture.branch }],
    }, 201);
    await pool.query(`insert into app.task_closes (task_id, closed_by, request_id)
      select id, created_by, $2 from app.shared_tasks where id = $1`,
    [legacy.id, `legacy-${runId}`]);
    await pool.query(`update app.shared_tasks set state = 'closed', version = version + 1
      where id = $1`, [legacy.id]);
    await check('Task UI: creation, edit, cancellation, close and staff access', () =>
      runDeviceTest('tasks_live_test.dart', 'tasks-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
    await check('X08 new client process reopens persisted task badge', () =>
      runDeviceTest('tasks_live_test.dart', 'tasks-restart-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts,
          x08Restart: true }),
      }));
    const tasks = (await pool.query(`select to_jsonb(task) as value from app.canonical_tasks task
      where title like 'TASK-AUDIT-%' order by title`)).rows.map(row => row.value);
    fs.writeFileSync(path.join(output, 'tasks-db.json'), JSON.stringify(tasks, null, 2));
    const x08 = (await pool.query(`select task.id, task.title, task.state, task.start_at,
      close.result_code, close.result_label, close.comment, close.closed_at, close.closed_by
      from app.shared_tasks task left join app.task_closes close on close.task_id = task.id
      where task.title like 'TASK-X08-%' order by task.title`)).rows;
    fs.writeFileSync(path.join(output, 'tasks-x08-db.json'), JSON.stringify(x08, null, 2));
    await check('X08 persisted 20 today → 5 closed; adjacent days and legacy result unchanged', async () => {
      const today = x08.filter(row => row.title.startsWith('TASK-X08-TODAY-'));
      assert.equal(today.length, 20);
      assert.equal(today.filter(row => row.state === 'closed').length, 5);
      assert.equal(today.filter(row => row.state === 'open').length, 15);
      assert(today.filter(row => row.state === 'closed').every(row =>
        row.result_code && row.closed_at && row.closed_by));
      assert.equal(x08.filter(row => row.title.startsWith('TASK-X08-FUTURE-') && row.state === 'open').length, 2);
      assert.equal(x08.filter(row => row.title.startsWith('TASK-X08-YESTERDAY-') && row.state === 'open').length, 2);
      assert.equal(x08.find(row => row.id === legacy.id)?.result_code, null);
    });
    await check('X08 scoped badge, results, and forbidden task calls', async () => {
      const originalToken = token;
      try {
        for (const role of ['admin', 'manager', 'foreign-manager', 'teacher', 'client']) {
          const account = fixture.clientAuditAccounts.find(value => value.role === role);
          const login = await request('POST', '/auth/login',
            { email: account.email, password: fixture.password }, 200, { auth: false });
          token = login.session.accessToken;
          if (role === 'admin') {
            assert.equal((await request('GET', '/crm/sections/unseen')).tasks, 15);
            await request('POST', '/crm/shared-tasks', {
              title: 'TASK-X08-FORBIDDEN', allDay: true, startAt: new Date().toISOString(),
              audiences: [{ type: 'branch', targetId: fixture.branch }],
            }, 403);
          } else if (role === 'manager') {
            const results = await request('GET', '/crm/shared-tasks/results?q=TASK-X08-');
            assert.equal(results.items.filter(item => item.title.startsWith('TASK-X08-TODAY-')).length, 5);
            assert(results.items.some(item => item.taskId === legacy.id && item.result === null));
          } else if (role === 'foreign-manager' || role === 'teacher') {
            const list = await request('GET', '/crm/shared-tasks?q=TASK-X08-TODAY-1');
            assert.equal(list.items.length, 0);
          } else {
            await request('GET', '/crm/shared-tasks?q=TASK-X08-TODAY-1', undefined, 403);
          }
        }
      } finally {
        token = originalToken;
      }
    });
  }
  if (process.argv.includes('--audit-archive')) {
    const { runClientArchiveAudit } = require('./client-archive-verification.cjs');
    await runClientArchiveAudit({ pool, output, check, fixture, baseUrl, runDeviceTest });
  }
  if (process.argv.includes('--audit-branch-discipline')) {
    const discipline = await request('POST', '/crm/disciplines', { name: 'BRANCH-DISCIPLINE-AUDIT' }, 201);
    await check('Actual branch form assigns, unassigns and restores a discipline binding', () =>
      runDeviceTest('branch_discipline_live_test.dart', 'branch-discipline-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, branchId: fixture.branch,
          disciplineId: discipline.id, accounts: fixture.clientAuditAccounts }),
      }));
    const rows = (await pool.query(`select to_jsonb(link) binding, d.lifecycle_state discipline_state,b.lifecycle_state branch_state
      from app.branch_disciplines link join app.disciplines d on d.id=link.discipline_id
      join app.branches b on b.id=link.branch_id where link.discipline_id=$1`, [discipline.id])).rows;
    fs.writeFileSync(path.join(output, 'branch-discipline-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-branch-rooms')) {
    await check('Actual branch and room forms save, clear and cancel changes', () =>
      runDeviceTest('branch_rooms_live_test.dart', 'branch-rooms-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const branches = (await pool.query(`select to_jsonb(b) value from app.branches b where name like 'BRANCH-FORM-%' order by name`)).rows.map(r => r.value);
    const rooms = (await pool.query(`select to_jsonb(r) value from app.rooms r where name like 'ROOM-%' order by name`)).rows.map(r => r.value);
    const hours = (await pool.query(`select h.branch_id,h.weekday,h.open_local::text,h.close_local::text
      from app.branch_hours h join app.branches b on b.id=h.branch_id where b.name like 'BRANCH-FORM-%' order by h.weekday`)).rows;
    fs.writeFileSync(path.join(output, 'branch-rooms-db.json'), JSON.stringify({ branches, rooms, hours }, null, 2));
  }
  if (process.argv.includes('--audit-org-lifecycle')) {
    const branch = await request('POST', '/crm/branches', { name: 'LIFECYCLE-BRANCH', weeklyHours: [{ weekday: 1, open: '09:00', close: '21:00' }] }, 201);
    const room = await request('POST', '/crm/rooms', { name: 'LIFECYCLE-ROOM', branchId: branch.id, capacity: 10 }, 201);
    await check('Branch and room lifecycle blocks active links and preserves restored history', () =>
      runDeviceTest('organization_lifecycle_live_test.dart', 'organization-lifecycle-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          newBranchId: branch.id, newRoomId: room.id, busyBranchId: fixture.branch, busyRoomId: fixture.rooms[0] }),
      }));
    const rows = (await pool.query(`select to_jsonb(b) branch,to_jsonb(r) room,
      (select count(*)::int from app.branch_hours h where h.branch_id=b.id) hours_count,
      (select jsonb_agg(to_jsonb(h) order by h.version) from app.branch_lifecycle_history h where h.branch_id=b.id) branch_history,
      (select jsonb_agg(to_jsonb(h) order by h.version) from app.room_lifecycle_history h where h.room_id=r.id) room_history
      from app.branches b join app.rooms r on r.branch_id=b.id where b.id=$1`, [branch.id])).rows;
    fs.writeFileSync(path.join(output, 'organization-lifecycle-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-manager-org')) {
    const foreign = await request('POST', '/crm/branches', { name: 'MANAGER-FOREIGN', weeklyHours: [{ weekday: 1, open: '09:00', close: '21:00' }] }, 201);
    await request('POST', '/crm/rooms', { name: 'MANAGER-FOREIGN-ROOM', branchId: foreign.id, capacity: 10 }, 201);
    await check('Manager reads assigned organization data and cannot mutate default settings', () =>
      runDeviceTest('manager_organization_live_test.dart', 'manager-org-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          branchId: fixture.branch, foreignBranchId: foreign.id }),
      }));
    const rows = (await pool.query(`select b.id,b.name,b.schedule_reference_version,
      (select count(*)::int from app.branch_hours h where h.branch_id=b.id) hours_count,
      (select count(*)::int from app.rooms r where r.branch_id=b.id) rooms_count
      from app.branches b where b.id=any($1::uuid[]) order by name`, [[fixture.branch, foreign.id]])).rows;
    fs.writeFileSync(path.join(output, 'manager-org-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-branch-hours')) {
    await check('Branch working hours and exceptions persist with stale-version protection', () =>
      runDeviceTest('branch_hours_live_test.dart', 'branch-hours-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, branchId: fixture.branch }),
      }));
    const branch = (await pool.query('select id,timezone_name,schedule_reference_version from app.branches where id=$1', [fixture.branch])).rows[0];
    const weekly = (await pool.query('select weekday,open_local::text,close_local::text from app.branch_hours where branch_id=$1 order by weekday', [fixture.branch])).rows;
    const exceptions = (await pool.query('select local_date::text,closed,open_local::text,close_local::text from app.branch_hour_exceptions where branch_id=$1', [fixture.branch])).rows;
    fs.writeFileSync(path.join(output, 'branch-hours-db.json'), JSON.stringify({ branch, weekly, exceptions }, null, 2));
  }
  if (process.argv.includes('--audit-teacher-availability')) {
    const extra = await request('POST', '/crm/branches', { name: 'ZZ-TEACHER-BRANCH', weeklyHours: [{ weekday: 1, open: '09:00', close: '21:00' }] }, 201);
    await check('Teacher branch assignments and availability save independently with version protection', () =>
      runDeviceTest('teacher_availability_live_test.dart', 'teacher-availability-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          branchId: fixture.branch, extraBranchId: extra.id, teacherId: fixture.teachers[0], otherTeacherId: fixture.teachers[1],
          roomId: fixture.rooms[0], studentId: fixture.students[0] }),
      }));
    await check('Client cannot change teacher availability', async () => {
      const from = new Date();
      const to = new Date(from.getTime() + 31 * 86400000);
      const endpoint = `/crm/schedule-reference?branchId=${fixture.branch}&teacherId=${fixture.teachers[0]}&from=${encodeURIComponent(from.toISOString())}&to=${encodeURIComponent(to.toISOString())}`;
      const before = (await request('GET', endpoint)).teacher;
      const login = await request('POST', '/auth/login', {
        email: fixture.clientAuditAccounts.find(account => account.role === 'client').email,
        password: fixture.password,
      }, 200, { auth: false });
      const adminToken = token;
      try {
        token = login.session.accessToken;
        await request('PUT', `/crm/schedule-reference/teachers/${fixture.teachers[0]}/availability`, {
          expectedVersion: before.version,
          rules: before.availability.map(rule => Object.fromEntries(Object.entries(rule).filter(([, value]) => value !== null))),
        }, 403);
      } finally {
        token = adminToken;
      }
      const after = (await request('GET', endpoint)).teacher;
      assert.equal(after.version, before.version);
    });
    const teachers = (await pool.query(`select t.id,p.first_name,t.schedule_reference_version,
      (select jsonb_agg(to_jsonb(a) order by a.branch_id) from app.teacher_branches a where a.teacher_id=t.id) assignments,
      (select jsonb_agg(to_jsonb(r) order by r.kind,r.weekday) from app.teacher_availability_rules r where r.teacher_id=t.id) rules
      from app.teachers t join app.profiles p on p.id=t.profile_id where t.id=any($1::uuid[]) order by p.first_name`, [fixture.teachers])).rows;
    fs.writeFileSync(path.join(output, 'teacher-availability-db.json'), JSON.stringify(teachers, null, 2));
  }
  if (process.argv.includes('--audit-group-boundaries')) {
    await require('./group-boundary-verification.cjs').runGroupBoundaryAudit({ pool, fixture, baseUrl, output, check });
  }
  if (process.argv.includes('--audit-deletion-queue')) {
    const ids = {};
    await request('POST', '/crm/payments', { studentId: fixture.students[0], amount: 1234.5, paymentDate: new Date().toISOString(), method: 'cash', externalId: 'AUDIT-DELETION-' + runId, notes: 'AUDIT-DELETION-HISTORY' }, 201);
    await request('POST', '/auth/login', { email: fixture.clientAuditAccounts.find(a => a.role === 'client').email, password: fixture.password }, 200, { auth: false });
    for (const role of ['teacher', 'client']) {
      const account = fixture.clientAuditAccounts.find(a => a.role === role);
      const user = (await pool.query('select id from app.users where email=$1', [account.email])).rows[0];
      ids[role] = (await pool.query("insert into app.account_deletion_requests(user_id,reason) values ($1,$2) returning id,user_id", [user.id, 'AUDIT-QUEUE-' + role])).rows[0];
    }
    async function snapshot() {
      const history = {};
      for (const table of ['students', 'subscriptions', 'payments', 'lessons', 'lesson_snapshot_participants']) {
        history[table] = (await pool.query('select to_jsonb(t) value from app.' + table + ' t order by to_jsonb(t)::text')).rows.map(r => r.value);
      }
      const users = (await pool.query(`select u.id,u.email,u.deleted_at,u.password_hash is not null has_password,p.first_name,p.last_name,p.phone,p.dob,p.deleted_at profile_deleted,
        (select count(*)::int from app.refresh_sessions r where r.user_id=u.id and r.revoked_at is null) live_sessions
        from app.users u join app.profiles p on p.user_id=u.id where u.id=any($1::uuid[]) order by u.id`, [Object.values(ids).map(r => r.user_id)])).rows;
      const requests = (await pool.query('select * from app.account_deletion_requests order by id')).rows;
      return { history, users, requests };
    }
    const before = await snapshot();
    await check('Deletion queue: review restrictions rejection and confirmed anonymization through actual forms', () =>
      runDeviceTest('deletion_queue_live_test.dart', 'deletion-queue-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          rejectedId: ids.teacher.id, completedId: ids.client.id }),
      }));
    const after = await snapshot();
    fs.writeFileSync(path.join(output, 'deletion-queue-db.json'), JSON.stringify({ ids, before, after }, null, 2));
  }
  if (process.argv.includes('--audit-expenses')) {
    await check('Expense forms persist create edit clear and delete while preserving history', () =>
      runDeviceTest('expenses_live_test.dart', 'expenses-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, branchId: fixture.branch }),
      }));
    const expenses = (await pool.query('select * from app.expenses order by id')).rows;
    const audit = (await pool.query("select action,entity_id,metadata from app.audit_events where entity_type='expense' order by created_at")).rows;
    fs.writeFileSync(path.join(output, 'expenses-db.json'), JSON.stringify({ expenses, audit }, null, 2));
  }
  if (process.argv.includes('--audit-notifications-inbox')) {
    const notificationIds = {};
    for (const role of ['admin', 'manager', 'director']) {
      const account = fixture.clientAuditAccounts.find(a => a.role === role);
      const user = (await pool.query('select id from app.users where email=$1', [account.email])).rows[0]; notificationIds[role] = [];
      for (let index = 1; index <= 2; index++) {
        const row = (await pool.query("insert into app.notifications(type,title,body) values ('admin_broadcast',$1,$2) returning id", ['AUDIT-INBOX-' + role + '-' + index, 'Синтетическое уведомление аудита'])).rows[0];
        await pool.query('insert into app.notification_recipients(notification_id,user_id) values ($1,$2)', [row.id, user.id]); notificationIds[role].push(row.id);
      }
    }
    await check('Notification inbox read markers and counters survive reopening with recipient scope', () =>
      runDeviceTest('notifications_inbox_live_test.dart', 'notifications-inbox-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, notificationIds }),
      }));
    const recipients = (await pool.query("select r.notification_id,u.role,r.is_read,r.read_at,n.title from app.notification_recipients r join app.notifications n on n.id=r.notification_id join app.users u on u.id=r.user_id where n.title like 'AUDIT-INBOX-%' order by u.role,n.title")).rows;
    fs.writeFileSync(path.join(output, 'notifications-inbox-db.json'), JSON.stringify(recipients, null, 2));
  }
  if (notificationSourceMode) {
    const sourceId = (await pool.query(
      "update app.lead_sources set canonical_name='st02',display_name='ST02 source' where canonical_name=$1 returning id",
      [`http_${runId}`])).rows[0].id;
    const controlDir = path.join(output, 'notification-control');
    fs.mkdirSync(controlDir);
    let deviceFinished = false;
    const device = runDeviceTest('notification_source_live_test.dart', 'notification-source-windows.log', {
      HTTP_JOURNEY_FIXTURE: JSON.stringify({baseUrl, password: fixture.password,
        accounts: fixture.clientAuditAccounts, controlDir}),
    }).finally(() => { deviceFinished = true; });
    const webhook = (async () => {
      const trigger = path.join(controlDir, 'trigger');
      for (let attempt = 0; !fs.existsSync(trigger); attempt++) {
        if (deviceFinished || attempt >= 600) throw Error('Native listener did not request inbound lead');
        await new Promise(resolve => setTimeout(resolve, 500));
      }
      const ingestionId = randomUUID();
      const payload = {firstName:'ST02',lastName:'Входящий',phone:'89991234568',sourceId,branchId:fixture.branch};
      const timestamp = Math.floor(Date.now() / 1000);
      const { createInboundLeadSignature } = require(path.join(server, 'src/crm/clients/inbound-lead-signature'));
      const signature = createInboundLeadSignature(leadWebhookSecret, timestamp, ingestionId, payload);
      async function send() {
        const response = await fetch(`${baseUrl}/public/lead-webhook`, {method:'POST',
          headers:{'content-type':'application/json','x-ingestion-id':ingestionId,
            'x-webhook-timestamp':String(timestamp),'x-webhook-signature':signature},
          body:JSON.stringify(payload),signal:AbortSignal.timeout(20000)});
        const body = await response.json();
        assert.equal(response.status, 201, `Webhook returned ${response.status}`);
        return body;
      }
      const first = await send(), replay = await send();
      assert.equal(first.leadId, replay.leadId);
      assert.equal(replay.replayed, true);
      fs.writeFileSync(path.join(controlDir, 'inbound-result.json'), JSON.stringify(replay));
      return {ingestionId, leadId:first.leadId};
    })();
    await check('Live Windows app listener routes manual and inbound lead notifications', async () => {
      const [native, external] = await Promise.allSettled([device, webhook]);
      if (native.status === 'rejected') throw native.reason;
      if (external.status === 'rejected') throw external.reason;
      const {ingestionId, leadId} = external.value;
      if (integratedCandidateMode) integratedLeadId = leadId;
      const state = {
        manualLeads:(await pool.query("select id from app.leads where first_name='ST02Edited' and last_name='Ручной'")).rows.length,
        manualNotifications:(await pool.query("select n.id from app.notifications n join app.leads l on l.id::text=n.data->>'entityId' where l.first_name='ST02Edited' and l.last_name='Ручной'")).rows.length,
        inboundLeads:(await pool.query('select id from app.leads where inbound_id=$1',[ingestionId])).rows.length,
        notifications:(await pool.query("select n.id,r.user_id,u.role from app.notifications n join app.notification_recipients r on r.notification_id=n.id join app.users u on u.id=r.user_id where n.data->>'entityId'=$1 order by u.role",[leadId])).rows,
        outbox:(await pool.query("select event_id,published_at from app.platform_outbox_events where request_id=$1",[`inbound-lead:${ingestionId}`])).rows,
      };
      assert.equal(state.manualLeads, 1);
      assert.equal(state.manualNotifications, 0);
      assert.equal(state.inboundLeads, 1);
      assert.equal(new Set(state.notifications.map(row=>row.user_id)).size, state.notifications.length);
      assert(state.notifications.some(row=>row.role==='admin'));
      assert(state.notifications.some(row=>row.role==='manager'));
      assert(!state.notifications.some(row=>row.role==='teacher'||row.role==='client'));
      const foreignUser = (await pool.query('select id from app.users where email=$1',
        [fixture.clientAuditAccounts.find(account=>account.role==='foreign-manager').email])).rows[0].id;
      assert(!state.notifications.some(row=>row.user_id===foreignUser));
      assert.equal(state.outbox.length, 1);
      assert(state.outbox[0].published_at);
      fs.writeFileSync(path.join(output, 'notification-source-db.json'), JSON.stringify(state,null,2));
      return {manualLeads:1, manualNotifications:0, inboundLeads:1,
        recipients:state.notifications.length, outboxStatus:'published'};
    });
    if (integratedCandidateMode) assert(integratedLeadId, 'Integrated journey requires a passing inbound UI step');
    if (!integratedCandidateMode) await require('./task-delivery-verification.cjs').runTaskDeliveryAudit({pool,fixture,baseUrl,output,check,
      closeOpenTask:taskId=>runDeviceTest('notification_task_close_live_test.dart','notification-task-close-windows.log',{
        HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,
          accounts:fixture.clientAuditAccounts,taskId})})});
  }
  if (process.argv.includes('--audit-messenger-extras')) {
    const members = (await pool.query('select id from app.users where email=any($1::text[])', [fixture.clientAuditAccounts.map(a => a.email)])).rows;
    const chat = await request('POST', '/messenger/groups', { name: 'AUDIT-EXTRA-CHAT', memberUserIds: members.map(m => m.id) }, 201);
    const forward = await request('POST', '/messenger/groups', { name: 'AUDIT-FORWARD-CHAT', memberUserIds: members.map(m => m.id) }, 201);
    await check('Messenger reactions forwarding pins and mute through actual message and chat menus', () =>
      runDeviceTest('messenger_extras_live_test.dart', 'messenger-extras-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, chatId: chat.id, forwardId: forward.id }),
      }));
    const messages = (await pool.query('select m.id,m.chat_id,u.role,m.content,m.forwarded_from_id,m.pinned_at,m.deleted_at from app.messages m join app.users u on u.id=m.sender_id where m.chat_id=any($1::uuid[]) order by u.role,m.created_at', [[chat.id, forward.id]])).rows;
    const reactions = (await pool.query('select r.* from app.message_reactions r join app.messages m on m.id=r.message_id where m.chat_id=$1', [chat.id])).rows;
    const chats = (await pool.query('select c.id,c.type,c.title from app.chats c where c.id=any($1::uuid[]) order by id', [[chat.id, forward.id]])).rows;
    fs.writeFileSync(path.join(output, 'messenger-extras-db.json'), JSON.stringify({ messages, reactions, chats }, null, 2));
  }
  if (process.argv.includes('--audit-phone-review')) {
    const phoneCases = {};
    for (const [index, role] of ['manager', 'director'].entries()) {
      const lead = (await pool.query("insert into app.leads(first_name,last_name,phone,branch_id) values ($1,'Аудит',$2,$3) returning id,version", ['PHONE-' + role, '123' + index, fixture.branch])).rows[0];
      const correct = (await pool.query("insert into app.phone_review_queue(entity_type,entity_id,raw_phone,reason) values ('lead',$1,$2,'too_short') returning id", [lead.id, '123' + index])).rows[0];
      const student = (await pool.query('select profile_id from app.students where id=$1', [fixture.students[index]])).rows[0];
      const originalPhone = '+1 212 555 010' + index;
      await pool.query('update app.profiles set phone=$2 where id=$1', [student.profile_id, originalPhone]);
      const accept = (await pool.query("insert into app.phone_review_queue(entity_type,entity_id,raw_phone,reason) values ('profile',$1,$2,'non_ru') returning id", [student.profile_id, originalPhone])).rows[0];
      phoneCases[role] = { correctId: correct.id, acceptId: accept.id, leadId: lead.id, profileId: student.profile_id, originalPhone };
    }
    await check('Phone queue decisions preserve reasons update canonical phones and keep accepted originals', () =>
      runDeviceTest('phone_review_live_test.dart', 'phone-review-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, phoneCases }),
      }));
    const queue = (await pool.query('select * from app.phone_review_queue order by id')).rows;
    const leads = (await pool.query('select id,phone,phone_normalized,version from app.leads where id=any($1::uuid[]) order by id', [Object.values(phoneCases).map(c => c.leadId)])).rows;
    const profiles = (await pool.query('select id,phone,phone_normalized from app.profiles where id=any($1::uuid[]) order by id', [Object.values(phoneCases).map(c => c.profileId)])).rows;
    fs.writeFileSync(path.join(output, 'phone-review-db.json'), JSON.stringify({ phoneCases, queue, leads, profiles }, null, 2));
  }
  if (process.argv.includes('--audit-plan-lifecycle') || process.argv.includes('--audit-plan-rows')) {
    if (process.argv.includes('--audit-plan-rows')) {
      const pkg=await request('POST','/crm/subscription-packages',{name:'PLAN-ROW-PACKAGE',branchId:fixture.branch,unitCount:8,basePriceMinor:'800000',currencyCode:'RUB',validityDays:90},201);
      const input={packageId:pkg.id,payerStudentId:fixture.students[1],fundingMode:'installment',purchaseReason:'Синтетическая проверка строки расписания',installments:[30,60].map(days=>({dueAt:new Date(Date.now()+days*86400000).toISOString(),amountMinor:'400000'}))};
      const preview=await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase/preview`,input,201);
      assert(preview.canCommit);
      const purchased=await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase`,{...input,previewToken:preview.previewToken,confirm:true},201);
      fixture.subscriptions[1]=purchased.subscription.id;
    }
    const from=new Date();from.setUTCDate(from.getUTCDate()+1);
    const to=new Date(from);to.setUTCDate(to.getUTCDate()+14);
    const plan=await request('POST','/crm/schedule-plans',{
      kind:'individual',title:'HTTP recurring journey',studentId:fixture.students[1],subscriptionId:fixture.subscriptions[1],
      activeFrom:from.toISOString().slice(0,10),activeUntil:to.toISOString().slice(0,10),
      rows:[{teacherId:fixture.teachers[1],roomId:fixture.rooms[1],branchId:fixture.branch,weekday:2,beginTime:'10:00',durationMinutes:60,
        financialDecision:{settlementTypeKey:'lesson',teacherCompensationRuleKey:'standard',clientDecisions:[{clientId:fixture.students[1],payerStudentId:fixture.students[1],chargeType:'subscription',subscriptionId:fixture.subscriptions[1]}]}}]
    },201,{key:randomUUID()});
    assert(plan);
    async function snapshot(){return {
      plan:(await pool.query('select * from app.schedule_plans where id=$1',[plan.id])).rows[0],
      series:(await pool.query('select * from app.schedule_series where plan_id=$1',[plan.id])).rows,
      lessons:(await pool.query('select l.* from app.lessons l join app.schedule_series s on s.id=l.series_id where s.plan_id=$1 order by l.scheduled_at',[plan.id])).rows,
      reservations:(await pool.query('select r.* from app.lesson_reservations r join app.lessons l on l.id=r.lesson_id join app.schedule_series s on s.id=l.series_id where s.plan_id=$1',[plan.id])).rows
    };}
    const before=await snapshot();
    await check('Schedule plan end archive restore through actual section',()=>runDeviceTest(process.argv.includes('--audit-plan-rows')?'plan_rows_live_test.dart':'schedule_plan_lifecycle_live_test.dart','plan-lifecycle-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,studentId:fixture.students[1],branchId:fixture.branch,planId:plan.id})
    }));
    fs.writeFileSync(path.join(output,'plan-lifecycle-db.json'),JSON.stringify({before,after:await snapshot()},null,2));
  }
  if(process.argv.includes('--audit-homework-files')){
    await request('POST','/crm/homeworks',{studentId:fixture.students[0],title:'AUDIT-CLIENT-FILE',description:'Синтетическое решение с файлом'},201);
    for(const role of ['admin','client'])await check('Homework files through actual '+role+' UI',()=>runDeviceTest('homework_files_live_test.dart','homework-files-'+role+'-windows.log',{
      HOMEWORK_AUDIT_ROLE:role,HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,studentId:fixture.students[0]})
    }));
    const db={};for(const table of ['lesson_homeworks','homework_attachments','file_objects'])db[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);
    fs.writeFileSync(path.join(output,'homework-files-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-account-purchase')){
    await request('POST','/crm/subscription-packages',{name:'PURCHASE-PACKAGE',branchId:fixture.branch,unitCount:8,basePriceMinor:'800000',currencyCode:'RUB',validityDays:90},201);
    await check('Purchase from existing account balance through actual card',()=>runDeviceTest('account_purchase_live_test.dart','account-purchase-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const db={};for(const table of ['subscriptions','payments','account_adjustments','client_payment_records','subscription_obligation_facts','subscription_lifecycle_events'])db[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);
    fs.writeFileSync(path.join(output,'account-purchase-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-profile-avatar')){
    await check('Five roles real crop upload replace and failed profile save',()=>runDeviceTest('profile_avatar_live_test.dart','profile-avatar-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,avatarPath:path.join(root,'assets/icon.png')})
    }));
    const db={profiles:(await pool.query('select p.id,p.user_id,p.avatar_file_id,u.role from app.profiles p join app.users u on u.id=p.user_id where p.avatar_file_id is not null')).rows,files:(await pool.query("select * from app.file_objects where purpose='profile_avatar'")).rows};
    fs.writeFileSync(path.join(output,'profile-avatar-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-messenger-structure')){
    await check('Actual messenger groups channel editors and attachment forms',()=>runDeviceTest('messenger_structure_live_test.dart','messenger-structure-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts})
    }));
    const db={groups:(await pool.query("select id,title,created_by from app.chats where title like 'AUDIT-UI-GROUP-%' order by title")).rows,
      members:(await pool.query("select m.chat_id,m.user_id,m.left_at from app.chat_members m join app.chats c on c.id=m.chat_id where c.title like 'AUDIT-UI-GROUP-%' order by c.title,m.user_id")).rows,
      channels:(await pool.query("select id,title,description from app.channels where title like 'AUDIT-UI-CHANNEL-%' order by title")).rows,
      files:(await pool.query("select id,sha256,size_bytes,deleted_at from app.file_objects where purpose='chat_attachment' order by id")).rows};
    fs.writeFileSync(path.join(output,'messenger-structure-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-students-pagination')){
    let oldestStudent;
    for(let i=1;i<=105;i++){
      const name='AUDIT-PAGE-'+String(i).padStart(3,'0');
      const u=(await pool.query("insert into app.users(email,role,is_app_account) values($1,'client',false) returning id",[name+'-'+runId+'@example.test'])).rows[0].id;
      const p=(await pool.query("insert into app.profiles(user_id,first_name,last_name) values($1,$2,'') returning id",[u,name])).rows[0].id;
      const student=(await pool.query("insert into app.students(profile_id,branch_id,created_at) values($1,$2,now()+$3*interval '1 second') returning id",[p,fixture.branch,i])).rows[0].id;
      if(i===1)oldestStudent=student;
      await pool.query("insert into app.lessons(student_id,teacher_id,branch_id,scheduled_at,duration_minutes) values($1,$2,$3,'2028-01-01T09:00:00Z'::timestamptz+$4*interval '1 day',60)",[student,fixture.teachers[0],fixture.branch,i]);
    }
    const allStudents=(await pool.query('select id from app.students where deleted_at is null')).rows.map(r=>r.id);
    const teacherStudents=(await pool.query('select distinct s.id from app.students s join app.lessons l on l.student_id=s.id where l.teacher_id=$1 and l.deleted_at is null and s.deleted_at is null',[fixture.teachers[0]])).rows.map(r=>r.id);
    const snapshot=async()=>(await pool.query('select id,version,status,deleted_at from app.students order by id')).rows;const before=await snapshot();
    await check('Actual student boards and teacher list pagination',()=>runDeviceTest('students_pagination_live_test.dart','students-pagination-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,allStudents,teacherStudents,oldestStudent})
    }));
    fs.writeFileSync(path.join(output,'students-pagination-db.json'),JSON.stringify({before,after:await snapshot(),allStudents,teacherStudents,oldestStudent},null,2));
  }
  if(process.argv.includes('--audit-messenger-inbox')){
    const users=(await pool.query('select u.id,u.role,p.id profile_id from app.users u join app.profiles p on p.user_id=u.id where u.email=any($1::text[])',[fixture.clientAuditAccounts.map(a=>a.email)])).rows;
    const director=users.find(u=>u.role==='director'),client=users.find(u=>u.role==='client');
    const staff=(await pool.query("insert into app.staff_members(profile_id,role,status) values($1,'director','working') returning id",[director.profile_id])).rows[0];
    await pool.query('insert into app.staff_branch_assignments(staff_member_id,branch_id) values($1,$2)',[staff.id,fixture.branch]);
    const account=fixture.clientAuditAccounts.find(a=>a.role==='client');
    const login=await fetch(baseUrl+'/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:account.email,password:fixture.password})});assert.equal(login.status,200);const session=await login.json();
    const response=await fetch(baseUrl+'/messenger/chats/direct',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+session.session.accessToken},body:JSON.stringify({type:'administration'})});assert.equal(response.status,201);const inbox=await response.json();
    const groupIds=[];
    for(let i=1;i<=105;i++){
      const g=(await pool.query("insert into app.chats(type,title,created_by) values('group',$1,$2) returning id",['AUDIT-PAGING-'+String(i).padStart(3,'0'),director.id])).rows[0].id;groupIds.push(g);
      for(const u of users.filter(u=>u.role!=='teacher'))await pool.query('insert into app.chat_members(chat_id,user_id) values($1,$2)',[g,u.id]);
    }
    await check('Actual inbox assignment archive directory pagination and contact links',()=>runDeviceTest('messenger_inbox_live_test.dart','messenger-inbox-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,groupIds,inboxId:inbox.id,clientUserId:client.id,clientProfileId:client.profile_id})
    }));
    const db={inbox:(await pool.query('select id,assigned_to_user_id from app.chats where id=$1',[inbox.id])).rows,archive:(await pool.query('select staff_user_id,archived_at from app.chat_inbox_state where chat_id=$1',[inbox.id])).rows,groups:(await pool.query("select id,title from app.chats where title like 'AUDIT-PAGING-%'")).rows};
    db.notes=(await pool.query("select id,profile_id,author_id,body from app.profile_notes where body like 'AUDIT-PROFILE-NOTE-%' order by body")).rows;
    fs.writeFileSync(path.join(output,'messenger-inbox-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-plan-create')){
    const pkg=await request('POST','/crm/subscription-packages',{name:'PLAN-CREATE-PACKAGE',branchId:fixture.branch,unitCount:12,basePriceMinor:'1200000',currencyCode:'RUB',validityDays:365},201);
    const purchaseInput={packageId:pkg.id,payerStudentId:fixture.students[1],fundingMode:'installment',purchaseReason:'Синтетическая проверка создания расписания',installments:[30,60].map(days=>({dueAt:new Date(Date.now()+days*86400000).toISOString(),amountMinor:'600000'}))};
    const preview=await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase/preview`,purchaseInput,201);assert(preview.canCommit);
    await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase`,{...purchaseInput,previewToken:preview.previewToken,confirm:true},201);
    await check('Actual multi-day multi-resource plan creation editor',()=>runDeviceTest('plan_create_live_test.dart','plan-create-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,studentId:fixture.students[1],branchId:fixture.branch,teachers:fixture.teachers})
    }));
    const db={plans:(await pool.query("select * from app.schedule_plans where title='AUDIT-MULTI-ROW-PLAN'")).rows,
      series:(await pool.query("select s.* from app.schedule_series s join app.schedule_plans p on p.id=s.plan_id where p.title='AUDIT-MULTI-ROW-PLAN'")).rows,
      lessons:(await pool.query("select l.id,l.scheduled_at,l.teacher_id,l.room_id,l.version,l.status from app.lessons l join app.schedule_series s on s.id=l.series_id join app.schedule_plans p on p.id=s.plan_id where p.title='AUDIT-MULTI-ROW-PLAN' order by l.scheduled_at")).rows,
      reservations:(await pool.query("select r.* from app.lesson_reservations r join app.lessons l on l.id=r.lesson_id join app.schedule_series s on s.id=l.series_id join app.schedule_plans p on p.id=s.plan_id where p.title='AUDIT-MULTI-ROW-PLAN'")).rows};
    fs.writeFileSync(path.join(output,'plan-create-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-access-credentials')){
    const credentialTargets={};
    for(const type of ['staff','teacher']){
      const u=(await pool.query("insert into app.users(email,role,is_app_account) values($1,$2,false) returning id",['audit-access-initial-'+type+'@example.test',type==='staff'?'admin':'teacher'])).rows[0];
      const p=(await pool.query("insert into app.profiles(user_id,first_name,last_name) values($1,$2,'HTTP test') returning id",[u.id,'AUDIT-ACCESS-'+type])).rows[0];
      if(type==='staff'){
        credentialTargets.staff=(await pool.query("insert into app.staff_members(profile_id,role,status) values($1,'admin','working') returning id",[p.id])).rows[0].id;
        await pool.query('insert into app.staff_branch_assignments(staff_member_id,branch_id) values($1,$2)',[credentialTargets.staff,fixture.branch]);
      }else{
        credentialTargets.teacher=(await pool.query('insert into app.teachers(profile_id) values($1) returning id',[p.id])).rows[0].id;
        await pool.query("insert into app.teacher_branches(teacher_id,branch_id,active_from,active_until) values($1,$2,'2020-01-01','2100-12-31')",[credentialTargets.teacher,fixture.branch]);
      }
    }
    const auto=(await pool.query("insert into app.users(email,role,is_app_account) values('audit-autolink@example.test','client',true) returning id")).rows[0];
    credentialTargets.autoProfile=(await pool.query("insert into app.profiles(user_id,first_name,last_name,phone) values($1,'AUDIT-AUTO','HTTP test','+79991234567') returning id",[auto.id])).rows[0].id;
    credentialTargets.grantUser=auto.id;
    await pool.query('update app.users set is_app_account=false where id=(select p.user_id from app.students s join app.profiles p on p.id=s.profile_id where s.id=$1)',[fixture.students[1]]);
    await pool.query("update app.profiles set phone='+79991234567' where id=(select profile_id from app.students where id=$1)",[fixture.students[1]]);
    await check('Actual staff teacher credential provisioning account search autolink and grant',()=>runDeviceTest('access_credentials_live_test.dart','access-credentials-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,studentId:fixture.students[1],credentialTargets})
    }));
    const accounts=(await pool.query("select u.id,u.email,u.role,u.is_app_account,u.password_hash from app.users u join app.profiles p on p.user_id=u.id where p.first_name like 'AUDIT-ACCESS-%'")).rows;
    const saved=[];for(const account of accounts){const {password_hash,...safe}=account;saved.push({...safe,passwordMatches:password_hash ? await new PasswordService().verify(fixture.password+'2',password_hash) : false});}
    const db={accounts:saved,links:(await pool.query('select * from app.user_crm_links where user_id=$1',[auto.id])).rows,credentialTargets};
    fs.writeFileSync(path.join(output,'access-credentials-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-auth-runtime')){
    await check('Actual access retry legal links logout and account switch',()=>runDeviceTest('auth_runtime_live_test.dart','auth-runtime-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts})
    }));
    const db={accounts:(await pool.query('select u.id,u.email,u.role,p.id profile_id,p.first_name,p.last_name from app.users u join app.profiles p on p.user_id=u.id where u.email=any($1::text[])',[fixture.clientAuditAccounts.map(a=>a.email)])).rows};
    fs.writeFileSync(path.join(output,'auth-runtime-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-client-extended')){
    const cardPackage = await request('POST', '/crm/subscription-packages', {
      name: 'CARD-VIEWPORT', branchId: fixture.branch, unitCount: 8,
      basePriceMinor: '800000', currencyCode: 'RUB', validityDays: 90,
    }, 201);
    const cardPurchase = {packageId: cardPackage.id, payerStudentId: fixture.students[0],
      fundingMode: 'personal_account', paymentAmountMinor: '800000', paymentMethod: 'cash',
      purchaseReason: 'Карточка с оплаченным абонементом'};
    const cardPreview = await request('POST', `/crm/students/${fixture.students[0]}/subscriptions/purchase/preview`, cardPurchase, 201);
    assert(cardPreview.canCommit);
    await request('POST', `/crm/students/${fixture.students[0]}/subscriptions/purchase`, {
      ...cardPurchase, previewToken: cardPreview.previewToken, confirm: true,
    }, 201);
    const secondBranchId=(await pool.query("insert into app.branches(name,timezone_name) values('AUDIT-SECOND-BRANCH','Europe/Moscow') returning id")).rows[0].id;
    await pool.query('insert into app.staff_branch_assignments(staff_member_id,branch_id) select sm.id,$1 from app.staff_members sm join app.profiles p on p.id=sm.profile_id join app.users u on u.id=p.user_id where u.email=any($2::text[])',[secondBranchId,fixture.clientAuditAccounts.map(a=>a.email)]);
    await check('Actual client creation dynamic fields and card branch source birthday',()=>runDeviceTest('client_extended_live_test.dart','client-extended-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,secondBranchId,populatedStudentId:fixture.students[0]})
    }));
    const db={leads:(await pool.query("select id,first_name,last_name,branch_id,source_id,custom_data,version from app.leads where first_name='AUDIT-EXTENDED'")).rows,students:(await pool.query("select s.id,p.first_name,p.last_name,s.branch_id,s.source_id,s.custom_data,s.version from app.students s join app.profiles p on p.id=s.profile_id where p.first_name='AUDIT-EXTENDED'")).rows};
    db.fieldValues=(await pool.query('select d.field_key,v.entity_type,v.entity_id,v.value_text,v.value_number,v.value_boolean,v.value_date::text from app.client_custom_field_values v join app.client_custom_field_definitions d on d.id=v.definition_id where v.entity_id=any($1::uuid[])',[[...db.leads,...db.students].map(r=>r.id)])).rows;
    fs.writeFileSync(path.join(output,'client-extended-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-plan-timeline') || process.argv.includes('--audit-x03')){
    const timelineUser=(await pool.query("insert into app.users(email,role,is_app_account) values('audit-timeline@example.test','client',false) returning id")).rows[0].id;
    const timelineProfile=(await pool.query("insert into app.profiles(user_id,first_name,last_name) values($1,'AUDIT','TIMELINE') returning id",[timelineUser])).rows[0].id;
    const student=(await pool.query('insert into app.students(profile_id,branch_id) values($1,$2) returning id',[timelineProfile,fixture.branch])).rows[0].id;
    const pkg=await request('POST','/crm/subscription-packages',{name:'PLAN-TIMELINE-PACKAGE',branchId:fixture.branch,unitCount:200,basePriceMinor:'20000000',currencyCode:'RUB',validityDays:365},201);
    const input={packageId:pkg.id,payerStudentId:student,fundingMode:'installment',purchaseReason:'Синтетическая проверка ленты занятий',installments:[30,60].map(days=>({dueAt:new Date(Date.now()+days*86400000).toISOString(),amountMinor:'10000000'}))};
    const preview=await request('POST','/crm/students/'+student+'/subscriptions/purchase/preview',input,201);assert(preview.canCommit);
    const purchase=await request('POST','/crm/students/'+student+'/subscriptions/purchase',{...input,previewToken:preview.previewToken,confirm:true},201);
    const from=new Date(Date.now()+86400000),to=new Date(Date.now()+211*86400000);
    for(let i=0;i<4;i++)await request('POST','/crm/schedule-plans',{
      kind:'individual',title:'AUDIT-TIMELINE-'+(i+1),studentId:student,subscriptionId:purchase.subscription.id,
      activeFrom:from.toISOString().slice(0,10),activeUntil:to.toISOString().slice(0,10),
      rows:[{teacherId:fixture.teachers[i%2],roomId:fixture.rooms[i%2],branchId:fixture.branch,weekday:i+1,beginTime:'19:00',durationMinutes:60,
        financialDecision:{settlementTypeKey:'lesson',teacherCompensationRuleKey:'standard',clientDecisions:[{clientId:student,payerStudentId:student,chargeType:'subscription',subscriptionId:purchase.subscription.id}]}}]
    },201,{key:randomUUID()});
    const snapshot=async()=>(await pool.query("select l.id,l.version,l.status,l.scheduled_at from app.lessons l join app.schedule_series s on s.id=l.series_id join app.schedule_plans p on p.id=s.plan_id where p.student_id=$1 order by l.scheduled_at",[student])).rows;
    const before=await snapshot();assert(before.length>90);
    const x03=process.argv.includes('--audit-x03');
    await check(x03?'X-03 two staff UI sessions, real CRM stream and current timeline':'Actual schedule plan and lesson timeline pagination and lesson opening',()=>runDeviceTest(x03?'x03_live_test.dart':'plan_timeline_live_test.dart',x03?'x03-windows.log':'plan-timeline-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,studentId:student,lessonIds:before.map(l=>l.id),edgeLessonId:before[29].id,edgeScheduledAt:before[29].scheduled_at,recoveryLessonId:before[8].id,recoveryScheduledAt:before[8].scheduled_at,conflictLessonId:before[12].id,conflictScheduledAt:before[12].scheduled_at})
    }));
    const ui = JSON.parse(fs.readFileSync(path.join(output,x03?'x03-admin.json':'plan-timeline-director.json'),'utf8'));
    const chain = ui.facts.find(fact=>fact.step==='CANCEL-CURRENT' && Array.isArray(fact.chain))?.chain;
    assert.equal(chain?.length,3,'Two moves and cancellation must produce three linked lessons');
    const linked=(await pool.query('select id,predecessor_id,successor_id,lifecycle_state from app.lessons where id=any($1::uuid[]) order by array_position($1::uuid[],id)',[chain])).rows;
    assert.equal(linked.length,3);
    assert.deepEqual(linked.map(row=>row.lifecycle_state),['rescheduled','rescheduled','cancelled']);
    assert.deepEqual(linked.map(row=>row.successor_id),[chain[1],chain[2],null]);
    const transitions=(await pool.query('select lesson_id,to_state,successor_id from app.lesson_transitions where lesson_id=any($1::uuid[]) order by array_position($1::uuid[],lesson_id)',[chain])).rows;
    assert.deepEqual(transitions.map(row=>row.to_state),['rescheduled','rescheduled','cancelled']);
    const audits=(await pool.query("select entity_id,action from app.audit_events where entity_type='lesson' and entity_id=any($1::text[]) and action in ('crm.lesson_rescheduled','crm.lesson_cancelled') order by array_position($1::text[],entity_id)",[chain])).rows;
    assert.deepEqual(audits.map(row=>row.action),['crm.lesson_rescheduled','crm.lesson_rescheduled','crm.lesson_cancelled']);
    const outbox=(await pool.query("select aggregate_id,event_type from app.platform_outbox_events where aggregate_type='schedule:lesson' and aggregate_id=any($1::text[]) and event_type='schedule.lesson.changed' order by array_position($1::text[],aggregate_id)",[chain])).rows;
    assert.equal(outbox.length,3,'Each UI transition must retain one outbox event');
    let otherChains=null;
    if(x03){
      const recovered=ui.facts.find(fact=>fact.step==='MISSED-EVENT' && fact.successorId);
      const retried=ui.facts.find(fact=>fact.step==='ERROR-RETRY' && fact.successorId);
      const conflict=ui.facts.find(fact=>fact.step==='CONCURRENT-VERSION' && fact.staleLessonId);
      assert(recovered && retried && conflict,'Recovery, retry and concurrency UI facts are required');
      const recoveryIds=[recovered.sourceId,recovered.successorId,retried.successorId];
      const recoveryTransitions=(await pool.query('select lesson_id,to_state from app.lesson_transitions where lesson_id=any($1::uuid[]) order by array_position($1::uuid[],lesson_id)',[recoveryIds])).rows;
      assert.deepEqual(recoveryTransitions.map(row=>row.to_state),['rescheduled','rescheduled']);
      const conflictTransitions=(await pool.query('select lesson_id,to_state from app.lesson_transitions where lesson_id=$1',[conflict.staleLessonId])).rows;
      assert.deepEqual(conflictTransitions.map(row=>row.to_state),['rescheduled']);
      otherChains={recoveryIds,recoveryTransitions,conflictLessonId:conflict.staleLessonId,conflictTransitions};
    }
    await check('Linked client reads only scoped current timeline',async()=>{
      const clientAccount=fixture.clientAuditAccounts.find(account=>account.role==='client');
      const clientUser=(await pool.query('select id from app.users where email=$1',[clientAccount.email])).rows[0].id;
      await pool.query("insert into app.user_crm_links(user_id,entity_type,entity_id,link_source,confirmed_at) values($1,'student',$2,'import',now())",[clientUser,student]);
      const previousToken=token;
      try {
        token=(await request('POST','/auth/login',{email:clientAccount.email,password:fixture.password},200,{auth:false})).session.accessToken;
        const own=await request('GET',`/crm/students/${student}/lesson-timeline`);
        assert(own.items.length>0);
        assert(own.items.every(item=>!chain.includes(item.id)));
        const foreign=await request('GET',`/crm/students/${fixture.students[1]}/lesson-timeline`,undefined,[200,403,404]);
        assert(!foreign.items?.length,'Unlinked student lessons must not be exposed');
      } finally { token=previousToken; }
    });
    await check('Fresh Windows client process reads only current student lessons',()=>runDeviceTest('plan_timeline_live_test.dart','plan-timeline-restart-windows.log',{
      ST04_TIMELINE_RESTART:'1',
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,
        branchId:fixture.branch,studentId:student,lessonIds:before.map(lesson=>lesson.id),chain}),
    }));
    fs.writeFileSync(path.join(output,'plan-timeline-db.json'),JSON.stringify({before,after:await snapshot(),chain:linked,transitions,audits,outbox,otherChains},null,2));
  }
  if(process.argv.includes('--audit-task-navigation')){
    await check('Actual task calendar scope history and linked entity navigation',()=>runDeviceTest('task_navigation_live_test.dart','task-navigation-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,students:fixture.students})
    }));
    const tasks=(await pool.query("select to_jsonb(t) value from app.canonical_tasks t where title like 'AUDIT-TASK-NAV-%' order by title")).rows.map(r=>r.value);
    fs.writeFileSync(path.join(output,'task-navigation-db.json'),JSON.stringify({tasks},null,2));
  }
  if(process.argv.includes('--audit-finance-access')){
    async function financeSnapshot(){const data={};for(const table of ['payments','account_adjustments','client_payment_records','lesson_client_charge_facts','lesson_teacher_compensation_facts'])data[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t order by t.id')).rows.map(r=>r.row);return data;}
    const before=await financeSnapshot();
    for(const auditRole of ['admin','manager'])await check('Actual finance read permission revoked from live card '+auditRole,()=>runDeviceTest('finance_access_live_test.dart','finance-access-'+auditRole+'-windows.log',{
      ACCESS_AUDIT_ROLE:auditRole,
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,students:fixture.students})
    }));
    const accounts=(await pool.query("select u.id,u.role,v.version access_version from app.users u join app.user_access_versions v on v.user_id=u.id where u.email=any($1::text[]) order by u.role",[fixture.clientAuditAccounts.map(a=>a.email)])).rows;
    fs.writeFileSync(path.join(output,'finance-access-db.json'),JSON.stringify({before,after:await financeSnapshot(),accounts},null,2));
  }

  if(process.argv.includes('--audit-access-runtime')){
    for(const auditRole of ['admin','manager'])await check('Actual open card permission revocation through real WebSocket '+auditRole,()=>runDeviceTest('access_runtime_live_test.dart','access-runtime-'+auditRole+'-windows.log',{
      ACCESS_AUDIT_ROLE:auditRole,
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,students:fixture.students})
    }));
    const accounts=(await pool.query("select u.id,u.email,u.role,v.version access_version from app.users u join app.user_access_versions v on v.user_id=u.id where u.email=any($1::text[])",[fixture.clientAuditAccounts.map(a=>a.email)])).rows;
    fs.writeFileSync(path.join(output,'access-runtime-db.json'),JSON.stringify({accounts},null,2));
  }
  if(process.argv.includes('--audit-overview-runtime')){
    await check('Actual overview loading recovery refresh and KPI destinations',()=>runDeviceTest('overview_runtime_live_test.dart','overview-runtime-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,students:fixture.students})
    }));
    const leads=(await pool.query("select id,first_name,last_name,branch_id from app.leads where first_name='AUDIT-OVERVIEW' order by last_name")).rows;
    fs.writeFileSync(path.join(output,'overview-runtime-db.json'),JSON.stringify({leads},null,2));
  }
  if(process.argv.includes('--audit-deep-link')){
    await check('Actual entity URI redirect through login and signed-in router',()=>runDeviceTest('deep_link_live_test.dart','deep-link-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,students:fixture.students})
    }));
    fs.writeFileSync(path.join(output,'deep-link-db.json'),JSON.stringify({students:fixture.students},null,2));
  }
  if(process.argv.includes('--audit-purchase-retry')){
    await request('POST','/crm/subscription-packages',{name:'RETRY-PACKAGE',branchId:fixture.branch,unitCount:8,basePriceMinor:'800000',currencyCode:'RUB',validityDays:90},201);
    await check('Actual related payer purchase survives a lost committed response',()=>runDeviceTest('purchase_retry_live_test.dart','purchase-retry-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const db={};for(const table of ['subscriptions','payments','account_adjustments','client_payment_records','subscription_obligation_facts','subscription_lifecycle_events','family_members'])db[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);
    fs.writeFileSync(path.join(output,'purchase-retry-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-group-plan')){
    const performanceTeachers = Number(process.env.GROUP_PERF_TEACHERS || 0);
    assert(Number.isInteger(performanceTeachers) && performanceTeachers >= 0 && performanceTeachers <= 50);
    for (let index = 2; index < performanceTeachers; index++) {
      const user = (await pool.query("insert into app.users(email,role,is_app_account) values($1,'teacher',false) returning id", ['group-perf-'+index+'@example.test'])).rows[0].id;
      const profile = (await pool.query("insert into app.profiles(user_id,first_name,last_name) values($1,$2,'HTTP test') returning id", [user, 'PerfTeacher'+index])).rows[0].id;
      const teacher = (await pool.query('insert into app.teachers(profile_id) values($1) returning id', [profile])).rows[0].id;
      await pool.query("insert into app.teacher_branches(teacher_id,branch_id,active_from,active_until) values($1,$2,'2020-01-01','2100-12-31')", [teacher, fixture.branch]);
      await pool.query("insert into app.teacher_availability_rules(teacher_id,kind,available,timezone_name,weekday,local_start,local_end,valid_from,valid_until) select $1,'recurring',true,'Europe/Moscow',day,'08:00','22:00','2020-01-01','2100-12-31' from generate_series(1,7) day", [teacher]);
      await pool.query("insert into app.teacher_rates(teacher_id,rate,effective_from) values($1,800,'2020-01-01')", [teacher]);
    }
    const students=[];
    const secondBranch=await request('POST','/crm/branches',{name:'GROUP-SECOND-BRANCH',weeklyHours:Array.from({length:7},(_,i)=>({weekday:i+1,open:'08:00',close:'22:00'}))},201);
    await request('POST','/crm/rooms',{name:'GROUP-SECOND-ROOM',branchId:secondBranch.id,capacity:8},201);
    await pool.query("insert into app.teacher_branches(teacher_id,branch_id,active_from,active_until) values($1,$2,'2020-01-01','2100-12-31')",[fixture.teachers[1],secondBranch.id]);
    const pkg=await request('POST','/crm/subscription-packages',{name:'GROUP-PLAN-PACKAGE',branchId:fixture.branch,unitCount:20,basePriceMinor:'2000000',currencyCode:'RUB',validityDays:365},201);
    const group=await request('POST','/crm/groups',{name:'AUDIT-GROUP-PLAN',teacherId:fixture.teachers[1],branchId:fixture.branch,roomId:fixture.rooms[1],pricePerLesson:1000},201);
    assert.equal(group.settlementTypeKey,null);assert.equal(group.teacherCompensationRuleKey,null);
    for(let i=0;i<2;i++){
      const u=(await pool.query("insert into app.users(email,role,is_app_account) values($1,'client',false) returning id",['audit-group-plan-'+i+'@example.test'])).rows[0];
      const p=(await pool.query("insert into app.profiles(user_id,first_name,last_name) values($1,$2,'HTTP test') returning id",[u.id,'AUDIT-GROUP-STUDENT-'+i])).rows[0];
      const st=(await pool.query("insert into app.students(profile_id,branch_id) values($1,$2) returning id",[p.id,fixture.branch])).rows[0];students.push(st.id);
      const input={packageId:pkg.id,payerStudentId:st.id,fundingMode:'installment',purchaseReason:'Аудит группового расписания',installments:[30,60].map(days=>({dueAt:new Date(Date.now()+days*86400000).toISOString(),amountMinor:'1000000'}))};
      const preview=await request('POST','/crm/students/'+st.id+'/subscriptions/purchase/preview',input,201);assert(preview.canCommit);
      await request('POST','/crm/students/'+st.id+'/subscriptions/purchase',{...input,previewToken:preview.previewToken,confirm:true},201);
      await request('POST','/crm/groups/'+group.id+'/students',{studentId:st.id},201);
    }
    await check('Actual group plan creation and dated participants replacement',()=>runDeviceTest('group_plan_live_test.dart','group-plan-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,students,groupId:group.id,branchId:fixture.branch,secondBranchId:secondBranch.id,teacherId:fixture.teachers[1],roomId:fixture.rooms[1],performanceTeachers,performancePhase:process.env.GROUP_PERF_PHASE||'unspecified'})
    }));
    await check('Group defaults update replays safely and leaves existing lesson decisions unchanged', async()=>{
      const before=(await pool.query('select lesson_id,decision from app.lesson_settlement_plans order by lesson_id')).rows;
      const current=await request('GET','/crm/groups/'+group.id);
      const body={expectedVersion:current.version,settlementTypeKey:'lesson',teacherCompensationRuleKey:'none'};
      const key=randomUUID();
      const updated=await request('PATCH','/crm/groups/'+group.id,body,200,{key});
      assert.equal(updated.teacherCompensationRuleKey,'none');
      assert.equal((await request('PATCH','/crm/groups/'+group.id,body,200,{key})).version,updated.version);
      await request('PATCH','/crm/groups/'+group.id,body,409);
      assert.deepEqual((await pool.query('select lesson_id,decision from app.lesson_settlement_plans order by lesson_id')).rows,before);
    });
    await check('Manager creates one whole-group lesson with inherited rules, replay, audit and reservations', async()=>{
      const previousToken=token;
      try {
        const account=fixture.clientAuditAccounts.find(item=>item.role==='manager');
        token=(await request('POST','/auth/login',{email:account.email,password:fixture.password},200,{auth:false})).session.accessToken;
        const funding=(await pool.query("select id,student_id from app.subscriptions where student_id=any($1::uuid[]) and status='active'",[students])).rows;
        const body={groupId:group.id,scheduledAt:'2027-01-20T12:00:00Z',durationMinutes:60,isTrial:false,completionType:'standard.success',
          financialDecision:{settlementTypeKey:'free_lesson',clientDecisions:students.map(clientId=>({clientId,settlementTypeKey:'free_lesson',chargeType:'subscription',subscriptionId:funding.find(item=>item.student_id===clientId).id}))}};
        const key=randomUUID(),lesson=await request('POST','/crm/lessons',body,201,{key});
        assert.equal((await request('POST','/crm/lessons',body,201,{key})).id,lesson.id);
        const saved=(await pool.query(`select l.teacher_id,l.room_id,l.student_id,l.lead_id,p.decision,
          (select count(*)::int from app.lesson_snapshot_participants where lesson_id=l.id) participants,
          (select count(*)::int from app.lesson_reservations where lesson_id=l.id and state='reserved') reservations,
          (select count(*)::int from app.audit_events where entity_id=l.id::text and action='crm.lesson_created') audits,
          (select count(*)::int from app.platform_outbox_events where aggregate_id=l.id::text) events
          from app.lessons l join app.lesson_settlement_plans p on p.lesson_id=l.id where l.id=$1`,[lesson.id])).rows[0];
        assert.equal(saved.teacher_id,fixture.teachers[1]);assert.equal(saved.room_id,fixture.rooms[1]);
        assert.equal(saved.student_id,null);assert.equal(saved.lead_id,null);
        assert.equal(saved.decision.settlementTypeKey,'lesson');assert.equal(saved.decision.teacherCompensationRuleKey,'none');
        assert(saved.decision.clientDecisions.every(item=>(item.settlementTypeKey??saved.decision.settlementTypeKey)==='lesson' && item.chargeDurationMinutes===60));
        assert.deepEqual([saved.participants,saved.reservations,saved.audits,saved.events],[2,2,1,1]);
        await request('POST','/crm/lessons',{...body,scheduledAt:'2027-01-21T12:00:00Z',financialDecision:{...body.financialDecision,teacherCompensationRuleKey:'standard'}},403);
        await request('PATCH','/crm/groups/'+group.id,{expectedVersion:(await request('GET','/crm/groups/'+group.id)).version,teacherCompensationRuleKey:'standard'},403);
        await request('POST','/crm/lessons',{...body,scheduledAt:'2027-01-21T12:00:00Z',financialDecision:{...body.financialDecision,clientDecisions:body.financialDecision.clientDecisions.slice(0,1)}},422);
        assert.equal((await pool.query("select count(*)::int count from app.lessons where group_id=$1 and scheduled_at='2027-01-21T12:00:00Z'",[group.id])).rows[0].count,0);
      } finally {token=previousToken;}
    });
    await check('Single group lesson checks every member and rolls back a participant conflict',async()=>{
      await request('POST','/crm/lessons',{clientRef:{type:'student',id:students[1]},teacherId:fixture.teachers[0],branchId:fixture.branch,roomId:fixture.rooms[0],scheduledAt:'2027-01-22T12:00:00Z',durationMinutes:60,isTrial:false,completionType:'standard.success',clientChargeType:'personal_account',clientChargeValue:1000,teacherCompensationType:'hourly',teacherCompensationValue:700,financialDecision:{settlementTypeKey:'lesson',teacherCompensationRuleKey:'standard',clientDecisions:[{clientId:students[1],payerStudentId:students[1],chargeType:'personal_account',basePriceMinor:'100000'}]}},201);
      const result=await request('POST','/crm/lessons',{groupId:group.id,scheduledAt:'2027-01-22T12:00:00Z',durationMinutes:60,isTrial:false,completionType:'standard.success',financialDecision:{settlementTypeKey:'lesson',clientDecisions:students.map(clientId=>({clientId,chargeType:'none'}))}},422);
      assert.equal(result.code,'LESSON_CONSTRAINT_VIOLATIONS');
      assert.equal((await pool.query("select count(*)::int count from app.lessons where group_id=$1 and scheduled_at='2027-01-22T12:00:00Z'",[group.id])).rows[0].count,0);
    });
    await check('Group defaults migration rollback is reversible without changing history',async()=>{
      const client=await pool.connect();
      try {
        await client.query('begin');
        await client.query(fs.readFileSync(path.join(root,'server/db/migrations/0162_group_lesson_defaults.down.sql'),'utf8'));
        assert.equal((await client.query("select count(*)::int count from information_schema.columns where table_schema='app' and table_name='groups' and column_name='settlement_type_key'")).rows[0].count,0);
        await client.query('rollback');
        assert.equal((await request('GET','/crm/groups/'+group.id)).teacherCompensationRuleKey,'none');
      } finally {await client.query('rollback');client.release();}
    });
    await check('Partial group charges and teacher minutes inherit group types for single and recurring lessons',async()=>{
      const current=await request('GET','/crm/groups/'+group.id);
      await request('PATCH','/crm/groups/'+group.id,{expectedVersion:current.version,settlementTypeKey:'partially_paid_lesson',teacherCompensationRuleKey:'standard'});
      const funding=(await pool.query("select id,student_id from app.subscriptions where student_id=any($1::uuid[]) and status='active'",[students])).rows;
      const clientDecisions=students.map(clientId=>({clientId,chargeType:'subscription',subscriptionId:funding.find(item=>item.student_id===clientId).id,chargeDurationMinutes:30}));
      const financialDecision={settlementTypeKey:'lesson',teacherCreditedDurationMinutes:30,clientDecisions};
      const lesson=await request('POST','/crm/lessons',{groupId:group.id,scheduledAt:'2027-01-23T12:00:00Z',durationMinutes:60,isTrial:false,completionType:'standard.success',financialDecision},201);
      const single=(await pool.query('select decision from app.lesson_settlement_plans where lesson_id=$1',[lesson.id])).rows[0].decision;
      assert.equal(single.settlementTypeKey,'partially_paid_lesson');assert.equal(single.teacherCompensationRuleKey,'standard');assert.equal(single.teacherCreditedDurationMinutes,30);
      assert.equal((await pool.query("select sum(units)::text units from app.lesson_reservations where lesson_id=$1 and state='reserved'",[lesson.id])).rows[0].units,'1.00');
      const row={teacherId:fixture.teachers[1],roomId:fixture.rooms[1],branchId:fixture.branch,weekday:1,beginTime:'16:00',durationMinutes:60,financialDecision};
      const plan=await request('POST','/crm/schedule-plans',{kind:'group',title:'AUDIT-PARTIAL-GROUP',groupId:group.id,activeFrom:'2027-01-25',activeUntil:'2027-02-08',participants:funding.map(item=>({studentId:item.student_id,subscriptionId:item.id})),rows:[row]},201);
      const saved=(await pool.query('select planned_financial_decision decision from app.schedule_series where id=$1',[plan.seriesIds[0]])).rows[0].decision;
      assert.equal(saved.teacherCompensationRuleKey,'standard');assert.equal(saved.teacherCreditedDurationMinutes,30);
      const update={expectedVersion:plan.version,effectiveFrom:'2027-02-01',activeUntil:'2027-02-08',rows:[{...row,seriesId:plan.seriesIds[0],durationMinutes:45,financialDecision:{...financialDecision,settlementTypeKey:'partially_paid_lesson',teacherCreditedDurationMinutes:20}}]};
      const preview=await request('POST','/crm/schedule-plans/'+plan.id+'/constraints/preview',update,201);assert(preview.valid);
      const updated=await request('PATCH','/crm/schedule-plans/'+plan.id,update);
      const changed=(await pool.query('select planned_financial_decision decision from app.schedule_series where id=$1',[updated.seriesIds[0]])).rows[0].decision;
      assert.equal(changed.teacherCompensationRuleKey,'standard');assert.equal(changed.teacherCreditedDurationMinutes,20);
    });
    const db={students,groupId:group.id};for(const table of ['schedule_plans','schedule_series','schedule_plan_participants','lessons','lesson_snapshot_participants','lesson_reservations'])db[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);
    fs.writeFileSync(path.join(output,'group-plan-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-lesson-guard')){
    const lesson=(await pool.query("select id from app.lessons where series_id is null and status='scheduled' order by created_at limit 1")).rows[0];assert(lesson);
    const snapshot=async()=>{const db={};for(const table of ['lessons','payments','client_payment_records','account_adjustments','lesson_reservations'])db[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t order by to_jsonb(t)::text')).rows.map(r=>r.row);return db;};
    const before=await snapshot();
    await check('Actual lesson dirty and in-flight close protection',()=>runDeviceTest('lesson_guard_live_test.dart','lesson-guard-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,lessonId:lesson.id})
    }));
    fs.writeFileSync(path.join(output,'lesson-guard-db.json'),JSON.stringify({lessonId:lesson.id,before,after:await snapshot()},null,2));
  }
  if(process.argv.includes('--audit-attachment-runtime')){
    const lesson=(await pool.query("select l.id from app.lessons l where l.teacher_id=$1 and l.student_id=$2 and l.deleted_at is null order by l.scheduled_at limit 1",[fixture.teachers[0],fixture.students[0]])).rows[0];assert(lesson);
    const homework=await request('POST','/crm/homeworks',{studentId:fixture.students[0],lessonId:lesson.id,title:'AUDIT-SUBMITTED-ANSWER',description:'Решение ученика с изображением и текстом'},201);
    const member=(await pool.query('select p.user_id from app.teachers t join app.profiles p on p.id=t.profile_id where t.id=$1',[fixture.teachers[0]])).rows[0];
    await check('Actual homework answer surfaces photo preview and messenger download',()=>runDeviceTest('attachment_runtime_live_test.dart','attachment-runtime-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,studentId:fixture.students[0],homeworkId:homework.id,memberUserId:member.user_id,imagePath:path.join(root,'assets/icon.png')})
    }));
    const db={homeworkId:homework.id};for(const table of ['lesson_homeworks','homework_attachments','file_objects'])db[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);
    fs.writeFileSync(path.join(output,'attachment-runtime-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-client-link-invite')){
    await check('Actual existing student linkage and invitation action',()=>runDeviceTest('client_link_invite_live_test.dart','client-link-invite-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const db={students:(await pool.query("select s.id,s.lead_id,s.version,s.contact_email,p.first_name from app.students s join app.profiles p on p.id=s.profile_id where p.first_name like 'AUDIT-LINK-STUDENT-%' order by p.first_name")).rows,links:(await pool.query("select x.user_id,x.entity_id,x.link_source,x.confirmed_at from app.user_crm_links x join app.students s on s.id=x.entity_id join app.profiles p on p.id=s.profile_id where x.entity_type='student' and x.deleted_at is null and p.first_name like 'AUDIT-LINK-STUDENT-%' order by p.first_name")).rows,emailOutbox:(await pool.query("select id,template,status,recipient_student_id from app.email_outbox where template='student_invite' order by created_at")).rows,smtp:smtp.messages.map(m=>({recipient:m.recipient,receivedAt:m.receivedAt,byteLength:Buffer.byteLength(m.body)}))};
    fs.writeFileSync(path.join(output,'client-link-invite-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-schedule-context')){
    await pool.query("update app.branch_hours set open_local='00:00',close_local='23:59' where branch_id=$1",[fixture.branch]);
    await pool.query("update app.teacher_availability_rules set local_start='00:00',local_end='23:59' where teacher_id=any($1::uuid[])",[fixture.teachers]);
    const second=(await pool.query("insert into app.branches(name,timezone_name,utc_offset_minutes) values('AUDIT-VLADIVOSTOK','Asia/Vladivostok',600) returning id")).rows[0].id;
    await pool.query("insert into app.branch_hours(branch_id,weekday,open_local,close_local) select $1,n,'00:00','23:59' from generate_series(1,7)n",[second]);
    await pool.query("insert into app.teacher_branches(teacher_id,branch_id,active_from,active_until) values($1,$2,'2020-01-01','2100-12-31')",[fixture.teachers[1],second]);
    await pool.query('insert into app.staff_branch_assignments(staff_member_id,branch_id) select sm.id,$1 from app.staff_members sm join app.profiles p on p.id=sm.profile_id join app.users u on u.id=p.user_id where u.email=any($2::text[])',[second,fixture.clientAuditAccounts.map(a=>a.email)]);
    const room=(await pool.query("insert into app.rooms(branch_id,name) values($1,'AUDIT-EAST-ROOM') returning id",[second])).rows[0].id;
    const created=[];
    for(let i=0;i<2;i++)created.push(await request('POST','/crm/lessons',{clientRef:{type:'student',id:fixture.students[i]},teacherId:fixture.teachers[i],roomId:i?room:fixture.rooms[0],branchId:i?second:fixture.branch,scheduledAt:'2027-01-04T21:15:00Z',durationMinutes:30,isTrial:false,completionType:'standard.success',clientChargeType:'personal_account',clientChargeValue:1000,teacherCompensationType:'hourly',teacherCompensationValue:700,financialDecision:{settlementTypeKey:'lesson',teacherCompensationRuleKey:'standard',clientDecisions:[{clientId:fixture.students[i],payerStudentId:fixture.students[i],chargeType:'personal_account',basePriceMinor:'100000'}]}},201));
    async function snapshot(){return {lessons:(await pool.query('select to_jsonb(t) row from app.lessons t where id=any($1::uuid[]) order by id',[created.map(x=>x.id)])).rows.map(r=>r.row),plans:(await pool.query('select to_jsonb(t) row from app.lesson_settlement_plans t where lesson_id=any($1::uuid[]) order by lesson_id',[created.map(x=>x.id)])).rows.map(r=>r.row)};}
    const before=await snapshot();
    await check('Actual cross midnight timezone branches and linked schedule cards',()=>runDeviceTest('schedule_context_live_test.dart','schedule-context-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,secondBranchId:second,lessonId:created[0].id,otherLessonId:created[1].id,studentId:fixture.students[0],teacherId:fixture.teachers[0],roomId:fixture.rooms[0]})
    }));
    fs.writeFileSync(path.join(output,'schedule-context-db.json'),JSON.stringify({before,after:await snapshot()},null,2));
  }
  if (process.argv.includes('--audit-customer-revisions') || integratedCandidateMode) {
    const branchHours = (await pool.query(
      'select weekday,open_local::text,close_local::text from app.branch_hours where branch_id=$1 order by weekday',
      [fixture.branch],
    )).rows;
    const teacherHours = (await pool.query(
      `select weekday,local_start::text,local_end::text from app.teacher_availability_rules
       where teacher_id=$1 and available=true order by weekday`,
      [fixture.teachers[0]],
    )).rows;
    assert.equal(branchHours.length, 7);
    assert.equal(teacherHours.length, 7);
    assert(branchHours.every(row => row.open_local === '08:00:00' && row.close_local === '22:00:00'));
    assert(teacherHours.every(row => row.local_start === '08:00:00' && row.local_end === '22:00:00'));
    fs.writeFileSync(path.join(output, 'trial-slot-preconditions.json'), JSON.stringify({
      timezone: 'Europe/Moscow', branchHours, teacherHours,
      createLocal: 'tomorrow 10:00/60m', editLocal: 'day after tomorrow 11:00/60m',
    }, null, 2));
    for (let index = 2; index < 6; index++) {
      fixture.rooms.push((await pool.query(
        'insert into app.rooms(branch_id,name) values($1,$2) returning id',
        [fixture.branch, `Room${index} HTTP test`],
      )).rows[0].id);
    }
    const lesson = await request('POST', '/crm/lessons', {
      clientRef: { type: 'student', id: fixture.students[0] },
      teacherId: fixture.teachers[0], roomId: fixture.rooms[0], branchId: fixture.branch,
      scheduledAt: '2027-01-12T08:15:00Z', durationMinutes: 45,
      completionType: 'standard.success', clientChargeType: 'none', clientChargeValue: 0,
      teacherCompensationType: 'none', teacherCompensationValue: 0,
      financialDecision: { settlementTypeKey: 'trial_lesson',
        teacherCompensationRuleKey: 'trial_lesson',
        clientDecisions: [{ clientId: fixture.students[0], chargeType: 'none' }] },
    }, 201);
    await check(process.env.HTTP_JOURNEY_ANDROID_MAIN === '1'
      ? 'Android ordinary entrypoint: UI login, navigation, mobile move and reopen'
      : 'Trial defaults, administrator pay override, six-room day move and filters', () =>
      runDeviceTest('customer_revisions_live_test.dart', 'customer-revisions-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          accounts: fixture.clientAuditAccounts, branchId: fixture.branch,
          lessonId: lesson.id, studentId: fixture.students[0], rooms: fixture.rooms,
          teacherId: fixture.teachers[0], roomId: fixture.rooms[0],
          foreignBranchId: fixture.foreignBranch, integratedLeadId }),
      }));
    if (!process.env.HTTP_JOURNEY_ANDROID_SERIAL) {
    const trialRecords = Object.fromEntries((integratedCandidateMode ? ['manager', 'director'] : ['admin', 'manager', 'director']).map(role => {
      const audit = JSON.parse(fs.readFileSync(path.join(output, `lead-trial-${role}.json`), 'utf8'));
      const created = audit.facts.find(fact => fact.step === 'CREATE');
      const cancelled = audit.facts.find(fact => fact.step === 'CANCEL');
      assert(created?.leadId && cancelled?.calendarLesson?.status === 'cancelled');
      return [role, { leadId: created.leadId, lessonId: cancelled.calendarLesson.id }];
    }));
    await check('Trial cancellation persists after a fresh Windows client process', () =>
      runDeviceTest('customer_revisions_live_test.dart', 'trial-restart-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          accounts: fixture.clientAuditAccounts, trialRestart: true, trialRecords }),
      }));
    await check('Cancelled trials have one zero-value client and teacher fact each', async () => {
      const lessonIds = Object.values(trialRecords).map(record => record.lessonId);
      const clients = (await pool.query(`select lesson_id,charge_type,amount_minor::text,units::text
        from app.lesson_client_charge_facts where lesson_id=any($1::uuid[])`, [lessonIds])).rows;
      const teachers = (await pool.query(`select lesson_id,compensation_type,amount_minor::text
        from app.lesson_teacher_compensation_facts where lesson_id=any($1::uuid[])`, [lessonIds])).rows;
      assert.equal(clients.length, lessonIds.length);
      assert.equal(teachers.length, lessonIds.length);
      assert.deepEqual(clients.map(row => row.lesson_id).sort(), [...lessonIds].sort());
      assert.deepEqual(teachers.map(row => row.lesson_id).sort(), [...lessonIds].sort());
      assert(clients.every(row => row.charge_type === 'none' && row.amount_minor === '0' && Number(row.units) === 0));
      assert(teachers.every(row => row.compensation_type === 'none' && row.amount_minor === '0'));
      const facts = { clientFacts: clients.length, teacherFacts: teachers.length,
        clientAmountMinor: '0', clientUnits: '0', teacherAmountMinor: '0' };
      fs.writeFileSync(path.join(output, 'trial-financial-facts.json'), JSON.stringify(facts, null, 2));
      return facts;
    });
    if (process.env.HTTP_JOURNEY_ROLLBACK_IMAGE) {
      assert(process.env.HTTP_JOURNEY_IMAGE, 'Recovery switch requires an image-backed candidate');
      // Exercise the administrator workflow, not the operator's explicit-rate override.
      const recoveryAdmin = fixture.clientAuditAccounts.find(account => account.role === 'admin');
      token = (await request('POST', '/auth/login', { email: recoveryAdmin.email,
        password: fixture.password }, 200, { auth: false })).session.accessToken;
      await require('./customer-recovery-verification.cjs').verifyRecovery({
        pool, fixture, request, check,
        completeCandidate: async () => {
          await stopApi();
          await startApi(fixture, true);
          const account = fixture.clientAuditAccounts.find(account => account.role === 'admin');
          token = (await request('POST', '/auth/login', { email: account.email,
            password: fixture.password }, 200, { auth: false })).session.accessToken;
        },
        exportReport: async (query) => {
          const response = await fetch(`${baseUrl}/crm/reports/teacher-stats/export?${query}`, {
            headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(20000),
          });
          assert.equal(response.status, 200, 'Filtered export must be accepted');
          const workbook = new (dependency('exceljs').Workbook)();
          await workbook.xlsx.load(Buffer.from(await response.arrayBuffer()));
          return workbook.worksheets.map(sheet => ({ name: sheet.name, rows: sheet.getSheetValues() }));
        },
        restart: async () => {
          await stopApi();
          process.env.HTTP_JOURNEY_IMAGE = process.env.HTTP_JOURNEY_ROLLBACK_IMAGE;
          await startApi(fixture);
          const account = fixture.clientAuditAccounts.find(account => account.role === 'admin');
          token = (await request('POST', '/auth/login', { email: account.email,
            password: fixture.password }, 200, { auth: false })).session.accessToken;
        },
      });
    }
    }
  }
  if(process.argv.includes('--audit-lesson-funding')){
    const pkg=await request('POST','/crm/subscription-packages',{name:'AUDIT-LESSON-FUNDING',branchId:fixture.branch,unitCount:12,basePriceMinor:'1200000',currencyCode:'RUB',validityDays:365},201);
    const purchaseInput={packageId:pkg.id,payerStudentId:fixture.students[1],fundingMode:'installment',purchaseReason:'Синтетическая проверка источников оплаты',installments:[30,60].map(days=>({dueAt:new Date(Date.now()+days*86400000).toISOString(),amountMinor:'600000'}))};
    const purchasePreview=await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase/preview`,purchaseInput,201);assert(purchasePreview.canCommit);
    const purchase=await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase`,{...purchaseInput,previewToken:purchasePreview.previewToken,confirm:true},201);
    const family=await request('POST','/crm/families',{name:'AUDIT-LESSON-FAMILY',branchId:fixture.branch},201);
    await request('POST','/crm/families/'+family.id+'/members',{entityType:'student',entityId:fixture.students[0],role:'child'},201);
    await request('POST','/crm/families/'+family.id+'/members',{entityType:'student',entityId:fixture.students[1],role:'payer'},201);
    const lessonIds={};
    for(const [i,role] of ['admin','manager','director'].entries()){const lesson=await request('POST','/crm/lessons',{clientRef:{type:'student',id:fixture.students[0]},teacherId:fixture.teachers[0],roomId:fixture.rooms[0],branchId:fixture.branch,scheduledAt:'2027-01-'+String(12+i).padStart(2,'0')+'T10:00:00Z',durationMinutes:60,isTrial:false,completionType:'standard.success',clientChargeType:'personal_account',clientChargeValue:1000,teacherCompensationType:'hourly',teacherCompensationValue:700,financialDecision:{settlementTypeKey:'lesson',teacherCompensationRuleKey:'standard',clientDecisions:[{clientId:fixture.students[0],payerStudentId:fixture.students[0],chargeType:'personal_account',basePriceMinor:'100000'}]}},201);lessonIds[role]=lesson.id;}
    async function snapshot(){const data={};for(const table of ['lessons','lesson_reservations','lesson_settlement_plans','lesson_settlement_plan_revisions','payments','client_payment_records','account_adjustments'])data[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t order by 1::text')).rows.map(r=>r.row);return data;}
    const before=await snapshot();
    await check('Actual lesson payer sources calculation history and conflict repair',()=>runDeviceTest('lesson_funding_live_test.dart','lesson-funding-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,lessonIds,studentId:fixture.students[0],payerId:fixture.students[1],subscriptionId:purchase.subscription.id,roomId:fixture.rooms[0]})
    }));
    fs.writeFileSync(path.join(output,'lesson-funding-db.json'),JSON.stringify({lessonIds,before,after:await snapshot()},null,2));
  }
  if(process.argv.includes('--audit-report-async')){
    const status=(await pool.query('select id from app.lead_statuses order by sort_order limit 1')).rows[0].id;
    await pool.query("insert into app.leads(first_name,last_name,branch_id,status_id) select 'AUDIT-LARGE-'||lpad(n::text,5,'0'),'Тест',$1,$2 from generate_series(1,10001)n",[fixture.branch,status]);
    await check('Actual asynchronous large report queue download and entity navigation',()=>runDeviceTest('report_async_live_test.dart','report-async-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const jobs=(await pool.query('select id,actor_user_id,report_key,format,row_count,status,filename,mime_type,content,error_code from app.report_export_jobs order by created_at')).rows;
    for(const j of jobs){if(j.content){j.byteLength=j.content.length;j.sha256=require('node:crypto').createHash('sha256').update(j.content).digest('hex');if(j.format==='xlsx'){const ExcelJS=require('../server/node_modules/exceljs');const workbook=new ExcelJS.Workbook();await workbook.xlsx.load(j.content);j.sheetRows=workbook.worksheets[0].rowCount;const text=JSON.stringify(workbook.worksheets[0].getSheetValues());j.firstMarker=text.includes('AUDIT-LARGE-00001');j.lastMarker=text.includes('AUDIT-LARGE-10001');}else{const text=j.content.toString('utf8');j.markerCount=(text.match(/AUDIT-LARGE-/g)||[]).length;j.firstMarker=text.includes('AUDIT-LARGE-00001');j.lastMarker=text.includes('AUDIT-LARGE-10001');}}delete j.content;}
    fs.writeFileSync(path.join(output,'report-async-db.json'),JSON.stringify({jobs,leadCount:Number((await pool.query("select count(*) from app.leads where first_name like 'AUDIT-LARGE-%'")).rows[0].count)},null,2));
  }
  if(process.argv.includes('--audit-subscription-coverage')){
    await stopApi();await startApi(fixture,true);token=(await request('POST','/auth/login',{email:fixture.email,password:fixture.password},200,{auth:false})).session.accessToken;
    const pkg=await request('POST','/crm/subscription-packages',{name:'AUDIT-COVERAGE-8',branchId:fixture.branch,unitCount:8,basePriceMinor:'800000',currencyCode:'RUB',validityDays:365},201);
    const replacement=await request('POST','/crm/subscription-packages',{name:'AUDIT-COVERAGE-2',branchId:fixture.branch,unitCount:2,basePriceMinor:'200000',currencyCode:'RUB',validityDays:365},201);
    const cases={};
    for(const [i,role] of ['admin','manager','director'].entries()){
      const u=(await pool.query("insert into app.users(email,role,is_app_account) values($1,'client',false) returning id",['coverage-'+role+'@example.test'])).rows[0].id;
      const p=(await pool.query("insert into app.profiles(user_id,first_name,last_name) values($1,'AUDIT-COVERAGE',$2) returning id",[u,role])).rows[0].id;
      const sid=(await pool.query('insert into app.students(profile_id,branch_id) values($1,$2) returning id',[p,fixture.branch])).rows[0].id;
      const input={packageId:pkg.id,payerStudentId:sid,fundingMode:'personal_account',paymentAmountMinor:'800000',paymentMethod:'cash',startsAt:'2026-08-01',expiresAt:'2027-08-01',purchaseReason:'Синтетическая проверка резервов и использования'};
      const preview=await request('POST','/crm/students/'+sid+'/subscriptions/purchase/preview',input,201);assert(preview.canCommit);
      const purchase=await request('POST','/crm/students/'+sid+'/subscriptions/purchase',{...input,previewToken:preview.previewToken,confirm:true},201),sub=purchase.subscription.id;
      const created=[];
      for(let j=0;j<4;j++){const when=j===0?'2026-08-'+(20+i)+'T10:00:00Z':'2027-02-'+String(1+i*4+j).padStart(2,'0')+'T10:00:00Z';created.push(await request('POST','/crm/lessons',{clientRef:{type:'student',id:sid},teacherId:fixture.teachers[0],roomId:fixture.rooms[0],branchId:fixture.branch,scheduledAt:when,durationMinutes:60,isTrial:false,completionType:'standard.success',clientChargeType:'subscription',clientChargeValue:1,subscriptionId:sub,teacherCompensationType:'hourly',teacherCompensationValue:700,financialDecision:{settlementTypeKey:'lesson',teacherCompensationRuleKey:'standard',clientDecisions:[{clientId:sid,payerStudentId:sid,chargeType:'subscription',subscriptionId:sub}]}},201));}
      cases[role]={studentId:sid,subscriptionId:sub,usedLessonId:created[0].id,lessonIds:created.slice(1).map(l=>l.id)};
    }
    const usedIds=Object.values(cases).map(c=>c.usedLessonId);let complete=false;
    for(let i=0;i<45;i++){complete=Number((await pool.query("select count(*) from app.lessons where id=any($1::uuid[]) and lifecycle_state='successfully_completed'",[usedIds])).rows[0].count)===3;if(complete)break;await new Promise(resolve=>setTimeout(resolve,500));}assert(complete,'Actual completion worker must consume each past lesson');
    const ids=Object.values(cases).map(c=>c.studentId),lessonIds=Object.values(cases).flatMap(c=>[c.usedLessonId,...c.lessonIds]);
    async function snapshot(){const data={};for(const table of ['subscriptions','payments','account_adjustments','client_payment_records','subscription_obligation_facts','subscription_lifecycle_events','lesson_client_charge_facts','lesson_teacher_compensation_facts','lesson_reservations','lesson_settlement_plans','lessons'])data[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);return data;}
    const before=await snapshot();
    await check('Actual used reserved replacement cancellation and retained lessons',()=>runDeviceTest('subscription_coverage_live_test.dart','subscription-coverage-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,cases,replacementPackageId:replacement.id})
    }));
    fs.writeFileSync(path.join(output,'subscription-coverage-db.json'),JSON.stringify({cases,before,after:await snapshot()},null,2));
  }
  if(process.argv.includes('--audit-organization-edges')){
    const staffEmail=fixture.clientAuditAccounts.find(a=>a.role==='admin').email,staff=(await pool.query('select sm.id,p.user_id,p.id profile_id from app.staff_members sm join app.profiles p on p.id=sm.profile_id join app.users u on u.id=p.user_id where u.email=$1',[staffEmail])).rows[0];
    await pool.query("update app.profiles set first_name='AUDIT-BLOCKED',last_name='STAFF',phone=null where id=$1",[staff.profile_id]);
    const status=(await pool.query('select id from app.lead_statuses order by sort_order limit 1')).rows[0].id;
    await pool.query("insert into app.leads(first_name,last_name,branch_id,status_id,assigned_to) values('AUDIT-BLOCKED','LEAD',$1,$2,$3)",[fixture.branch,status,staff.user_id]);
    await request('POST','/crm/shared-tasks',{title:'AUDIT-BLOCKED-TASK',allDay:true,startAt:new Date(Date.now()+86400000).toISOString(),audiences:[{type:'user',targetId:staff.user_id}]},201);
    await request('POST','/crm/groups',{name:'AUDIT-BLOCKED-GROUP',teacherId:fixture.teachers[0],branchId:fixture.branch,roomId:fixture.rooms[0],pricePerLesson:1000},201);
    const second=(await pool.query("insert into app.branches(name,timezone_name,utc_offset_minutes) values('AUDIT-HOURS-EAST','Asia/Vladivostok',600) returning id")).rows[0].id;
    await pool.query("insert into app.branch_hours(branch_id,weekday,open_local,close_local) select $1,n,'08:00','22:00' from generate_series(1,7)n",[second]);
    await pool.query("insert into app.teacher_branches(teacher_id,branch_id,active_from,active_until) values($1,$2,'2020-01-01','2100-12-31')",[fixture.teachers[0],second]);
    await pool.query('insert into app.staff_branch_assignments(staff_member_id,branch_id) select sm.id,$1 from app.staff_members sm join app.profiles p on p.id=sm.profile_id join app.users u on u.id=p.user_id where u.email=any($2::text[])',[second,fixture.clientAuditAccounts.map(a=>a.email)]);
    const room=(await pool.query("insert into app.rooms(branch_id,name) values($1,'AUDIT-HOURS-EAST-ROOM') returning id",[second])).rows[0].id;
    const lesson=await request('POST','/crm/lessons',{clientRef:{type:'student',id:fixture.students[0]},teacherId:fixture.teachers[0],roomId:fixture.rooms[0],branchId:fixture.branch,scheduledAt:'2027-01-18T10:00:00Z',durationMinutes:60,isTrial:false,completionType:'standard.success',clientChargeType:'personal_account',clientChargeValue:1000,teacherCompensationType:'hourly',teacherCompensationValue:700,financialDecision:{settlementTypeKey:'lesson',teacherCompensationRuleKey:'standard',clientDecisions:[{clientId:fixture.students[0],payerStudentId:fixture.students[0],chargeType:'personal_account',basePriceMinor:'100000'}]}},201);
    async function snapshot(){const data={};for(const table of ['teachers','staff_members','staff_branch_assignments','teacher_branches','lessons','groups','shared_tasks','task_audiences','leads','person_lifecycle_history'])data[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);data.hours=(await pool.query('select weekday,open_local,close_local from app.branch_hours where branch_id=$1 order by weekday',[second])).rows;return data;}
    const before=await snapshot();
    await check('Actual future person blockers linked accounts cross branch conflicts and hours',()=>runDeviceTest('organization_edges_live_test.dart','organization-edges-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,secondBranchId:second,secondRoomId:room,lessonId:lesson.id,studentId:fixture.students[1],teacherId:fixture.teachers[0],teacherName:'Teacher0 HTTP test',staffId:staff.id,staffName:'STAFF AUDIT-BLOCKED',staffEmail})
    }));
    fs.writeFileSync(path.join(output,'organization-edges-db.json'),JSON.stringify({before,after:await snapshot()},null,2));
  }
  if(process.argv.includes('--audit-voice-runtime')){
    const members=(await pool.query('select id from app.users where email=any($1::text[])',[fixture.clientAuditAccounts.map(a=>a.email)])).rows;
    const chat=await request('POST','/messenger/groups',{name:'AUDIT-VOICE-CHAT',memberUserIds:members.map(m=>m.id)},201);
    await check('Five role actual voice permission cancel send storage and native playback',()=>runDeviceTest('voice_runtime_live_test.dart','voice-runtime-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,chatId:chat.id,audioPath:path.join(root,'outputs/crm-function-map-2026-09-10/audit-silence.m4a'),shortAudioPath:path.join(root,'outputs/crm-function-map-2026-09-10/audit-short-silence.m4a')})
    }));
    const messages=(await pool.query("select m.id,m.chat_id,u.role,m.message_type,m.attachment_file_id,m.voice_duration_ms,m.deleted_at from app.messages m join app.users u on u.id=m.sender_id where m.chat_id=$1 and m.message_type='voice' order by u.role",[chat.id])).rows;
    const files=(await pool.query("select id,sha256,size_bytes,mime_type,deleted_at from app.file_objects where purpose='chat_voice' order by id")).rows;
    fs.writeFileSync(path.join(output,'voice-runtime-db.json'),JSON.stringify({messages,files,fixtureSha256:require('crypto').createHash('sha256').update(fs.readFileSync(path.join(root,'outputs/crm-function-map-2026-09-10/audit-silence.m4a'))).digest('hex')},null,2));
  }
  if(process.argv.includes('--audit-board-workflows')){
    const initial=await request('GET','/crm/client-pipelines?clientType=lead');
    const stages=[{...initial.stages[0],allowedTransitions:['audit_board']},{key:'audit_board',label:'Связались',style:'green',active:true,terminal:false,requiresReason:false,allowedTransitions:['new']}];
    await request('POST','/crm/client-pipelines/publish',{clientType:'lead',expectedVersion:initial.schoolVersion,stages,reason:'Синтетическая воронка аудита доски'},201);

    await check('Actual client board filters date range and drag status',()=>runDeviceTest('board_workflows_live_test.dart','board-workflows-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const db={leads:(await pool.query("select id,first_name,assigned_to,status_id,version,branch_id from app.leads where first_name like 'AUDIT-BOARD-%' order by first_name")).rows,students:(await pool.query("select s.id,p.first_name,s.status,s.version from app.students s join app.profiles p on p.id=s.profile_id where p.first_name like 'AUDIT-BOARD-STUDENT-%' order by p.first_name")).rows};
    fs.writeFileSync(path.join(output,'board-workflows-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-boards')){
    const status=(await pool.query('select id,stage_key from app.lead_statuses order by sort_order limit 1')).rows[0];assert(status);
    for(let i=1;i<=32;i++)await pool.query('insert into app.leads(first_name,branch_id,status_id) values($1,$2,$3)',['AUDIT-LEAD-'+String(i).padStart(3,'0'),fixture.branch,status.id]);
    const before=(await pool.query('select id,first_name,status_id,version,deleted_at from app.leads order by id')).rows;
    await check('Actual lead and student boards filters search pagination',()=>runDeviceTest('boards_live_test.dart','boards-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,leadStatus:status.id})
    }));
    const after=(await pool.query('select id,first_name,status_id,version,deleted_at from app.leads order by id')).rows;
    fs.writeFileSync(path.join(output,'boards-db.json'),JSON.stringify({before,after},null,2));
  }
  if(process.argv.includes('--audit-update-center')){
    await check('Actual updates center local network and bundled history',()=>runDeviceTest('update_center_live_test.dart','update-center-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts})
    }));
    fs.writeFileSync(path.join(output,'update-center-db.json'),JSON.stringify({noBusinessCommands:true},null,2));
  }
  if(process.argv.includes('--audit-workspace-runtime')){
    for(const stage of ['first','second']){
      await check('Actual workspace '+stage+' process',()=>runDeviceTest('workspace_runtime_live_test.dart','workspace-'+stage+'-windows.log',{
        WORKSPACE_AUDIT_STAGE:stage,HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,students:fixture.students})
      }));
    }
    const students=(await pool.query('select s.id,p.first_name,s.version from app.students s join app.profiles p on p.id=s.profile_id where s.id=any($1::uuid[]) order by s.id',[fixture.students])).rows;
    fs.writeFileSync(path.join(output,'workspace-db.json'),JSON.stringify({students},null,2));
  }
  if(process.argv.includes('--audit-schedule-views')){
    const pickerPackage = await request('POST','/crm/subscription-packages',{
      name:'AUDIT-CLIENT-PICKER-HOURS',branchId:fixture.branch,unitCount:1.5,
      basePriceMinor:'150000',currencyCode:'RUB',validityDays:365,
    },201);
    const pickerInput = {packageId:pickerPackage.id,payerStudentId:fixture.students[1],
      fundingMode:'installment',purchaseReason:'Синтетическая проверка остатка астрономических часов',
      installments:[30,60].map(days=>({dueAt:new Date(Date.now()+days*86400000).toISOString(),amountMinor:'75000'}))};
    const pickerPreview = await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase/preview`,pickerInput,201);
    assert(pickerPreview.canCommit);
    await request('POST',`/crm/students/${fixture.students[1]}/subscriptions/purchase`,{...pickerInput,previewToken:pickerPreview.previewToken,confirm:true},201);
    const before=(await pool.query('select id,version,scheduled_at,teacher_id,room_id,status,deleted_at from app.lessons order by id')).rows;
    const lesson=before.find(l=>l.deleted_at===null&&l.status==='scheduled');assert(lesson);
    await check('Actual schedule navigation filters and cancellation',()=>runDeviceTest('schedule_views_live_test.dart','schedule-views-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,lesson,activeStudentId:fixture.students[1]})
    }));
    const after=(await pool.query('select id,version,scheduled_at,teacher_id,room_id,status,deleted_at from app.lessons order by id')).rows;
    fs.writeFileSync(path.join(output,'schedule-views-db.json'),JSON.stringify({before,after},null,2));
  }
  if(process.argv.includes('--audit-reports-deep')){
    await request('POST','/crm/students/'+fixture.students[0]+'/payment-records',{amountMinor:'500000',currencyCode:'RUB',status:'paid',reason:'AUDIT-REPORT-REVENUE',externalIdentifier:'AUDIT-REPORT-RECEIPT',method:'cash',branchId:fixture.branch,occurredAt:new Date().toISOString()},201,{key:randomUUID()});
    await request('POST','/crm/expenses',{amount:2000,category:'AUDIT-REPORT-EXPENSE',description:'Синтетический расход',branchId:fixture.branch,occurredAt:new Date().toISOString()},201,{key:randomUUID()});
    await check('Reports filters drilldowns and nonzero finance through actual widgets',()=>runDeviceTest('reports_deep_live_test.dart','reports-deep-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,students:fixture.students})
    }));
    const db={payments:(await pool.query('select student_id,branch_id,amount_minor from app.payments')).rows,expenses:(await pool.query('select id,branch_id,amount,category from app.expenses')).rows};
    fs.writeFileSync(path.join(output,'reports-deep-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-finance-advanced')){
    await check('Payment correction and account adjustment reversal through actual card',()=>runDeviceTest('finance_advanced_live_test.dart','finance-advanced-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const students=(await pool.query("select s.id,p.last_name from app.students s join app.profiles p on p.id=s.profile_id where p.last_name like 'FINANCE-ADVANCED-%'")).rows;
    const ids=students.map(s=>s.id),db={students};
    for(const table of ['client_payment_records','payments','account_adjustments']) db[table]=(await pool.query('select * from app.'+table+' where student_id=any($1::uuid[])',[ids])).rows;
    db.statusEvents=(await pool.query('select e.* from app.client_payment_status_events e join app.client_payment_records p on p.id=e.payment_record_id where p.student_id=any($1::uuid[])',[ids])).rows;
    db.audit=(await pool.query("select action,entity_type,entity_id,metadata from app.audit_events where action like '%payment%' or action like '%adjustment%' order by created_at")).rows;
    fs.writeFileSync(path.join(output,'finance-advanced-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-payroll')){
    await stopApi();await startApi(fixture,true);
    for(let n=0;n<50;n++){
      const pending=(await pool.query("select count(*)::int n from app.lessons where lifecycle_state='scheduled' and scheduled_at+make_interval(mins=>duration_minutes)<now()")).rows[0].n;
      if(!pending)break;await new Promise(resolve=>setTimeout(resolve,500));
    }
    async function snapshot(){return {
      lessons:(await pool.query('select id,teacher_id,teacher_rate,status,lifecycle_state from app.lessons order by id')).rows,
      facts:(await pool.query('select * from app.lesson_teacher_compensation_facts order by created_at')).rows,
      effective:(await pool.query('select * from app.lesson_teacher_compensation_facts_effective order by lesson_id')).rows
    };}
    const before=await snapshot();assert(before.effective.length>0);
    await check('Teacher payroll report XLSX and director rate correction through real UI',()=>runDeviceTest('payroll_live_test.dart','payroll-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    fs.writeFileSync(path.join(output,'payroll-db.json'),JSON.stringify({before,after:await snapshot()},null,2));
  }
  if(process.argv.includes('--audit-replacement')){
    await request('POST','/crm/subscription-packages',{name:'PURCHASE-PACKAGE',branchId:fixture.branch,unitCount:8,basePriceMinor:'800000',currencyCode:'RUB',validityDays:90},201);
    const target=await request('POST','/crm/subscription-packages',{name:'REPLACEMENT-PACKAGE',branchId:fixture.branch,unitCount:10,basePriceMinor:'1000000',currencyCode:'RUB',validityDays:90},201);
    await check('Subscription replacement through actual card',()=>runDeviceTest('subscription_replacement_live_test.dart','replacement-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch,replacementPackageId:target.id})
    }));
    const db={};for(const table of ['students','subscriptions','payments','client_payment_records','subscription_obligation_facts','subscription_lifecycle_events','subscription_installments'])db[table]=(await pool.query('select to_jsonb(t) row from app.'+table+' t')).rows.map(r=>r.row);
    fs.writeFileSync(path.join(output,'replacement-db.json'),JSON.stringify(db,null,2));
  }
  if(process.argv.includes('--audit-comment-rules')) await require('./comment-rules-verification.cjs').runCommentRulesAudit({pool,fixture,baseUrl,output,check});
  if(process.argv.includes('--audit-payroll-export')) await require('./payroll-export-verification.cjs').runPayrollExportAudit({fixture,baseUrl,output,check});
  if(process.argv.includes('--audit-task-delivery')) await require('./task-delivery-verification.cjs').runTaskDeliveryAudit({pool,fixture,baseUrl,output,check});
  if (process.argv.includes('--audit-responsible')) {
    await require('./responsible-audit-verification.cjs').runResponsibleAudit({pool,fixture,baseUrl,output,check});
  }
  if (process.argv.includes('--audit-tasks-advanced')) {
    await check('Task time intervals audience and reminders persist through actual editor',()=>runDeviceTest('tasks_advanced_live_test.dart','tasks-advanced-windows.log',{
      HTTP_JOURNEY_FIXTURE: JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const tasks=(await pool.query("select to_jsonb(t) row from app.shared_tasks t where title like 'AUDIT-ADVANCED-%' order by title")).rows;
    fs.writeFileSync(path.join(output,'tasks-advanced-db.json'),JSON.stringify({tasks},null,2));
  }
  if (process.argv.includes('--audit-messenger-lifecycle')) {
    await require('./messenger-lifecycle-verification.cjs').runMessengerLifecycleAudit({pool,fixture,baseUrl,output,check});
  }
  if (process.argv.includes('--audit-auth-delivery')) {
    await require('./auth-delivery-verification.cjs').runAuthDeliveryAudit({pool,fixture,baseUrl,output,check,smtp});
  }
  if (process.argv.includes('--audit-data-quality-boundaries')) {
    const { runDataQualityBoundaryAudit } = require('./data-quality-boundary-verification.cjs');
    await runDataQualityBoundaryAudit({pool,fixture,baseUrl,output,check});
  }
  if (process.argv.includes('--audit-report-exports')) {
    await check('Actual reporting exports download valid files through role-scoped API',()=>runDeviceTest('report_exports_live_test.dart','report-exports-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const jobs = (await pool.query('select actor_user_id,report_key,format,row_count,status,filename,mime_type,octet_length(content) bytes,completed_at from app.report_export_jobs order by created_at')).rows;
    fs.writeFileSync(path.join(output,'report-exports-db.json'),JSON.stringify({jobs},null,2));
  }
  if (process.argv.includes('--audit-configuration')) {
    await check('Configuration field draft publication archive and rollback persist revisions',()=>runDeviceTest('configuration_live_test.dart','configuration-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,branchId:fixture.branch})
    }));
    const revisions = (await pool.query('select version,reason,rollback_from_version,effective_snapshot,created_by from app.crm_configuration_revisions where branch_id is null order by version')).rows;
    const fields = (await pool.query('select to_jsonb(d) value from app.client_custom_field_definitions d order by id')).rows.map(r=>r.value);
    fs.writeFileSync(path.join(output,'configuration-db.json'),JSON.stringify({revisions,fields},null,2));
  }
  if (process.argv.includes('--audit-access-editor')) {
    const account = fixture.clientAuditAccounts.find(a => a.role === 'admin');
    const target = (await pool.query('select u.id,u.role,v.version access_version from app.users u join app.user_access_versions v on v.user_id=u.id where u.email=$1',[account.email])).rows[0];
    await check('Actual access editor persists capability denial and confirmed role changes',()=>runDeviceTest('access_editor_live_test.dart','access-editor-windows.log',{
      HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,accounts:fixture.clientAuditAccounts,accessTargetId:target.id})
    }));
    const user = (await pool.query('select u.id,u.role,v.version access_version from app.users u join app.user_access_versions v on v.user_id=u.id where u.id=$1',[target.id])).rows[0];
    const audit = (await pool.query("select action,entity_type,entity_id,metadata from app.audit_events where action like 'access.%' order by created_at")).rows;
    fs.writeFileSync(path.join(output,'access-editor-db.json'),JSON.stringify({before:target,after:user,audit},null,2));
  }
  if (process.argv.includes('--audit-client-payments')) {
    await check('Actual client card payment statuses and reversals persist in canonical finance', () =>
      runDeviceTest('client_payment_live_test.dart', 'client-payment-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, branchId: fixture.branch }),
      }));
    const students = (await pool.query("select s.id,p.last_name from app.students s join app.profiles p on p.id=s.profile_id where p.last_name like 'PAYMENT-%' order by s.id")).rows;
    const ids = students.map(s => s.id);
    const records = (await pool.query('select * from app.client_payment_records where student_id=any($1::uuid[]) order by id', [ids])).rows;
    const payments = (await pool.query('select * from app.payments where student_id=any($1::uuid[]) order by id', [ids])).rows;
    const audit = (await pool.query("select action,entity_type,entity_id,metadata from app.audit_events where action like '%payment%' order by created_at")).rows;
    fs.writeFileSync(path.join(output,'client-payment-db.json'),JSON.stringify({students,records,payments,audit},null,2));
  }
  if (process.argv.includes('--audit-lead-merge')) {
    const mergeCases = {};
    for (const [index, role] of ['manager', 'director'].entries()) {
      const pair = [randomUUID(), randomUUID()].sort(), phone = '+7999555000' + index;
      await pool.query("insert into app.leads(id,first_name,last_name,phone,phone_normalized,branch_id,custom_data) values ($1,$3,'Аудит',$4,$4,$5,'{\"first\":\"preserved\"}'),($2,$3,'Аудит',$4,$4,$5,'{\"second\":\"preserved\"}')", [pair[0], pair[1], 'MERGE-' + role, phone, fixture.branch]);
      const comment = await request('POST', '/crm/comments', { entityType: 'lead', entityId: pair[1], body: 'AUDIT-MERGE-COMMENT-' + role, kind: 'admin_comment' }, 201);
      mergeCases[role] = { winnerId: pair[0], loserId: pair[1], commentId: comment.id };
    }
    await check('Lead merge and undo through actual duplicate cards preserve linked comments and history', () =>
      runDeviceTest('lead_merge_live_test.dart', 'lead-merge-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, mergeCases }),
      }));
    const leads = (await pool.query("select id,first_name,deleted_at,version,custom_data from app.leads where first_name like 'MERGE-%' order by id")).rows;
    const comments = (await pool.query('select to_jsonb(c) value from app.entity_comments c where id=any($1::uuid[]) order by id', [Object.values(mergeCases).map(c => c.commentId)])).rows.map(r => r.value);
    const history = (await pool.query('select * from app.merge_log order by merged_at,id')).rows;
    fs.writeFileSync(path.join(output, 'lead-merge-db.json'), JSON.stringify({ mergeCases, leads, comments, history }, null, 2));
  }
  if (process.argv.includes('--audit-messenger-text')) {
    const members = (await pool.query('select id,role from app.users where email=any($1::text[]) order by role', [fixture.clientAuditAccounts.map(a => a.email)])).rows;
    const chat = await request('POST', '/messenger/groups', { name: 'AUDIT-TEXT-CHAT', memberUserIds: members.map(m => m.id) }, 201);
    await check('Five roles send edit reply and delete messages through the real messenger', () =>
      runDeviceTest('messenger_text_live_test.dart', 'messenger-text-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, chatId: chat.id }),
      }));
    const rows = (await pool.query(`select m.id,m.chat_id,u.role,m.content,m.reply_to_id,m.deleted_at,m.created_at,m.updated_at
      from app.messages m join app.users u on u.id=m.sender_id where m.chat_id=$1 order by u.role,m.created_at`, [chat.id])).rows;
    fs.writeFileSync(path.join(output, 'messenger-text-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-notification-preferences')) {
    const before = (await pool.query(`select role,event_type,enabled,channels from app.notification_preferences order by event_type,role`)).rows;
    await check('Notification routing toggles and channels persist through all configured event and recipient cells', () =>
      runDeviceTest('notification_preferences_live_test.dart', 'notification-preferences-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const after = (await pool.query(`select role,event_type,enabled,channels from app.notification_preferences order by event_type,role`)).rows;
    fs.writeFileSync(path.join(output, 'notification-preferences-db.json'), JSON.stringify({ before, after }, null, 2));
  }
  if (process.argv.includes('--audit-ui-usability')) {
    const director = (await pool.query('select id from app.users where email=$1', [fixture.employeeEmail])).rows[0].id;
    const chatId = (await pool.query("insert into app.chats(type,title,created_by) values('group','UI-HISTORY-CHAT',$1) returning id", [director])).rows[0].id;
    await pool.query("insert into app.chat_members(chat_id,user_id,role) values($1,$2,'admin')", [chatId,director]);
    const channelId = (await pool.query("insert into app.channels(title,created_by) values('UI-HISTORY-CHANNEL',$1) returning id", [director])).rows[0].id;
    // Identical timestamps exercise the ID tie-breaker; matches are outside the latest 100.
    await pool.query(`insert into app.messages(chat_id,sender_id,content,created_at)
      select $1,$2,case when n<=55 then 'Архив ёлка %_ '||n else 'UI-RECENT-'||n end,
        case when n<=55 then now()-interval '2 days' else now()-interval '1 day' end
      from generate_series(1,155) n`, [chatId,director]);
    await pool.query(`insert into app.channel_posts(channel_id,author_id,content,published_at)
      select $1,$2,case when n<=55 then 'Архив ёлка %_ '||n else 'UI-RECENT-'||n end,
        case when n<=55 then now()-interval '2 days' else now()-interval '1 day' end
      from generate_series(1,155) n`, [channelId,director]);
    await pool.query("insert into app.messages(chat_id,sender_id,content,created_at,deleted_at) values($1,$2,'Архив ёлка %_ удалено',now()-interval '2 days',now())", [chatId,director]);
    const conflictDate = '2027-01-04T10:00:00Z';
    await pool.query(`insert into app.lessons(student_id,branch_id,room_id,teacher_id,scheduled_at,notes)
      values($1,$2,$3,null,$5,'UI-CONFLICT'),($1,$2,$3,$4,$5::timestamptz+interval '3 hours','UI-NORMAL'),
      ($1,$2,$3,null,$5::timestamptz+interval '1 day','UI-NEXT-DAY-CONFLICT')`,
      [fixture.students[0],fixture.branch,fixture.rooms[0],fixture.teachers[0],conflictDate]);
    const clientAccount = fixture.clientAuditAccounts.find(a => a.role === 'client');
    await check('History search respects chat and channel access', async () => {
      const login = await fetch(baseUrl+'/auth/login', {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:clientAccount.email,password:fixture.password})});
      assert.equal(login.status,200);
      const session = (await login.json()).session;
      for (const endpoint of [`chats/${chatId}/messages`, `channels/${channelId}/posts`]) {
        const response = await fetch(`${baseUrl}/messenger/${endpoint}?q=ёлка`, {headers:{authorization:'Bearer '+session.accessToken}});
        assert([403,404].includes(response.status));
      }
    });
    await check('UI usability: forms, finance tables, conflicts and complete message history', () =>
      runDeviceTest('ui_usability_live_test.dart', 'ui-usability-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, branchId: fixture.branch, historyChatId: chatId, historyChannelId: channelId, conflictDate }),
      }));
  }
  if (process.argv.includes('--audit-teacher-forms')) {
    await check('Teacher identity and employment forms persist without creating login access', () =>
      runDeviceTest('teacher_forms_live_test.dart', 'teacher-forms-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, branchId: fixture.branch }),
      }));
    const rows = (await pool.query(`select to_jsonb(t) entity,p.first_name,p.last_name,u.is_app_account,
      (select jsonb_agg(to_jsonb(r) order by r.effective_from) from app.teacher_rates r where r.teacher_id=t.id) rates,
      (select jsonb_agg(to_jsonb(a)) from app.teacher_branches a where a.teacher_id=t.id) assignments
      from app.teachers t join app.profiles p on p.id=t.profile_id left join app.users u on u.id=p.user_id
      where p.first_name like 'TEACHER-%' order by p.first_name`)).rows;
    fs.writeFileSync(path.join(output, 'teacher-forms-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-person-lifecycle')) {
    const staffEmail = `offboard-${runId}@example.test`;
    const staff = await request('POST', '/crm/staff', { firstName: 'OFFBOARD-STAFF', lastName: 'Проверка',
      branchIds: [fixture.branch], email: staffEmail, password: fixture.password, accessRole: 'admin' }, 201);
    await check('Staff offboarding and restore affect actual account login and preserve history', () =>
      runDeviceTest('person_lifecycle_live_test.dart', 'person-lifecycle-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, staffId: staff.id, staffEmail }),
      }));
    const rows = (await pool.query(`select to_jsonb(s) entity,p.first_name,p.last_name,u.is_app_account,
      (select jsonb_agg(to_jsonb(a)) from app.staff_branch_assignments a where a.staff_member_id=s.id) assignments,
      (select jsonb_agg(jsonb_build_object('revoked',r.revoked_at is not null) order by r.created_at) from app.refresh_sessions r where r.user_id=u.id) sessions,
      (select jsonb_agg(to_jsonb(h) order by h.version) from app.person_lifecycle_history h where h.person_type='staff' and h.person_id=s.id) history
      from app.staff_members s join app.profiles p on p.id=s.profile_id join app.users u on u.id=p.user_id where s.id=$1`, [staff.id])).rows;
    fs.writeFileSync(path.join(output, 'person-lifecycle-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-teacher-offboard')) {
    const staffEmail = `offboard-${runId}@example.test`;
    const staff = await request('POST', '/crm/teachers', { firstName: 'OFFBOARD-TEACHER', lastName: 'Проверка',
      branchIds: [fixture.branch], email: staffEmail, password: fixture.password, accessRole: 'teacher' }, 201);
    await check('Staff offboarding and restore affect actual account login and preserve history', () =>
      runDeviceTest('teacher_offboard_live_test.dart', 'teacher-offboard-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, staffId: staff.id, staffEmail }),
      }));
    const rows = (await pool.query(`select to_jsonb(s) entity,p.first_name,p.last_name,u.is_app_account,
      (select jsonb_agg(to_jsonb(a)) from app.teacher_branches a where a.teacher_id=s.id) assignments,
      (select jsonb_agg(jsonb_build_object('revoked',r.revoked_at is not null) order by r.created_at) from app.refresh_sessions r where r.user_id=u.id) sessions,
      (select jsonb_agg(to_jsonb(h) order by h.version) from app.person_lifecycle_history h where h.person_type='teacher' and h.person_id=s.id) history
      from app.teachers s join app.profiles p on p.id=s.profile_id join app.users u on u.id=p.user_id where s.id=$1`, [staff.id])).rows;
    fs.writeFileSync(path.join(output, 'teacher-offboard-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-staff-forms')) {
    await check('Staff forms create and edit CRM records without implicitly granting app access', () =>
      runDeviceTest('staff_forms_live_test.dart', 'staff-forms-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts, branchId: fixture.branch }),
      }));
    const rows = (await pool.query(`select s.id,p.first_name,p.last_name,p.user_id,s.position,s.status,s.deleted_at,
      (select jsonb_agg(to_jsonb(a)) from app.staff_branch_assignments a where a.staff_member_id=s.id) assignments
      from app.staff_members s join app.profiles p on p.id=s.profile_id where p.first_name like 'STAFF-%' order by p.first_name`)).rows;
    fs.writeFileSync(path.join(output, 'staff-forms-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-group-lifecycle')) {
    const groups = {};
    for (const role of ['director', 'manager']) {
      const group = await request('POST', '/crm/groups', { name: `LIFECYCLE-GROUP-${role}`, branchId: fixture.branch,
        teacherId: fixture.teachers[0], roomId: fixture.rooms[0], pricePerLesson: 1500 }, 201);
      groups[role] = group.id;
      await request('POST', `/crm/groups/${group.id}/students`, { studentId: fixture.students[0] }, 201);
    }
    await check('Group archive and restore preserve membership and lifecycle history for director and manager', () =>
      runDeviceTest('group_lifecycle_live_test.dart', 'group-lifecycle-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          groups, studentId: fixture.students[0] }),
      }));
    const rows = (await pool.query(`select to_jsonb(g) as entity,
      (select jsonb_agg(to_jsonb(m)) from app.group_students m where m.group_id=g.id) members,
      (select jsonb_agg(to_jsonb(h) order by h.version) from app.group_lifecycle_history h where h.group_id=g.id) history
      from app.groups g where g.id=any($1::uuid[]) order by g.name`, [Object.values(groups)])).rows;
    fs.writeFileSync(path.join(output, 'group-lifecycle-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-groups')) {
    await check('Director and manager create groups and maintain student membership through real forms', () =>
      runDeviceTest('group_membership_live_test.dart', 'groups-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          branchId: fixture.branch, teacherId: fixture.teachers[0], roomId: fixture.rooms[0], studentId: fixture.students[0] }),
      }));
    const groups = (await pool.query(`select to_jsonb(g) value from app.groups g where name like 'GROUP-%' order by name`)).rows.map(r => r.value);
    const members = (await pool.query(`select to_jsonb(m) value from app.group_students m join app.groups g on g.id=m.group_id where g.name like 'GROUP-%' order by g.name`)).rows.map(r => r.value);
    fs.writeFileSync(path.join(output, 'groups-db.json'), JSON.stringify({ groups, members }, null, 2));
  }
  if (process.argv.includes('--audit-reference-catalog')) {
    await request('POST', '/crm/disciplines', { name: 'REFERENCE-READONLY-discipline' }, 201);
    await request('POST', '/crm/loss-reasons', { name: 'REFERENCE-READONLY-loss_reason', kind: 'lost' }, 201);
    await check('Discipline and loss-reason forms, search, rename, archive and restore', () =>
      runDeviceTest('reference_catalog_live_test.dart', 'reference-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const snapshots = {};
    for (const table of ['disciplines', 'lead_loss_reasons']) {
      snapshots[table] = (await pool.query(`select to_jsonb(r) value from app.${table} r where name like 'REFERENCE-%' order by name`)).rows.map(r => r.value);
    }
    fs.writeFileSync(path.join(output, 'reference-db.json'), JSON.stringify(snapshots, null, 2));
  }
  if (process.argv.includes('--audit-package-catalog')) {
    await check('Subscription package catalog saves, resolves conflicts, archives and restores through real forms', () =>
      runDeviceTest('package_catalog_live_test.dart', 'catalog-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
    const packages = (await pool.query(`select to_jsonb(p) value from app.subscription_packages p where name like 'CATALOG-%' order by name`)).rows.map(r => r.value);
    fs.writeFileSync(path.join(output, 'catalog-db.json'), JSON.stringify(packages, null, 2));
  }
  if (process.argv.includes('--audit-account-deletion')) {
    await check('Five roles request and withdraw account deletion through production routes', () =>
      runDeviceTest('account_deletion_live_test.dart', 'deletion-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const rows = (await pool.query(`select u.id user_id,u.role,u.deleted_at account_deleted_at,p.id profile_id,
      p.deleted_at profile_deleted_at,r.id,r.status,r.reason,r.resolved_at,r.resolved_by,r.resolution_note
      from app.users u join app.profiles p on p.user_id=u.id left join app.account_deletion_requests r on r.user_id=u.id
      where u.email=any($1::text[]) order by u.role`, [fixture.clientAuditAccounts.map(row => row.email)])).rows;
    const audit = (await pool.query(`select actor_user_id,action,entity_id,metadata from app.audit_events
      where entity_type='account_deletion_request' order by created_at`)).rows;
    fs.writeFileSync(path.join(output, 'deletion-db.json'), JSON.stringify({ rows, audit }, null, 2));
  }
  if (process.argv.includes('--audit-auth-email')) {
    await check('Production router changes login email, signs out and signs back in for five roles', () =>
      runDeviceTest('auth_email_routed_live_test.dart', 'auth-email-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const rows = (await pool.query(`select u.id,u.email,u.role,p.id profile_id,
      (select count(*)::int from app.refresh_sessions s where s.user_id=u.id and s.revoked_at is not null) revoked_sessions
      from app.users u join app.profiles p on p.user_id=u.id where u.email=any($1::text[]) order by u.role`,
      [fixture.clientAuditAccounts.flatMap(row => [row.email, `updated-${row.email}`])])).rows;
    fs.writeFileSync(path.join(output, 'auth-email-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-auth-methods')) {
    await check('Five roles validate password and email forms and save authentication methods', () =>
      runDeviceTest('auth_methods_live_test.dart', 'auth-methods-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const rows = (await pool.query(`select u.id,u.role,u.password_changed_at,p.email_otp_2fa_enabled,
      (select count(*)::int from app.refresh_sessions s where s.user_id=u.id and s.revoked_at is not null) revoked_sessions
      from app.users u join app.profiles p on p.user_id=u.id where u.email=any($1::text[]) order by u.role`,
      [fixture.clientAuditAccounts.map(row => row.email)])).rows;
    fs.writeFileSync(path.join(output, 'auth-methods-db.json'), JSON.stringify(rows, null, 2));
  }
  if (process.argv.includes('--audit-profile-date')) {
    await check('Date of birth survives two unrelated name edits in five role profiles', () =>
      runDeviceTest('profile_date_roundtrip_live_test.dart', 'profile-date-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const rows = (await pool.query(`select p.id,u.role,p.first_name,p.dob::text as dob from app.profiles p
      join app.users u on u.id=p.user_id where u.email=any($1::text[]) order by u.role`,
      [fixture.clientAuditAccounts.map(row => row.email)])).rows;
    fs.writeFileSync(path.join(output, 'profile-date-db.json'), JSON.stringify({ timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, rows }, null, 2));
  }
  if (process.argv.includes('--audit-profile')) {
    await check('Five roles save and clear their own profile fields through actual screen', () =>
      runDeviceTest('profile_fields_live_test.dart', 'profile-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts }),
      }));
    const profiles = (await pool.query(`select p.id,p.user_id,u.role,p.first_name,p.last_name,p.phone,p.dob
      from app.profiles p join app.users u on u.id=p.user_id where u.email=any($1::text[]) order by u.role`,
      [fixture.clientAuditAccounts.map(row => row.email)])).rows;
    fs.writeFileSync(path.join(output, 'profile-db.json'), JSON.stringify(profiles, null, 2));
  }
  if (process.argv.includes('--audit-teacher-card')) {
    const studentId = fixture.students[0];
    const lessons = (await pool.query('select id,teacher_id from app.lessons where student_id=$1 and deleted_at is null', [studentId])).rows;
    const own = lessons.filter(row => row.teacher_id === fixture.teachers[0]);
    const other = lessons.find(row => row.teacher_id !== fixture.teachers[0]);
    assert(own.length > 0 && other, 'Teacher card fixture needs lessons owned by both teachers');
    const ownHomework = await request('POST', '/crm/homeworks', { studentId, lessonId: own[0].id, title: 'TEACHER-OWN-HOMEWORK', description: 'Для своего преподавателя' }, 201);
    const otherHomework = await request('POST', '/crm/homeworks', { studentId, lessonId: other.id, title: 'TEACHER-OTHER-HOMEWORK', description: 'Для другого преподавателя' }, 201);
    const privateComment = await request('POST', '/crm/comments', { entityType: 'student', entityId: studentId, body: 'TEACHER-PRIVATE-COMMENT', kind: 'admin_comment' }, 201);
    const sharedComment = await request('POST', '/crm/comments', { entityType: 'student', entityId: studentId, body: 'TEACHER-SHARED-COMMENT', kind: 'admin_comment' }, 201);
    await request('PATCH', `/crm/comments/${sharedComment.id}/visibility`, { sharedWithTeacher: true, expectedVersion: Number(sharedComment.version), reasonCode: 'crm.comment.teacher-sharing' });
    fs.writeFileSync(path.join(output, 'teacher-card-fixture.json'), JSON.stringify({ studentId, ownLessons: own.map(row => row.id), otherLesson: other.id, ownHomework, otherHomework, privateComment, sharedComment }, null, 2));
    await check('Teacher educational card entered through actual student list', () =>
      runDeviceTest('teacher_card_live_test.dart', 'teacher-card-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password, accounts: fixture.clientAuditAccounts,
          studentId, ownLessons: own.map(row => row.id), ownHomework: ownHomework.id, otherHomework: otherHomework.id,
          privateComment: privateComment.id, sharedComment: sharedComment.id }),
      }));
  }
  if (process.argv.includes('--audit-statuses')) {
    const initial = await request('GET', '/crm/client-pipelines?clientType=lead');
    assert.equal(initial.stages.length, 1);
    assert.equal(initial.stages[0].key, 'new');
    const stages = [
      { ...initial.stages[0], allowedTransitions: ['audit_contact'] },
      { key: 'audit_contact', label: 'Связались', style: 'green', active: true, terminal: false, requiresReason: false, allowedTransitions: ['new', 'audit_closed'] },
      { key: 'audit_closed', label: 'Закрыт с причиной', style: 'gray', active: true, terminal: true, requiresReason: true, allowedTransitions: ['new'] },
    ];
    const input = { clientType: 'lead', expectedVersion: initial.schoolVersion, stages };
    const preview = await request('POST', '/crm/client-pipelines/preview', input, 201);
    assert.equal(preview.valid, true);
    const published = await request('POST', '/crm/client-pipelines/publish', { ...input, reason: 'Тестирование переходов в синтетической БД' }, 201);
    const contact = (await pool.query("select id from app.lead_statuses where stage_key='audit_contact'")).rows[0];
    assert(contact);
    fs.writeFileSync(path.join(output, 'statuses-config.json'), JSON.stringify({ initial, input, preview, published }, null, 2));
    await check('Lead status changes and required reason through actual card', () =>
      runDeviceTest('client_statuses_live_test.dart', 'statuses-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts, contactStatusId: contact.id }),
      }));
    const snapshots = {};
    for (const table of ['leads', 'lead_statuses', 'lead_status_history', 'student_funnel_revisions']) {
      snapshots[table] = (await pool.query(`select to_jsonb(row) value from app.${table} row`)).rows.map(row => row.value);
    }
    fs.writeFileSync(path.join(output, 'statuses-db.json'), JSON.stringify(snapshots, null, 2));
  }
  if (process.argv.includes('--audit-purchase') || process.argv.includes('--audit-subscription-cancel') || process.argv.includes('--audit-partial-purchase') || installmentCycleMode) {
    if (installmentCycleMode) {
      await stopApi();
      await startApi(fixture, true);
      token = (await request('POST', '/auth/login', {
        email: fixture.email, password: fixture.password,
      }, 200, { auth: false })).session.accessToken;
    }
    const purchasePackage = await request('POST', '/crm/subscription-packages', { name: 'PURCHASE-PACKAGE', branchId: fixture.branch,
      unitCount: installmentCycleMode ? 4 : 8,
      basePriceMinor: installmentCycleMode ? '1440000' : '800000',
      currencyCode: 'RUB', validityDays: 90 }, 201);
    await check('Subscription sale, cancellation, payment and lead conversion through actual form', () =>
      runDeviceTest(process.argv.includes('--audit-partial-purchase') || installmentCycleMode ? 'partial_purchase_live_test.dart' : 'client_purchase_live_test.dart', 'purchase-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch,
          roomId: fixture.rooms[installmentCycleMode ? 1 : 0],
          teacherId: fixture.teachers[installmentCycleMode ? 1 : 0],
          accounts: fixture.clientAuditAccounts, auditCancellation: process.argv.includes('--audit-subscription-cancel'),
          auditInstallmentCycle: installmentCycleMode, integratedLeadId,
          integratedTrialId: integratedCandidateMode
            ? JSON.parse(fs.readFileSync(path.join(output, 'lead-trial-admin.json'), 'utf8'))
              .facts.find(fact => fact.step === 'INTEGRATED-TRIAL')?.lessonId
            : undefined }),
      }));
    if (installmentCycleMode) await check('Two UI lesson charges create one durable installment due across restart', async () => {
      const trace = JSON.parse(fs.readFileSync(path.join(output, 'partial-purchase-admin.json'), 'utf8'));
      const purchase = trace.facts.find(fact => fact.step === (integratedCandidateMode ? 'lead-PURCHASE' : 'student-PURCHASE'));
      const consumption = trace.facts.find(fact => fact.step === 'PAID-LESSON-2');
      assert(purchase?.studentId && purchase?.subscription?.id);
      assert.equal(consumption?.lessonIds?.length, 2);
      if (integratedCandidateMode) {
        assert.equal(purchase.id, integratedLeadId);
        integratedStudentId = purchase.studentId;
        const card = await request('GET', `/crm/leads/${integratedLeadId}/card`);
        assert(card.linkedStudents.some(student => student.id === purchase.studentId));
        fs.writeFileSync(path.join(output, 'integrated-client-link.json'), JSON.stringify({
          leadId: integratedLeadId, studentId: purchase.studentId,
          subscriptionId: purchase.subscription.id, lessonIds: consumption.lessonIds,
        }, null, 2));
      }
      for (const role of ['admin', 'manager', 'director']) {
        fs.copyFileSync(path.join(output, `partial-purchase-${role}.json`),
          path.join(output, `installment-cycle-${role}.json`));
      }
      await stopApi();
      await startApi(fixture, true);
      token = (await request('POST', '/auth/login', {
        email: fixture.email, password: fixture.password,
      }, 200, { auth: false })).session.accessToken;
      await runDeviceTest('partial_purchase_live_test.dart', 'purchase-restart-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          accounts: fixture.clientAuditAccounts,
          cycleRestartStudentId: purchase.studentId }),
      });
      const issued = (await pool.query(
        'select id,student_id,final_price_minor::text from app.subscriptions where package_id=$1 order by id',
        [purchasePackage.id],
      )).rows;
      assert.equal(issued.length, 6);
      const records = [];
      for (const subscription of issued) {
        assert.equal(subscription.final_price_minor, '1440000');
        const payments = (await pool.query(
          'select id,amount_minor::text from app.payments where issued_subscription_id=$1 and deleted_at is null',
          [subscription.id],
        )).rows;
        const installments = (await pool.query(
          'select id,amount_minor::text,due_policy from app.subscription_installments where issued_subscription_id=$1',
          [subscription.id],
        )).rows;
        assert.equal(payments.length, 1);
        assert.equal(payments[0].amount_minor, '720000');
        assert.equal(installments.length, 1);
        assert.equal(installments[0].amount_minor, '720000');
        assert.equal(installments[0].due_policy, 'consumption');
        const due = (await pool.query(
          'select id,trigger_charge_fact_id,due_at from app.subscription_installment_due_facts where installment_id=$1',
          [installments[0].id],
        )).rows;
        assert.equal(due.length, subscription.id === purchase.subscription.id ? 1 : 0);
        records.push({ subscriptionId: subscription.id, paymentId: payments[0].id,
          installmentId: installments[0].id, dueFactId: due[0]?.id ?? null });
      }
      const charges = (await pool.query(
        `select id,lesson_id,units::text,created_at from app.lesson_client_charge_facts_effective
         where subscription_id=$1 and charge_type='subscription' order by created_at,id`,
        [purchase.subscription.id],
      )).rows;
      assert.equal(charges.length, 2);
      assert(charges.every(charge => Number(charge.units) === 1));
      assert.deepEqual(charges.map(charge => charge.lesson_id).sort(), [...consumption.lessonIds].sort());
      const target = records.find(record => record.subscriptionId === purchase.subscription.id);
      const due = (await pool.query(
        'select trigger_charge_fact_id,due_at from app.subscription_installment_due_facts where id=$1',
        [target.dueFactId],
      )).rows[0];
      assert.equal(due.trigger_charge_fact_id,
        charges.find(charge => charge.lesson_id === consumption.lessonIds[1]).id);
      assert.equal(new Date(due.due_at).toISOString(),
        new Date(charges.find(charge => charge.lesson_id === consumption.lessonIds[1]).created_at).toISOString());
      const dueRecords = (await pool.query(
        'select id,status,amount_minor::text from app.client_payment_records where installment_id=$1',
        [target.installmentId],
      )).rows;
      assert.equal(dueRecords.length, 1);
      assert.equal(dueRecords[0].status, 'posted_pending');
      assert.equal(dueRecords[0].amount_minor, '720000');
      const requestId = `installment-due:${target.installmentId}`;
      const audit = (await pool.query('select id from app.audit_events where request_id=$1', [requestId])).rows;
      const outbox = (await pool.query('select event_id from app.platform_outbox_events where request_id=$1', [requestId])).rows;
      assert.equal(audit.length, 1);
      assert.equal(outbox.length, 1);
      const evidence = { subscriptionCount: issued.length, records, chargeFacts: charges,
        dueAt: due.due_at, dueRecordId: dueRecords[0].id,
        auditId: audit[0].id, outboxId: outbox[0].event_id };
      fs.writeFileSync(path.join(output, 'installment-cycle-db.json'), JSON.stringify(evidence, null, 2));
      return { subscriptions: 6, initialPayments: 6, futureInstallments: 6,
        completedChargeFacts: 2, dueFacts: 1, pendingRecords: 1 };
    });
    const snapshots = {};
    for (const table of ['leads', 'students', 'subscriptions', 'payments', 'client_payment_records', 'client_payment_status_events', 'subscription_obligation_facts', 'subscription_lifecycle_events', 'subscription_installments']) {
      snapshots[table] = (await pool.query(`select to_jsonb(row) value from app.${table} row`)).rows.map(row => row.value);
    }
    fs.writeFileSync(path.join(output, 'purchase-db.json'), JSON.stringify(snapshots, null, 2));
    if (integratedCandidateMode) assert(integratedStudentId, 'Integrated task must follow a verified conversion and consumption');
    if (integratedCandidateMode) await require('./task-delivery-verification.cjs').runTaskDeliveryAudit({pool,fixture,baseUrl,output,check,
      linkedEntity: {type:'student',id:integratedStudentId},
      closeOpenTask:taskId=>runDeviceTest('notification_task_close_live_test.dart','notification-task-close-windows.log',{
        HTTP_JOURNEY_FIXTURE:JSON.stringify({baseUrl,password:fixture.password,
          accounts:fixture.clientAuditAccounts,taskId, closeWithComment:true})})});
  }
  if (process.argv.includes('--audit-dynamic-fields')) {
    await check('Dynamic fields and status persistence through actual client cards', () =>
      runDeviceTest('client_dynamic_fields_live_test.dart', 'dynamic-fields-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
    const snapshots = {};
    for (const table of ['leads', 'students', 'client_custom_field_definitions', 'client_custom_field_values']) {
      snapshots[table] = (await pool.query(`select to_jsonb(row) as value from app.${table} row order by id`)).rows.map(row => row.value);
    }
    fs.writeFileSync(path.join(output, 'dynamic-fields-db.json'), JSON.stringify(snapshots, null, 2));
  }
  if (process.argv.includes('--audit-card-fields')) {
    await check('Lead/student editable fields and clear operations under real roles', () =>
      runDeviceTest('client_fields_live_test.dart', 'client-fields-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
    const snapshots = {};
    for (const role of ['admin', 'manager', 'director']) {
      const marker = `FIELDS-${role}`;
      snapshots[role] = {
        leads: (await pool.query(`select id,first_name,last_name,phone,email from app.leads where last_name=$1`, [marker])).rows,
        students: (await pool.query(`select s.id,p.first_name,p.last_name,p.phone,s.contact_email,s.custom_data from app.students s
          join app.profiles p on p.id=s.profile_id where p.last_name=$1`, [marker])).rows,
      };
    }
    fs.writeFileSync(path.join(output, 'client-fields-db.json'), JSON.stringify(snapshots, null, 2));
  }
  if (process.argv.includes('--audit-navigation')) {
    await check('Five real role workspaces: navigation and section requests', () =>
      runDeviceTest('role_navigation_live_test.dart', 'role-navigation-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts,
          studentId: fixture.students[0], teacherId: fixture.teachers[0] }),
      }));
  }
  if (process.argv.includes('--client-persistence')) {
    await check('Client forms and autosave under three real employee roles', () =>
      runDeviceTest('client_persistence_live_test.dart', 'client-persistence-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
    const { verifyClientPersistence } = require('./client-persistence-verification.cjs');
    await verifyClientPersistence({ pool, output, check, baseUrl, fixture });
  }
  if (process.argv.some(arg => ['--client-persistence', '--client-persistence-api'].includes(arg))) {
    const { verifyClientCreationApi } = require('./client-persistence-verification.cjs');
    await verifyClientCreationApi({ pool, output, check, baseUrl, fixture });
  }
  if (process.argv.includes('--client-autosave')) {
    await check('Client autosave failure recovery with real employee capabilities', () =>
      runDeviceTest('client_persistence_live_test.dart', 'client-autosave-windows.log', {
        CLIENT_AUDIT_MODE: 'autosave',
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, password: fixture.password,
          branchId: fixture.branch, accounts: fixture.clientAuditAccounts }),
      }));
  }
  if (process.argv.includes('--release-journeys')) {
    await stopApi();
    await startApi(fixture, true);
    await check('Employee UI journey with real persistence and failure recovery', async () => {
      const scheduled = new Date();
      scheduled.setUTCDate(scheduled.getUTCDate() + 1);
      scheduled.setUTCHours(16, 0, 0, 0);
      await runDeviceTest('employee_journey_live_test.dart', 'employee-windows.log', {
        HTTP_JOURNEY_FIXTURE: JSON.stringify({ baseUrl, email: fixture.employeeEmail, password: fixture.password,
          branchId: fixture.branch, roomId: fixture.rooms[0], teacherId: fixture.teachers[0], scheduledAt: scheduled.toISOString() }),
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
  if (smtp) await smtp.close();
  if (pool) await pool.end();
  // Remove only the fresh database created by this invocation, never an input database.
  if (created) await admin.query(`drop database ${databaseName} with (force)`);
  if (admin) await admin.end();
  if (testedSource !== sourceFingerprint()) {
    results.push({ name: 'Candidate source remained unchanged', status: 'FAIL', detail: 'Source changed during the gate; rerun the final candidate.' });
  }
  const report = { finishedAt: new Date().toISOString(), requestCount, serverErrorCount,
    requestCountersScope: 'Built-in HTTP journeys only; native Flutter and client audit helper requests are additional.',
    revision, sourceSha256: testedSource,
    passed: results.filter(r => r.status === 'PASS').length, failed: results.filter(r => r.status === 'FAIL').length,
    scope: notificationSourceMode
      ? 'Local Windows Debug UI, real CRM Socket.IO, PostgreSQL outbox/task workers, OS notification MethodChannel capture; external push/email and actual OS display not verified.'
      : process.argv.includes('--audit-tasks')
        ? 'Local Windows Debug task UI, real CRM Socket.IO and PostgreSQL outbox worker; task reminder worker runs in separate notification-source mode. No production requests.'
      : process.argv.includes('--audit-collaboration-recovery')
        ? 'Local Windows Debug UI, two authenticated staff sessions, real CRM Socket.IO reconnect and PostgreSQL outbox worker; external delivery and production not used.'
      : 'Real HTTP/PostgreSQL and synthetic fixtures. Employee mode uses native Flutter product surfaces and the real completion worker; realtime delivery is disabled. No production requests.',
    employeeUiRequired: process.argv.includes('--release-journeys'),
    clientPersistenceUiRequired: process.argv.includes('--client-persistence'),
    restoreRequired: process.argv.includes('--restore') || process.argv.includes('--release-journeys'), results };
  fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(report, null, 2));
  console.log(`RESULT ${report.passed} passed, ${report.failed} failed; ${requestCount} HTTP requests; ${serverErrorCount} server errors`);
  console.log(`REPORT ${path.join(output, 'result.json')}`);
  if (report.failed) process.exitCode = 1;
});
