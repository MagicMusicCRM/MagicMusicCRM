import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { OpenAPIObject } from '@nestjs/swagger';
import { createExpenseContractApp, expenseDocument } from '../../scripts/contracts/expense-contract-app';
import { wireContractValidator } from '../../scripts/contracts/validate-wire-contract';
import { UpsertExpenseDto } from '../crm/dto/upsert-expense.dto';
import { UpdateExpenseDto } from '../crm/dto/update-expense.dto';
import { ExpenseVersionQuery } from '../crm/dto/expense.query';

const root = resolve(__dirname, '../../../contracts');
const fixtures: Array<{ method: string; path: string; body: Record<string, unknown>; query?: Record<string, unknown>; status: number; response: Record<string, unknown> }> =
  JSON.parse(readFileSync(resolve(root, 'expenses.fixtures.json'), 'utf8'));
const stored: OpenAPIObject = JSON.parse(readFileSync(resolve(root, 'expenses.openapi.json'), 'utf8'));
const validator = wireContractValidator(stored);

describe('expense wire contract', () => {
  let app: INestApplication;
  beforeAll(async () => { app = await createExpenseContractApp(); });
  afterAll(async () => { await app?.close(); });
  it('matches live controller metadata and covers exactly the expense CRUD operations', () => {
    expect(expenseDocument(app)).toEqual(stored);
    expect(Object.values(stored.paths).flatMap(p => Object.values(p).map(op => op.operationId)).sort())
      .toEqual(['createExpense', 'deleteExpense', 'listExpenses', 'updateExpense']);
  });
  it.each(fixtures)('accepts shared Flutter fixture $method $path', (fixture) => {
    validator.request(fixture.path, fixture.method, fixture.body, fixture.query);
    validator.response(fixture.path, fixture.method, fixture.status, fixture.response);
  });
  it('detects missing version, unknown input fields and broken response types', () => {
    const patch = fixtures.find(f => f.method === 'PATCH')!;
    const { expectedVersion: _, ...missingVersion } = patch.body;
    expect(() => validator.request(patch.path, 'PATCH', missingVersion)).toThrow();
    expect(() => validator.request(patch.path, 'PATCH', { ...patch.body, typo: true })).toThrow();
    expect(() => validator.response(patch.path, 'PATCH', 200, { ...patch.response, version: '2' })).toThrow();
    expect(() => validator.response(patch.path, 'PATCH', 200, { ...patch.response, occurredAt: 'not-a-date' })).toThrow();
  });
  it('keeps the real ValidationPipe compatible with the shared requests', async () => {
    const pipe = new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true });
    await expect(pipe.transform(fixtures[0].body, { type: 'body', metatype: UpsertExpenseDto })).resolves.toMatchObject(fixtures[0].body);
    await expect(pipe.transform(fixtures[2].body, { type: 'body', metatype: UpdateExpenseDto })).resolves.toMatchObject(fixtures[2].body);
    await expect(pipe.transform({ expectedVersion: '2' }, { type: 'query', metatype: ExpenseVersionQuery })).resolves.toMatchObject({ expectedVersion: 2 });
    await expect(pipe.transform({ amount: 1 }, { type: 'body', metatype: UpdateExpenseDto })).rejects.toThrow();
    await expect(pipe.transform({ ...fixtures[0].body, typo: 1 }, { type: 'body', metatype: UpsertExpenseDto })).rejects.toThrow();
  });
  it('returns the documented error envelope when authentication is absent', async () => {
    await app.listen(0, '127.0.0.1');
    const response = await fetch(await app.getUrl() + '/api/crm/expenses');
    expect(response.status).toBe(401);
    validator.response('/api/crm/expenses', 'GET', 401, await response.json());
  });
});
