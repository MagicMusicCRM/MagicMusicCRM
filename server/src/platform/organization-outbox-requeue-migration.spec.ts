import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

describe("0135 organization outbox replay migration", () => {
  it("re-arms only unpublished organization lifecycle dead letters", async () => {
    const database = new PGlite();
    await database.exec(`
      create schema app;
      create table app.platform_outbox_events (
        event_id uuid primary key,
        event_type text not null,
        attempts integer not null,
        available_at timestamptz not null,
        claimed_at timestamptz,
        claimed_by text,
        last_error text,
        published_at timestamptz,
        dead_lettered_at timestamptz
      );
      insert into app.platform_outbox_events (
        event_id, event_type, attempts, available_at, claimed_at, claimed_by,
        last_error, published_at, dead_lettered_at
      ) values
        ('10000000-0000-4000-8000-000000000001',
         'organization.branch.changed', 10, now(), now(), 'worker-a',
         'Error', null, now()),
        ('10000000-0000-4000-8000-000000000002',
         'unknown.changed', 10, now(), null, null, 'Error', null, now()),
        ('10000000-0000-4000-8000-000000000003',
         'organization.room.changed', 1, now(), null, null, null, now(), null);
    `);
    const migration = await readFile(
      resolve(
        process.cwd(),
        "db/migrations/0135_requeue_organization_outbox.up.sql",
      ),
      "utf8",
    );

    await database.exec(migration);

    const result = await database.query<{
      event_type: string;
      attempts: number;
      last_error: string | null;
      published_at: Date | null;
      dead_lettered_at: Date | null;
    }>(
      `select event_type, attempts, last_error, published_at, dead_lettered_at
         from app.platform_outbox_events
        order by event_id`,
    );
    expect(result.rows).toEqual([
      expect.objectContaining({
        event_type: "organization.branch.changed",
        attempts: 0,
        last_error: null,
        published_at: null,
        dead_lettered_at: null,
      }),
      expect.objectContaining({
        event_type: "unknown.changed",
        attempts: 10,
        last_error: "Error",
        published_at: null,
        dead_lettered_at: expect.any(Date),
      }),
      expect.objectContaining({
        event_type: "organization.room.changed",
        attempts: 1,
        published_at: expect.any(Date),
        dead_lettered_at: null,
      }),
    ]);
    await database.close();
  }, 30_000);
});
