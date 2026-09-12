// Independent persistence assertions run even when a native UI test fails.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

async function verifyClientPersistence({ pool, output, check, baseUrl, fixture }) {
  for (const role of ['admin', 'manager', 'director']) {
    for (const entity of ['lead', 'student']) {
      await check(`${role}/${entity}: persisted checkpoints and exactly one creation after retry`, async () => {
        const file = path.join(output, `client-${role}-${entity}.json`);
        assert(fs.existsSync(file), 'Native evidence was not produced');
        const result = JSON.parse(fs.readFileSync(file, 'utf8'));
        const query = entity === 'lead'
          ? `select id, first_name, last_name, email from app.leads where last_name=$1`
          : `select s.id,p.first_name,p.last_name,u.email from app.students s
             join app.profiles p on p.id=s.profile_id join app.users u on u.id=p.user_id where p.last_name=$1`;
        const rows = (await pool.query(query, [result.marker])).rows;
        fs.writeFileSync(path.join(output, `client-${role}-${entity}-db.json`), JSON.stringify({ rows, checkpoints: result.checkpoints }, null, 2));
        assert(result.checkpoints.includes('autosave-reopened'), 'Autosave readback was not reached');
        assert(result.checkpoints.includes('response-lost-draft-retained'), 'Lost-response UI recovery was not reached');
        assert.equal(rows.length, 2, 'Expected one normal creation and one retried creation, without duplicates');
        assert.equal(new Set(result.retryIds).size, 1, 'Retry returned a second persisted client');
        return { checkpoints: result.checkpoints, persistedCount: rows.length };
      });
    }
  }
  for (const account of fixture.clientAuditAccounts.filter(a => ['teacher', 'client'].includes(a.role))) {
    await check(`${account.role}: backend rejects lead and student creation without writes`, async () => {
      const loginResponse = await fetch(`${baseUrl}/auth/login`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: account.email, password: fixture.password }),
      });
      assert.equal(loginResponse.status, 200);
      const login = await loginResponse.json();
      const headers = { 'content-type': 'application/json', authorization: `Bearer ${login.session.accessToken}` };
      const accessResponse = await fetch(`${baseUrl}/access/me`, { headers });
      assert.equal(accessResponse.status, 200);
      const access = await accessResponse.json();
      assert.equal(access.role, account.role);
      const source = (await pool.query(`select id from app.lead_sources where is_active and deleted_at is null limit 1`)).rows[0].id;
      const before = (await pool.query(`select (select count(*) from app.leads)::int leads,(select count(*) from app.students)::int students`)).rows[0];
      for (const entity of ['leads', 'students']) {
        const response = await fetch(`${baseUrl}/crm/${entity}`, {
          method: 'POST', headers,
          body: JSON.stringify({ firstName: 'Запрещённый', lastName: 'Аудит', phone: '+79995554433',
            sourceId: source, branchId: fixture.branch, status: 'new', customFields: [] }),
        });
        assert.equal(response.status, 403, `${account.role}/${entity}: must reject with 403`);
      }
      const after = (await pool.query(`select (select count(*) from app.leads)::int leads,(select count(*) from app.students)::int students`)).rows[0];
      assert.deepEqual(after, before);
    });
  }
}

async function verifyClientCreationApi({ pool, output, check, baseUrl, fixture }) {
  const evidence = [];
  for (const account of fixture.clientAuditAccounts) {
    let headers;
    await check(`${account.role}: real linked account authenticates`, async () => {
      const response = await fetch(`${baseUrl}/auth/login`, { method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: account.email, password: fixture.password }), signal: AbortSignal.timeout(20000) });
      assert.equal(response.status, 200);
      const login = await response.json();
      assert(login.session?.accessToken);
      headers = { 'content-type': 'application/json', authorization: `Bearer ${login.session.accessToken}` };
      const accessResponse = await fetch(`${baseUrl}/access/me`, { headers, signal: AbortSignal.timeout(20000) });
      assert.equal(accessResponse.status, 200);
      assert.equal((await accessResponse.json()).role, account.role);
    });
    if (!headers) continue;
    if (['teacher', 'client'].includes(account.role)) {
      await check(`${account.role}: lesson collection matches own assigned scope in PostgreSQL`, async () => {
        const response = await fetch(`${baseUrl}/crm/lessons?limit=100`, { headers, signal: AbortSignal.timeout(20000) });
        assert.equal(response.status, 200);
        const actual = (await response.json()).items.map(item => item.id).sort();
        const column = account.role === 'teacher' ? 'teacher_id' : 'student_id';
        const expected = (await pool.query(`select id from app.lessons where ${column}=$1 and deleted_at is null`,
          [account.role === 'teacher' ? fixture.teachers[0] : fixture.students[0]])).rows.map(row => row.id).sort();
        assert(expected.length > 0, 'Seeded linked role must have real lessons');
        evidence.push({ role: account.role, operation: 'read-lessons', expected, actual });
        assert.deepEqual(actual, expected, 'Only assigned lessons must be returned, with none missing');
        return { expectedLessons: expected.length, actualLessons: actual.length };
      });
      if (account.role === 'client') {
        await check('client: personal summary contains the linked student only', async () => {
          const response = await fetch(`${baseUrl}/crm/me`, { headers, signal: AbortSignal.timeout(20000) });
          assert.equal(response.status, 200);
          assert.deepEqual((await response.json()).students.map(s => s.id), [fixture.students[0]]);
        });
      }
      continue;
    }
    for (const entity of ['lead', 'student']) {
      await check(`${account.role}/${entity}: same HTTP idempotency key returns one persisted client`, async () => {
        const pipelineResponse = await fetch(`${baseUrl}/crm/client-pipelines?clientType=${entity}&branchId=${fixture.branch}`, { headers, signal: AbortSignal.timeout(20000) });
        assert.equal(pipelineResponse.status, 200);
        const pipeline = await pipelineResponse.json();
        const status = pipeline.stages.find(stage => stage.active).key;
        const sourceId = (await pool.query(`select id from app.lead_sources where is_active and deleted_at is null limit 1`)).rows[0].id;
        const marker = `AUDIT-HTTP-${account.role}-${entity}`;
        const body = { firstName: 'ПовторHTTP', lastName: marker, phone: '+79995554433',
          branchId: fixture.branch, sourceId, status, customFields: [] };
        const key = randomUUID();
        const responses = [];
        for (let attempt = 0; attempt < 2; attempt++) {
          const response = await fetch(`${baseUrl}/crm/${entity}s`, { method: 'POST',
            headers: { ...headers, 'idempotency-key': key, 'x-request-id': randomUUID() },
            body: JSON.stringify(body), signal: AbortSignal.timeout(20000) });
          const data = await response.json();
          responses.push({ status: response.status, id: data.id, code: data.code });
          assert.equal(response.status, 201, `Creation failed before replay check: ${data.code ?? data.message}`);
        }
        const rows = (await pool.query(entity === 'lead'
          ? `select id from app.leads where last_name=$1`
          : `select s.id from app.students s join app.profiles p on p.id=s.profile_id where p.last_name=$1`, [marker])).rows;
        evidence.push({ role: account.role, entity, operation: 'same-key-retry', key, responses, rows });
        assert.equal(rows.length, 1, 'Identical creation command was persisted twice');
        assert.equal(responses[1].id, responses[0].id);
      });
    }
  }
  fs.writeFileSync(path.join(output, 'client-api-evidence.json'), JSON.stringify(evidence, null, 2));
}

module.exports = { verifyClientPersistence, verifyClientCreationApi };
