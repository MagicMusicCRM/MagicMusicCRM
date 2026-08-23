import { randomUUID } from "crypto";
import { Pool } from "pg";
import { runPreflight } from "./preflight";

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? process.env.DATABASE_URL
  ?? "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";

describe("T8.1.3 workflow preflight", () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 2 });
  const entityId = randomUUID();
  const openTaskId = randomUUID();
  const doneTaskId = randomUUID();
  const leadId = randomUUID();
  const groupId = randomUUID();
  const distantIndividualLessonId = randomUUID();
  const distantGroupLessonId = randomUUID();

  beforeAll(async () => {
    await pool.query(
      `insert into app.tasks (id, entity_type, entity_id, title, status)
       values
         ($1, 'lead', $3, 'Open fixture', 'open'),
         ($2, 'lead', $3, 'Done fixture', 'done')`,
      [openTaskId, doneTaskId, entityId],
    );
    await pool.query("insert into app.leads (id, first_name) values ($1, 'Horizon')", [leadId]);
    await pool.query("insert into app.groups (id, name) values ($1, 'Horizon group')", [groupId]);
    await pool.query(
      `insert into app.lessons (id, lead_id, scheduled_at)
       values ($1, $2, now() + interval '90 days')`,
      [distantIndividualLessonId, leadId],
    );
    await pool.query(
      `insert into app.lessons (id, group_id, scheduled_at)
       values ($1, $2, now() + interval '90 days')`,
      [distantGroupLessonId, groupId],
    );
  });

  afterAll(async () => {
    await pool.query("delete from app.tasks where id = any($1::uuid[])", [
      [openTaskId, doneTaskId],
    ]);
    await pool.query("delete from app.lessons where id = any($1::uuid[])", [[
      distantIndividualLessonId,
      distantGroupLessonId,
    ]]);
    await pool.query("delete from app.groups where id = $1", [groupId]);
    await pool.query("delete from app.leads where id = $1", [leadId]);
    await pool.end();
  });

  it("blocks an unanchored open task but ignores closed history", async () => {
    const report = await runPreflight(pool);
    const check = report.checks.find(
      (item) => item.id === "workflow.task-audience-ambiguous",
    );

    expect(check?.rows).toEqual(expect.arrayContaining([
      expect.objectContaining({ entityId: openTaskId }),
    ]));
    expect(check?.rows).not.toEqual(expect.arrayContaining([
      expect.objectContaining({ entityId: doneTaskId }),
    ]));
  });

  it("limits individual snapshot blockers to 60 days but preserves group blockers", async () => {
    const report = await runPreflight(pool);
    const check = report.checks.find(
      (item) => item.id === "schedule.future-snapshot-incomplete",
    );
    expect(check?.rows).toEqual(expect.arrayContaining([
      expect.objectContaining({ entityId: distantGroupLessonId }),
    ]));
    expect(check?.rows).not.toEqual(expect.arrayContaining([
      expect.objectContaining({ entityId: distantIndividualLessonId }),
    ]));
  });
});
