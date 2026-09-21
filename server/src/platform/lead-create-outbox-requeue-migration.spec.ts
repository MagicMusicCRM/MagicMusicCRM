import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

describe("0160 Lead create outbox recovery", () => {
  it("audits and rearms only resolvable failed deliveries without changing event facts", async () => {
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
          claimed_by text, last_error text, published_at timestamptz,
          dead_lettered_at timestamptz
        );
        create table app.idempotency_records (
          operation text, status text, result_ref jsonb, outbox_event_id uuid
        );
        insert into app.platform_outbox_events
          (event_id,event_type,aggregate_type,aggregate_id,aggregate_version,request_id,
           payload,attempts,last_error,published_at,dead_lettered_at)
        values
          ('10000000-0000-4000-8000-000000000001','crm.lead.create.committed',
           'client_create_command','key-1',1,'request-1','{}',10,'Error',null,now()),
          ('10000000-0000-4000-8000-000000000002','crm.lead.create.committed',
           'client_create_command','key-2',1,'request-2','{}',10,'Error',null,now()),
          ('10000000-0000-4000-8000-000000000003','unknown.changed',
           'client_create_command','key-3',1,'request-3','{}',10,'Error',null,now()),
          ('10000000-0000-4000-8000-000000000004','crm.lead.create.committed',
           'client_create_command','key-4',1,'request-4','{}',1,null,now(),null);
        insert into app.idempotency_records
          (operation,status,result_ref,outbox_event_id)
        values
          ('crm.lead.create','completed','{"leadId":"lead-a"}',
           '10000000-0000-4000-8000-000000000001'),
          ('crm.lead.create','completed','{}',
           '10000000-0000-4000-8000-000000000002'),
          ('crm.lead.create','completed','{"leadId":"lead-c"}',
           '10000000-0000-4000-8000-000000000003'),
          ('crm.lead.create','completed','{"leadId":"lead-d"}',
           '10000000-0000-4000-8000-000000000004');
      `);
      const rows = async () =>
        (
          await db.query<Record<string, unknown>>(
            "select * from app.platform_outbox_events order by event_id",
          )
        ).rows;
      const before = await rows();
      const sql = await readFile(
        resolve(
          process.cwd(),
          "db/migrations/0160_requeue_lead_create_outbox.up.sql",
        ),
        "utf8",
      );

      await db.exec(sql);

      const after = await rows();
      expect(after[0]).toEqual({
        ...before[0],
        attempts: 0,
        last_error: null,
        dead_lettered_at: null,
        available_at: expect.any(Date),
      });
      expect(after.slice(1)).toEqual(before.slice(1));
      const audit = (
        await db.query<{
          before_ref: Record<string, unknown>;
          after_ref: Record<string, unknown>;
        }>("select before_ref,after_ref from app.audit_events")
      ).rows;
      expect(audit).toEqual([
        {
          before_ref: expect.objectContaining({
            attempts: 10,
            lastError: "Error",
            deadLetteredAt: expect.any(String),
          }),
          after_ref: {
            attempts: 0,
            deliveryState: "pending",
            entityId: "lead-a",
          },
        },
      ]);

      await db.exec(sql);
      expect(await rows()).toEqual(after);
      expect(
        (await db.query("select * from app.audit_events")).rows,
      ).toHaveLength(1);
    } finally {
      await db.close();
    }
  }, 30_000);
});
