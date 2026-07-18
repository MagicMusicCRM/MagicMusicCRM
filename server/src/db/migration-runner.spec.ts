import { promises as fs } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { MigrationRunner } from './migration-runner';

describe('MigrationRunner', () => {
  it('runs "-- migrate:no-transaction" migrations without begin/commit (for CREATE INDEX CONCURRENTLY)', async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'mmcrm-mig-'));
    await fs.writeFile(path.join(dir, '0001_tx.up.sql'), 'create table t (id int);');
    await fs.writeFile(path.join(dir, '0001_tx.down.sql'), 'drop table t;');
    await fs.writeFile(
      path.join(dir, '0002_idx.up.sql'),
      [
        '-- migrate:no-transaction',
        'create index concurrently if not exists t_id_idx on t (id);',
        'create index concurrently if not exists t_id_idx_2 on t (id);'
      ].join('\n')
    );
    await fs.writeFile(
      path.join(dir, '0002_idx.down.sql'),
      '-- migrate:no-transaction\ndrop index concurrently if exists t_id_idx;'
    );

    const calls: string[] = [];
    const client = {
      query: jest.fn(async (sql: string) => {
        calls.push(typeof sql === 'string' ? sql.trim() : '');
        return { rows: [] };
      }),
      release: jest.fn()
    };
    const pool = {
      query: jest.fn(async (sql: string) => {
        calls.push(typeof sql === 'string' ? sql.trim() : '');
        return { rows: [] };
      }),
      connect: jest.fn(async () => client)
    };

    const runner = new MigrationRunner(pool as never, dir);
    const completed = await runner.up();

    try {
      expect(completed).toEqual(['0001_tx', '0002_idx']);

      const idx = calls.findIndex((c) => /create index concurrently/i.test(c));
      expect(idx).toBeGreaterThan(-1);
      expect(calls.filter((c) => /create index concurrently/i.test(c))).toHaveLength(2);
      // The CONCURRENTLY statement must NOT be wrapped: the call right before it
      // is not "begin".
      expect(calls[idx - 1]).not.toMatch(/^begin$/i);
      // ...and there is no "commit" right after it either (autocommit path).
      expect(calls[idx + 2]).toMatch(/insert into app_schema_migrations/i);
      // The normal migration WAS wrapped in a transaction.
      expect(calls.some((c) => /^begin$/i.test(c))).toBe(true);
      expect(calls.some((c) => /^commit$/i.test(c))).toBe(true);
      expect(pool.connect).toHaveBeenCalledTimes(1);
      expect(client.release).toHaveBeenCalledTimes(1);
      expect(client.query).toHaveBeenCalledWith('begin');
      expect(client.query).toHaveBeenCalledWith('commit');
    } finally {
      await fs.rm(dir, { recursive: true, force: true });
    }
  });

  it('runs a transactional rollback on one checked-out client', async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'mmcrm-mig-down-'));
    await fs.writeFile(path.join(dir, '0001_tx.up.sql'), 'create table t (id int);');
    await fs.writeFile(path.join(dir, '0001_tx.down.sql'), 'drop table t;');
    const client = {
      query: jest.fn(async (_sql: string) => ({ rows: [] })),
      release: jest.fn()
    };
    const pool = {
      query: jest.fn(async (sql: string) => ({
        rows: /order by applied_at desc/i.test(sql) ? [{ id: '0001_tx' }] : []
      })),
      connect: jest.fn(async () => client)
    };

    try {
      const runner = new MigrationRunner(pool as never, dir);
      await expect(runner.down()).resolves.toBe('0001_tx');
      expect(client.query.mock.calls.map((call) => call[0])).toEqual([
        'begin',
        'drop table t;',
        expect.stringContaining('delete from app_schema_migrations'),
        'commit'
      ]);
      expect(client.release).toHaveBeenCalledTimes(1);
    } finally {
      await fs.rm(dir, { recursive: true, force: true });
    }
  });
});
