import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { AddressInfo } from 'node:net';
import { createExpenseContractApp, expenseDocument } from '../../scripts/contracts/expense-contract-app';
import { wireContractValidator } from '../../scripts/contracts/validate-wire-contract';
import { DatabaseService } from '../db/database.service';
import { PlatformIntegrityService } from '../platform/platform-integrity.service';
import { PlatformIntegrityRepository } from '../platform/platform-integrity.repository';
import { ExpenseService } from '../crm/finance/expense.service';
import { CrmPolicy } from '../crm/crm.policy';

const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
const fixtures = JSON.parse(readFileSync(resolve(__dirname, '../../../contracts/expenses.fixtures.json'), 'utf8'));

(url ? describe : describe.skip)('expense contract through HTTP and PostgreSQL', () => {
  let db: DatabaseService;
  let app: INestApplication;
  let base: string;
  let validator: ReturnType<typeof wireContractValidator>;
  const actor = { userId: randomUUID(), role: 'director' as const };
  let role = 'director';
  let expenseId: string;
  const category = randomUUID();
  const firstKey = randomUUID();
  const updateKey = randomUUID();
  const requestId = randomUUID();
  const createBody = { ...fixtures[0].body, category };

  beforeAll(async () => {
    const target = new URL(url!);
    if (!['127.0.0.1', 'localhost'].includes(target.hostname) || !target.pathname.includes('audit_fix')) {
      throw new Error('Explicit isolated localhost audit_fix database required');
    }
    db = new DatabaseService(new ConfigService({ DATABASE_URL: url }));
    await db.query("insert into app.users(id,email,role) values($1,$2,'director')", [actor.userId, `${actor.userId}@example.test`]);
    const service = new ExpenseService(db, new PlatformIntegrityService(db, new PlatformIntegrityRepository()), new CrmPolicy());
    // Only JWT identity is supplied by the harness. Controller, DTO validation,
    // domain service, authorization, transactions, audit and outbox are real.
    app = await createExpenseContractApp(service, { canActivate(context) {
      context.switchToHttp().getRequest().user = { ...actor, role };
      return true;
    } });
    validator = wireContractValidator(expenseDocument(app));
    await app.listen(0, '127.0.0.1');
    base = `http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}`;
  });
  afterAll(async () => { await app?.close(); await db?.onModuleDestroy(); });

  async function send(method: string, path: string, body?: unknown, query: Record<string, unknown> = {}, key?: string) {
    const target = new URL(base + path);
    for (const [k, v] of Object.entries(query)) target.searchParams.set(k, String(v));
    const response = await fetch(target, { method, headers: {
      'Content-Type': 'application/json', 'X-Request-Id': requestId,
      ...(key ? { 'Idempotency-Key': key } : {}),
    }, body: body === undefined ? undefined : JSON.stringify(body) });
    const result = await response.json();
    validator.response(path, method, response.status, result);
    expect(response.headers.get('x-request-id')).toBe(requestId);
    return { status: response.status, body: result };
  }

  it('executes the shared Flutter CRUD journey with real versioned expense responses', async () => {
    for (const fixture of fixtures) {
      const path = fixture.path.replace(fixtures[0].response.id, expenseId ?? fixtures[0].response.id);
      const body = fixture.body ? { ...fixture.body, category } : undefined;
      const query = { ...fixture.query, ...(fixture.query?.category ? { category } : {}) };
      validator.request(path, fixture.method, body, query);
      const key = fixture.method === 'POST' ? firstKey : fixture.method === 'PATCH' ? updateKey : randomUUID();
      const response = await send(fixture.method, path, body, query, key);
      expect(response.status).toBe(fixture.status);
      if (fixture.method === 'POST') expenseId = response.body.id;
      // Volatile identity/time come from PostgreSQL, all other values must match.
      const normalized = JSON.parse(JSON.stringify(response.body), (key, value) =>
        key === 'id' ? fixtures[0].response.id : key === 'category' ? fixtures[0].body.category :
          key === 'createdAt' ? fixtures[0].response.createdAt : value);
      expect(normalized).toEqual(fixture.response);
    }
    const replay = await send('POST', '/api/crm/expenses', createBody, {}, firstKey);
    expect(replay.body).toMatchObject({ id: expenseId, version: 1, amount: 120.25 });
  });

  it('returns documented validation and idempotency errors', async () => {
    expect((await send('POST', '/api/crm/expenses', createBody)).status).toBe(400);
    expect((await send('PATCH', `/api/crm/expenses/${expenseId}`, { amount: 1 }, {}, randomUUID())).status).toBe(400);
    expect((await send('POST', '/api/crm/expenses', { ...createBody, typo: 1 }, {}, randomUUID())).status).toBe(400);
    expect((await send('GET', '/api/crm/expenses', undefined, { limit: 501 })).status).toBe(400);
    expect((await send('PATCH', '/api/crm/expenses/not-a-uuid', { expectedVersion: 1 }, {}, randomUUID())).status).toBe(400);
    expect((await send('POST', '/api/crm/expenses', { ...createBody, amount: 999 }, {}, firstKey)).status).toBe(409);
  });

  it('keeps the total stable across cursor pages without missing or repeated records', async () => {
    const pageCategory = randomUUID();
    const ids = [];
    for (let i = 0; i < 2; i++) {
      const created = await send('POST', '/api/crm/expenses', { ...createBody, category: pageCategory }, {}, randomUUID());
      expect(created.status).toBe(201);
      ids.push(created.body.id);
    }
    const first = await send('GET', '/api/crm/expenses', undefined, { category: pageCategory, limit: 1 });
    expect(first.body.nextCursor).toEqual(expect.any(String));
    const second = await send('GET', '/api/crm/expenses', undefined, { category: pageCategory, limit: 1, cursor: first.body.nextCursor });
    expect(second.body.nextCursor).toBeNull();
    expect(first.body.total).toBe(240.5);
    expect(second.body.total).toBe(240.5);
    expect([...first.body.items, ...second.body.items].map(row => row.id).sort()).toEqual(ids.sort());
  });

  it('keeps forbidden-role errors compatible and preserves the financial facts', async () => {
    role = 'teacher';
    expect((await send('GET', '/api/crm/expenses')).status).toBe(403);
    expect((await send('POST', '/api/crm/expenses', createBody, {}, randomUUID())).status).toBe(403);
    const revisions = await db.query('select version from app.expense_revisions where expense_id=$1 order by version', [expenseId]);
    expect(revisions.rows.map(row => Number(row.version))).toEqual([1, 2, 3]);
  });
});
