import { PaymentCorrectionService } from '../crm/commerce/payment-correction.service';
import { PaymentReversalService } from '../crm/commerce/payment-reversal.service';
import { PaymentReversalRepository } from '../crm/commerce/payment-reversal.repository';
import { SubscriptionPreviewTokenService } from '../crm/commerce/subscription-preview-token.service';
import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createPaymentContractApp, paymentDocument } from '../../scripts/contracts/payment-contract-app';
import { wireContractValidator } from '../../scripts/contracts/validate-wire-contract';
import { DatabaseService } from '../db/database.service';
import { PlatformIntegrityService } from '../platform/platform-integrity.service';
import { PlatformIntegrityRepository } from '../platform/platform-integrity.repository';
import { PaymentLifecycleService } from '../crm/commerce/payment-lifecycle.service';
import { PaymentLifecycleRepository } from '../crm/commerce/payment-lifecycle.repository';
import { SubscriptionIssueRepository } from '../crm/commerce/subscription-issue.repository';
import { CommerceProjectionRepository } from '../crm/commerce/commerce-projection.repository';
import { SubscriptionReservationService } from '../crm/commerce/subscription-reservation.service';
import { RealtimeBus } from '../realtime/realtime-bus';
import { CrmPolicy } from '../crm/crm.policy';

const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
const fixtures = JSON.parse(readFileSync(resolve(__dirname, '../../../contracts/payments.fixtures.json'), 'utf8'));

(url ? describe : describe.skip)('payment commands through HTTP and PostgreSQL', () => {
  let db: DatabaseService;
  let app: INestApplication;
  let base: string;
  let validator: ReturnType<typeof wireContractValidator>;
  const actor = { userId: randomUUID(), role: 'director' as const };
  let role = 'director';
  let studentId: string;
  let otherStudentId: string;
  let recordId: string;
  let branchId: string;
  let correction: PaymentCorrectionService;
  const keys = [randomUUID(), randomUUID(), randomUUID()];
  const requestId = randomUUID();
  const path = () => `/api/crm/students/${studentId}/payment-records`;

  beforeAll(async () => {
    const target = new URL(url!);
    if (!['127.0.0.1', 'localhost'].includes(target.hostname) || !target.pathname.includes('audit_fix'))
      throw new Error('Explicit isolated localhost audit_fix database required');
    db = new DatabaseService(new ConfigService({ DATABASE_URL: url }));
    await db.query("insert into app.users(id,email,role) values($1,$2,'director')", [actor.userId, `${actor.userId}@example.test`]);
    const branch = await db.query("insert into app.branches(name,timezone_name) values($1,'Europe/Moscow') returning id", [`contract-${randomUUID()}`]);
    branchId = branch.rows[0].id;
    const ids = [];
    for (let i = 0; i < 2; i++) {
      const userId = randomUUID();
      await db.query("insert into app.users(id,email,role) values($1,$2,'client')", [userId, `${userId}@example.test`]);
      const profile = await db.query("insert into app.profiles(user_id,first_name,last_name) values($1,'Contract','Student') returning id", [userId]);
      const student = await db.query("insert into app.students(profile_id,status,branch_id) values($1,'active',$2) returning id", [profile.rows[0].id, branch.rows[0].id]);
      ids.push(student.rows[0].id);
    }
    [studentId, otherStudentId] = ids;
    const integrityRepository = new PlatformIntegrityRepository();
    const repository = new PaymentLifecycleRepository(db, integrityRepository);
    const issue = new SubscriptionIssueRepository(db);
    const policy = new CrmPolicy();
    const integrity = new PlatformIntegrityService(db, integrityRepository);
    const projections = new CommerceProjectionRepository(db);
    const reservations = new SubscriptionReservationService(db, {
      emitCrmChanged() {}, emitFinanceChanged() {},
    } as unknown as RealtimeBus);
    const service = new PaymentLifecycleService(repository, issue, policy, integrity, projections, reservations);
    const reversalRepository = new PaymentReversalRepository(db);
    const tokens = new SubscriptionPreviewTokenService(new ConfigService({ COMMERCE_PREVIEW_SECRET: randomUUID().repeat(2) }));
    correction = new PaymentCorrectionService(reversalRepository, repository, issue, projections, policy, integrity, tokens, reservations);
    const reversal = new PaymentReversalService(reversalRepository, issue, projections, policy, integrity, tokens, reservations);
    // JWT identity and realtime delivery are substituted; financial commands,
    // authorization, repositories, audit/outbox and the database remain real.
    app = await createPaymentContractApp(service, { canActivate(context) {
      context.switchToHttp().getRequest().user = { ...actor, role }; return true;
    } }, { correction, reversal });
    validator = wireContractValidator(paymentDocument(app));
    await app.listen(0, '127.0.0.1'); base = await app.getUrl();
  });
  afterAll(async () => { await app?.close(); await db?.onModuleDestroy(); });

  async function send(target: string, body: unknown, key?: string) {
    const response = await fetch(base + target, { method: 'POST', headers: {
      'Content-Type': 'application/json', 'X-Request-Id': requestId,
      ...(key ? { 'Idempotency-Key': key } : {}),
    }, body: JSON.stringify(body) });
    const data = await response.json();
    validator.response(target, 'POST', response.status, data);
    expect(response.headers.get('x-request-id')).toBe(requestId);
    return { status: response.status, data };
  }

  const balance = () => db.transaction(client =>
    new SubscriptionIssueRepository(db).readAccountBalance(client, studentId, 'RUB'));
  const paidInput = () => ({ amountMinor: '12345', currencyCode: 'RUB', status: 'paid',
    method: 'cashless', externalIdentifier: randomUUID(), occurredAt: fixtures[2].body.occurredAt,
    reason: 'Проверка исправления оплаты' });
  const counts = async () => (await db.query(`select
    (select count(*)::int from app.payments where student_id=$1) payments,
    (select count(*)::int from app.account_adjustments where student_id=$1) adjustments,
    (select count(*)::int from app.client_payment_records where student_id=$1) records`, [studentId])).rows[0];

  it('creates unpaid, pending and paid states with exactly one actual receipt', async () => {
    for (const [i, fixture] of fixtures.entries()) {
      const target = i === 0 ? path() : `${path()}/${recordId}/transition`;
      const response = await send(target, fixture.body, keys[i]);
      expect(response.status).toBe(201);
      if (i === 0) recordId = response.data.paymentRecord.id;
      expect(response.data.paymentRecord).toMatchObject({ id: recordId, studentId, amountMinor: '12345',
        status: fixture.response.paymentRecord.status, version: i + 1 });
      expect(response.data.statusHistory.map((e: { version: number }) => e.version)).toEqual(Array.from({ length: i + 1 }, (_, n) => n + 1));
      if (i < 2) expect(response.data.actualPayment).toBeNull();
      else {
        expect(response.data.actualPayment).toMatchObject({ id: response.data.paymentRecord.actualPaymentId,
          studentId, amountMinor: '12345', method: 'cashless', status: 'paid' });
        expect(response.data.statusHistory[2].actualPaymentId).toBe(response.data.actualPayment.id);
      }
    }
  });
  it('replays earlier commands with coherent current state and no duplicate money or history', async () => {
    for (const [i, fixture] of fixtures.entries()) {
      const response = await send(i === 0 ? path() : `${path()}/${recordId}/transition`, fixture.body, keys[i]);
      expect(response.status).toBe(201);
      expect(response.data.paymentRecord).toMatchObject({ status: 'paid', version: 3, id: recordId });
      expect(response.data.statusHistory).toHaveLength(3);
    }
    const counts = await db.query(`select
      (select count(*)::int from app.payments where payment_record_id=$1) receipts,
      (select count(*)::int from app.client_payment_status_events where payment_record_id=$1) events`, [recordId]);
    expect(counts.rows[0]).toEqual({ receipts: 1, events: 3 });
  });
  it('rejects stale versions, changed retry payloads and reversal through a status transition', async () => {
    expect((await send(`${path()}/${recordId}/transition`, { ...fixtures[1].body }, randomUUID())).status).toBe(409);
    expect((await send(path(), { ...fixtures[0].body, amountMinor: '999' }, keys[0])).status).toBe(409);
    expect((await send(`${path()}/${recordId}/transition`, { expectedVersion: 3, targetStatus: 'unpaid', reason: 'Проверка' }, randomUUID())).status).toBe(422);
  });
  it('returns documented validation errors and binds the payment to its student', async () => {
    expect((await send(path(), fixtures[0].body)).status).toBe(400);
    expect((await send(path(), { ...fixtures[0].body, amountMinor: 12345 }, randomUUID())).status).toBe(400);
    expect((await send(path(), { ...fixtures[0].body, status: 'paid' }, randomUUID())).status).toBe(422);
    expect((await send(`${path()}/${recordId}/transition`, { targetStatus: 'paid', reason: 'Проверка' }, randomUUID())).status).toBe(400);
    expect((await send(`/api/crm/students/${otherStudentId}/payment-records/${recordId}/transition`, fixtures[1].body, randomUUID())).status).toBe(404);
  });
  it('previews, corrects and reverses a paid record while preserving history and replay identity', async () => {
    const originalBalance = await balance();
    const source = await send(path(), paidInput(), randomUUID());
    expect(source.status).toBe(201);
    const sourceId = source.data.paymentRecord.id;
    const input = { expectedVersion: 1, amountMinor: '15000', status: 'paid' as const,
      method: 'cashless' as const, externalIdentifier: randomUUID(), branchId,
      occurredAt: fixtures[2].body.occurredAt };
    const beforePreview = await counts();
    const preview = await send(`${path()}/${sourceId}/correction/preview`, input);
    expect(preview.status).toBe(201);
    expect(preview.data.walletDeltaMinor).toBe('2655');
    expect(preview.data.resultingBalanceMinor).toBe((BigInt(originalBalance) + 15000n).toString());
    expect(await counts()).toEqual(beforePreview);
    const command = { previewToken: preview.data.previewToken, confirm: true, reason: 'Исправить сумму' };
    expect((await send(`${path()}/${sourceId}/correction`, { ...command, confirm: false }, randomUUID())).status).toBe(400);
    expect((await send(`${path()}/${sourceId}/correction`, { ...command, previewToken: 'x' + command.previewToken }, randomUUID())).status).toBe(422);
    expect((await send(`${path()}/${recordId}/correction`, command, randomUUID())).status).toBe(422);
    const expired = await correction.preview(actor, studentId, sourceId, input, new Date(Date.now() - 600_000));
    const expiredResult = await send(`${path()}/${sourceId}/correction`, { ...command, previewToken: expired.previewToken }, randomUUID());
    expect(expiredResult.status).toBe(422);
    expect(expiredResult.data.code).toBe('PREVIEW_TOKEN_EXPIRED');
    expect(await counts()).toEqual(beforePreview);
    const correctionKey = randomUUID();
    const corrected = await send(`${path()}/${sourceId}/correction`, command, correctionKey);
    expect(corrected.status).toBe(201);
    expect(corrected.data.replacement).toMatchObject({ amountMinor: '15000', status: 'paid', version: 1 });
    const fact = await db.query('select id from app.payment_record_corrections where source_payment_record_id=$1', [sourceId]);
    expect(corrected.data.correction.id).toBe(fact.rows[0].id);
    const afterCorrection = await counts();
    expect(afterCorrection).toEqual({ payments: beforePreview.payments + 1,
      adjustments: beforePreview.adjustments + 1, records: beforePreview.records + 1 });
    const repeated = await send(`${path()}/${sourceId}/correction`, command, correctionKey);
    expect(repeated.status).toBe(201);
    expect(repeated.data).toEqual({ ...corrected.data, replayed: true });
    expect(await counts()).toEqual(afterCorrection);
    expect(await balance()).toBe(preview.data.resultingBalanceMinor);

    const replacementId = corrected.data.replacement.id;
    const removal = await send(`${path()}/${replacementId}/reversal/preview`, { expectedVersion: 1 });
    expect(removal.status).toBe(201);
    expect(removal.data).toMatchObject({ operation: 'monetary_reversal', walletDeltaMinor: '-15000', resultingBalanceMinor: originalBalance });
    const reverseCommand = { previewToken: removal.data.previewToken, confirm: true, reason: 'Отмена ошибочной оплаты' };
    expect((await send(`${path()}/${replacementId}/reversal`, { ...reverseCommand, confirm: false }, randomUUID())).status).toBe(422);
    const reverseKey = randomUUID();
    const reversed = await send(`${path()}/${replacementId}/reversal`, reverseCommand, reverseKey);
    expect(reversed.status).toBe(201);
    expect(reversed.data.exclusion.counterpartKind).toBe('account_adjustment');
    expect((await send(`${path()}/${replacementId}/reversal`, reverseCommand, reverseKey)).data)
      .toEqual({ ...reversed.data, replayed: true });
    expect(await counts()).toEqual({ ...afterCorrection, adjustments: afterCorrection.adjustments + 1 });
    expect(await balance()).toBe(originalBalance);
    const originals = await db.query('select payment_record_id from app.payments where payment_record_id=any($1::uuid[])', [[sourceId, replacementId]]);
    expect(originals.rows).toHaveLength(2);
  });

  it('rejects a stale correction version and a reversal preview after wallet changes', async () => {
    const source = await send(path(), fixtures[0].body, randomUUID());
    expect(source.status).toBe(201);
    const id = source.data.paymentRecord.id;
    const preview = await send(`${path()}/${id}/correction/preview`, { expectedVersion: 1, amountMinor: '15000', status: 'unpaid' });
    expect(preview.status).toBe(201);
    expect((await send(`${path()}/${id}/transition`, fixtures[1].body, randomUUID())).status).toBe(201);
    expect((await send(`${path()}/${id}/correction`, { previewToken: preview.data.previewToken, confirm: true, reason: 'Устаревший расчёт' }, randomUUID())).status).toBe(409);
    const removal = await send(`${path()}/${id}/reversal/preview`, { expectedVersion: 2 });
    expect(removal.status).toBe(201);
    expect((await send(path(), paidInput(), randomUUID())).status).toBe(201);
    const before = await counts();
    const rejected = await send(`${path()}/${id}/reversal`, { previewToken: removal.data.previewToken, confirm: true, reason: 'Баланс изменился' }, randomUUID());
    expect(rejected.status).toBe(409);
    expect(rejected.data.code).toBe('PAYMENT_REVERSAL_PREVIEW_STALE');
    expect(await counts()).toEqual(before);
  });

  it('technically voids an unpaid record without creating a monetary adjustment', async () => {
    const created = await send(path(), fixtures[0].body, randomUUID());
    expect(created.status).toBe(201);
    const id = created.data.paymentRecord.id;
    const before = await counts();
    const beforeBalance = await balance();
    const preview = await send(`${path()}/${id}/reversal/preview`, { expectedVersion: 1 });
    expect(preview.status).toBe(201);
    expect(preview.data).toMatchObject({ operation: 'technical_void', walletDeltaMinor: '0' });
    const result = await send(`${path()}/${id}/reversal`, { previewToken: preview.data.previewToken, confirm: true, reason: 'Ошибочное обязательство' }, randomUUID());
    expect(result.status).toBe(201);
    expect(result.data.exclusion).toMatchObject({ sourceKind: 'payment_record', counterpartKind: null, counterpartId: null });
    expect(await counts()).toEqual(before);
    expect(await balance()).toBe(beforeBalance);
  });

  it('rejects forbidden roles and revoked database roles without new facts', async () => {
    const before = await db.query('select count(*)::int count from app.client_payment_records where student_id=$1', [studentId]);
    const correctionInput = { expectedVersion: 3, amountMinor: '15000', status: 'paid',
      method: 'cashless', branchId, externalIdentifier: randomUUID(), occurredAt: fixtures[2].body.occurredAt };
    const cp = await send(`${path()}/${recordId}/correction/preview`, correctionInput);
    const rp = await send(`${path()}/${recordId}/reversal/preview`, { expectedVersion: 3 });
    expect(cp.status).toBe(201);
    expect(rp.status).toBe(201);
    const adjustmentCases = [
      { route: 'correction/preview', body: correctionInput },
      { route: 'reversal/preview', body: { expectedVersion: 3 } },
      { route: 'correction', body: { previewToken: cp.data.previewToken, confirm: true, reason: 'Проверка прав' } },
      { route: 'reversal', body: { previewToken: rp.data.previewToken, confirm: true, reason: 'Проверка прав' } },
    ];
    const factsBefore = await counts();
    role = 'teacher';
    expect((await send(path(), fixtures[0].body, randomUUID())).status).toBe(403);
    for (const item of adjustmentCases) {
      expect((await send(`${path()}/${recordId}/${item.route}`, item.body, randomUUID())).status).toBe(403);
    }
    role = 'director';
    await db.query("update app.users set role='teacher' where id=$1", [actor.userId]);
    const response = await send(path(), fixtures[0].body, randomUUID());
    expect([403, 404]).toContain(response.status);
    for (const item of adjustmentCases) {
      expect([403, 404]).toContain((await send(`${path()}/${recordId}/${item.route}`, item.body, randomUUID())).status);
    }
    expect(await counts()).toEqual(factsBefore);
    const records = await db.query('select count(*)::int count from app.client_payment_records where student_id=$1', [studentId]);
    expect(records.rows[0].count).toBe(before.rows[0].count);
  });
});
