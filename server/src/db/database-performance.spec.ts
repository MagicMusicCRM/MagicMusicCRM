import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient } from 'pg';
import { DatabaseService } from './database.service';
import { newRequestPerformance, requestPerformance } from '../common/observability/request-performance';

describe('database performance adapter', () => {
  const failure = new Error('original failure');
  let db: DatabaseService;
  let query: jest.Mock;
  let release: jest.Mock;
  let connect: jest.SpyInstance;
  let rawClient: PoolClient;

  beforeEach(() => {
    query = jest.fn().mockResolvedValue({ rows: [], rowCount: 0 });
    release = jest.fn();
    rawClient = { query, release } as unknown as PoolClient;
    connect = jest.spyOn(Pool.prototype, 'connect').mockImplementation((() =>
      new Promise(resolve => setTimeout(() => resolve(rawClient), 10))) as never);
    db = new DatabaseService(new ConfigService({ DATABASE_URL: 'postgresql://unused/unused' }));
  });
  afterEach(async () => { connect.mockRestore(); await db.onModuleDestroy(); });

  it('measures acquire separately, and counts every transaction statement', async () => {
    const context = newRequestPerformance('transaction');
    const result = await requestPerformance.run(context, () => db.transaction(async client => {
      await client.query('select $1::text', ['private value']);
      return 42;
    }));
    expect(result).toBe(42);
    expect(context).toMatchObject({ dbQueryCount: 3, dbAcquireCount: 1, dbErrorCount: 0 });
    expect(context.dbAcquireMs).toBeGreaterThan(1);
    expect(rawClient.query).toBe(query);
    expect(release).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(context)).not.toContain('private value');
  });

  it('preserves the original failure and discards the connection if rollback fails', async () => {
    const rollbackFailure = new Error('rollback failed');
    query.mockImplementation(async (sql: string) => { if (sql === 'rollback') throw rollbackFailure; return { rows: [] }; });
    await requestPerformance.run(newRequestPerformance('rollback'), async () => {
      await expect(db.transaction(async () => { throw failure; })).rejects.toBe(failure);
    });
    expect(release).toHaveBeenCalledWith(rollbackFailure);
  });

  it('releases a failed single-query connection exactly once', async () => {
    query.mockRejectedValueOnce(failure);
    const context = newRequestPerformance('single');
    await requestPerformance.run(context, () => expect(db.query('select broken')).rejects.toBe(failure));
    expect(release).toHaveBeenCalledTimes(1);
    expect(release).toHaveBeenCalledWith(failure);
    expect(context.dbErrorCount).toBe(1);
  });

  it('keeps callback queries compatible without modifying the pooled client', async () => {
    query.mockImplementation((sql, callback) => {
      if (typeof callback === 'function') callback(null, { rows: [{ result: 42 }] });
      return Promise.resolve({ rows: [] });
    });
    await requestPerformance.run(newRequestPerformance('callback'), () => db.transaction(client =>
      new Promise<void>((resolve, reject) => client.query('select 42', (error, result) => {
        if (error) return reject(error);
        expect(result.rows[0].result).toBe(42);
        resolve();
      }))));
    expect(rawClient.query).toBe(query);
    expect(release).toHaveBeenCalledTimes(1);
  });
});
