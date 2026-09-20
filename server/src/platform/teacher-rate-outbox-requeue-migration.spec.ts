import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

describe("0157 teacher-rate outbox recovery", () => {
  it("audits failed deliveries, preserves event facts, excludes other states and is repeat-safe", async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create schema app;
        create table app.audit_events (action text, entity_type text, entity_id text,
          request_id text, reason text, before_ref jsonb, after_ref jsonb);
        create table app.platform_outbox_events (
          event_id uuid primary key, event_type text, aggregate_type text,
          aggregate_id text, aggregate_version bigint, request_id text, payload jsonb,
          occurred_at timestamptz default now(), attempts integer,
          available_at timestamptz default now(), claimed_at timestamptz,
          claimed_by text, last_error text, published_at timestamptz, dead_lettered_at timestamptz
        );
        insert into app.platform_outbox_events
          (event_id,event_type,aggregate_type,aggregate_id,aggregate_version,request_id,
           payload,attempts,last_error,dead_lettered_at,published_at)
        select ('10000000-0000-4000-8000-' || lpad(i::text,12,'0'))::uuid,
          case when i=2 then 'unknown.changed' else 'crm.lesson_teacher_rate.changed' end,
          'schedule:teacher-rate-bulk', case when i=5 then 'unexpected' else 'global' end,
          i, 'request-' || i, '{"action":"bulk_set"}',
          case when i in (3,4) then 1 else 10 end, 'Error',
          case when i in (3,4) then null else now() end,
          case when i=3 then now() else null end
        from generate_series(1,5) i;
      `);
      const rows = async () => (await db.query<Record<string, unknown>>(
        'select * from app.platform_outbox_events order by event_id')).rows;
      const before = await rows();
      const sql = await readFile(resolve(process.cwd(),
        'db/migrations/0157_requeue_teacher_rate_outbox.up.sql'), 'utf8');
      await db.exec(sql);
      const after = await rows();
      expect(after.slice(1)).toEqual(before.slice(1));
      expect(after[0]).toEqual({...before[0], attempts: 0, last_error: null,
        dead_lettered_at: null, available_at: expect.any(Date)});
      const audit = (await db.query<{before_ref: Record<string, unknown>}>(
        'select * from app.audit_events')).rows;
      expect(audit).toHaveLength(1);
      expect(audit[0].before_ref).toMatchObject({attempts: 10, lastError: 'Error',
        deadLetteredAt: expect.any(String)});
      await db.exec(sql);
      expect(await rows()).toEqual(after);
      expect((await db.query('select * from app.audit_events')).rows).toEqual(audit);
    } finally { await db.close(); }
  }, 30000);
});
