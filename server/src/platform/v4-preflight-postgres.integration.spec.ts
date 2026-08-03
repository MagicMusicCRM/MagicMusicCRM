import { randomUUID } from "crypto";
import { Pool } from "pg";
import { runPreflight } from "./v4-preflight";

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? process.env.DATABASE_URL
  ?? "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";

describe("T8.1.3 workflow preflight", () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 2 });
  const entityId = randomUUID();
  const openTaskId = randomUUID();
  const doneTaskId = randomUUID();

  beforeAll(async () => {
    await pool.query(
      `insert into app.tasks (id, entity_type, entity_id, title, status)
       values
         ($1, 'lead', $3, 'Open fixture', 'open'),
         ($2, 'lead', $3, 'Done fixture', 'done')`,
      [openTaskId, doneTaskId, entityId],
    );
  });

  afterAll(async () => {
    await pool.query("delete from app.tasks where id = any($1::uuid[])", [
      [openTaskId, doneTaskId],
    ]);
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
});
