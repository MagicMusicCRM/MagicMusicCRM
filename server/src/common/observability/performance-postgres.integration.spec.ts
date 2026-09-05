import { ConfigService } from '@nestjs/config';
import { Logger } from '@nestjs/common';
import express = require('express');
import { Server } from 'node:http';
import { AddressInfo } from 'node:net';
import { DatabaseService } from '../../db/database.service';
import { RequestIdMiddleware } from '../middleware/request-id.middleware';

const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
const suite = url ? describe : describe.skip;

suite('HTTP to PostgreSQL performance correlation', () => {
  let db: DatabaseService;
  let server: Server;
  let base: string;
  let logs: Record<string, unknown>[];
  let log: jest.SpyInstance;

  beforeAll(async () => {
    const parsed = new URL(url!);
    if (!['localhost', '127.0.0.1'].includes(parsed.hostname) || !parsed.pathname.includes('audit_fix')) {
      throw new Error('Performance test requires the isolated local audit database');
    }
    db = new DatabaseService(new ConfigService({ DATABASE_URL: url }));
    logs = [];
    log = jest.spyOn(Logger.prototype, 'log').mockImplementation((value) => {
      if (value?.event === 'http.performance') logs.push(value);
    });
    const app = express();
    const middleware = new RequestIdMiddleware();
    app.use((req, res, next) => middleware.use(req, res, next));
    app.get('/api/probe/:id', async (_req, res, next) => {
      try {
        await Promise.all([
          db.query('select $1::text, pg_sleep(0.01)', ['private@example.test']),
          db.transaction(async client => { await client.query('select 42'); })
        ]);
        res.json({ ok: true });
      } catch (error) { next(error); }
    });
    app.get('/api/failure/:id', async (_req, res) => {
      try { await db.transaction(async client => { await client.query('select 1 / 0'); }); }
      catch { res.status(500).json({ ok: false }); }
    });
    server = await new Promise<Server>(resolve => {
      const started = app.listen(0, '127.0.0.1', () => resolve(started));
    });
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  afterAll(async () => {
    await new Promise<void>((resolve, reject) => server?.close(error => error ? reject(error) : resolve()));
    await db?.onModuleDestroy();
    log?.mockRestore();
  });

  it('correlates concurrent HTTP requests without leaking SQL, values or path IDs', async () => {
    const responses = await Promise.all(['request-a', 'request-b'].map(id => fetch(`${base}/api/probe/private-student?email=private@example.test`, {
      headers: { 'X-Request-Id': id, 'X-Operation-Id': 'a64b7f01-8001-4000-9000-000000000000' }
    })));
    for (const response of responses) {
      expect(response.status).toBe(200);
      expect(response.headers.get('server-timing')).toMatch(/^app;dur=[\d.]+, db;dur=[\d.]+, pool;dur=[\d.]+$/);
    }
    const entries = logs.filter(entry => ['request-a', 'request-b'].includes(entry.requestId as string));
    expect(entries).toHaveLength(2);
    for (const entry of entries) {
      expect(entry).toMatchObject({ dbQueryCount: 4, dbAcquireCount: 2, dbErrorCount: 0,
        route: '/api/probe/:id', outcome: 'completed', operationId: 'a64b7f01-8001-4000-9000-000000000000' });
      expect(entry.dbQueryMs).toEqual(expect.any(Number));
    }
    expect(JSON.stringify(entries)).not.toMatch(/private|select|email/);
  });

  it('records rollback and errors, sanitizes IDs, and logs unknown routes without raw URLs', async () => {
    const failed = await fetch(`${base}/api/failure/secret`, { headers: { 'X-Request-Id': 'request-failed' } });
    expect(failed.status).toBe(500);
    expect(logs.find(entry => entry.requestId === 'request-failed')).toMatchObject({ dbQueryCount: 3, dbErrorCount: 1 });
    const missing = await fetch(`${base}/api/private@example.test`, { headers: { 'X-Request-Id': 'private@example.test' } });
    expect(missing.headers.get('x-request-id')).toMatch(/^[0-9a-f-]{36}$/);
    expect(logs.at(-1)?.route).toBe('unmatched');
    expect(JSON.stringify(logs.at(-1))).not.toContain('private');
  });
});
