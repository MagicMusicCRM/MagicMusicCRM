import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { OpenAPIObject } from '@nestjs/swagger';
import { createPaymentContractApp, paymentDocument } from '../../scripts/contracts/payment-contract-app';
import { wireContractValidator } from '../../scripts/contracts/validate-wire-contract';
import { CreatePaymentRecordDto, TransitionPaymentRecordDto, PreviewPaymentCorrectionDto, CorrectPaymentDto,
  PreviewPaymentReversalDto, ReversePaymentDto } from '../crm/dto/payment-lifecycle.dto';

const root = resolve(__dirname, '../../../contracts');
const fixtures: Array<{ path: string; body: Record<string, unknown>; response: Record<string, unknown> }> =
  JSON.parse(readFileSync(resolve(root, 'payments.fixtures.json'), 'utf8'));
const stored: OpenAPIObject = JSON.parse(readFileSync(resolve(root, 'payments.openapi.json'), 'utf8'));
const validator = wireContractValidator(stored);
const adjustments: Array<{ operationId: string; path: string; body: Record<string, unknown>; response: Record<string, unknown> }> =
  JSON.parse(readFileSync(resolve(root, 'payment-adjustments.fixtures.json'), 'utf8'));

describe('payment command wire contract', () => {
  let app: INestApplication;
  beforeAll(async () => { app = await createPaymentContractApp(); });
  afterAll(async () => { await app?.close(); });
  it('matches current metadata and covers all six payment record operations', () => {
    expect(paymentDocument(app)).toEqual(stored);
    expect(Object.values(stored.paths).map(p => p.post?.operationId).sort()).toEqual([
      'correctPayment', 'createPaymentRecord', 'previewPaymentCorrection',
      'previewPaymentReversal', 'reversePayment', 'transitionPaymentRecord']);
  });
  it.each(adjustments)('validates preview/commit wire data for $operationId', async fixture => {
    validator.request(fixture.path, 'POST', fixture.body);
    validator.response(fixture.path, 'POST', 201, fixture.response);
    const metatype = { previewPaymentCorrection: PreviewPaymentCorrectionDto, correctPayment: CorrectPaymentDto,
      previewPaymentReversal: PreviewPaymentReversalDto, reversePayment: ReversePaymentDto }[fixture.operationId];
    const pipe = new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true });
    await expect(pipe.transform(fixture.body, { type: 'body', metatype })).resolves.toMatchObject(fixture.body);
  });
  it('rejects unsigned commit shape and accepts signed negative balance strings', () => {
    for (const fixture of adjustments.filter(f => !f.path.endsWith('/preview'))) {
      expect(() => validator.request(fixture.path, 'POST', { confirm: true, reason: 'Причина' })).toThrow();
      expect(() => validator.request(fixture.path, 'POST', { ...fixture.body, confirm: false })).toThrow();
    }
    const preview = adjustments[2];
    validator.response(preview.path, 'POST', 201, { ...preview.response,
      walletBalanceMinor: '100', resultingBalanceMinor: '-14900', negativeBalanceWarning: true });
  });
  it.each(fixtures)('accepts shared wire data for $path', async fixture => {
    validator.request(fixture.path, 'POST', fixture.body);
    validator.response(fixture.path, 'POST', 201, fixture.response);
    const pipe = new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true });
    await expect(pipe.transform(fixture.body, { type: 'body', metatype:
      fixture.path.endsWith('/transition') ? TransitionPaymentRecordDto : CreatePaymentRecordDto })).resolves.toMatchObject(fixture.body);
  });
  it('rejects numeric money, missing versions, unknown status and malformed nullable objects', () => {
    const create = fixtures[0], transition = fixtures[1];
    expect(() => validator.request(create.path, 'POST', { ...create.body, amountMinor: 12345 })).toThrow();
    expect(() => validator.request(create.path, 'POST', { ...create.body, amountMinor: '12.34' })).toThrow();
    expect(() => validator.request(create.path, 'POST', { ...create.body, status: 'unknown' })).toThrow();
    expect(() => validator.request(transition.path, 'POST', { targetStatus: 'paid', reason: 'Проверка' })).toThrow();
    expect(() => validator.request(create.path, 'POST', { ...create.body, extra: true })).toThrow();
    expect(() => validator.response(create.path, 'POST', 201, { ...create.response, actualPayment: {} })).toThrow();
  });
});
