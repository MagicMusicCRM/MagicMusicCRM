import { promises as fs } from "node:fs";
import * as path from "node:path";

describe("0072 demo workflow invariants migration", () => {
  const migrationsDir = path.resolve(process.cwd(), "db/migrations");

  it("adds lead homework, one-shot conversion and single active FCM ownership", async () => {
    const sql = await fs.readFile(
      path.join(migrationsDir, "0072_demo_workflow_invariants.up.sql"),
      "utf8",
    );

    expect(sql).toContain("add column if not exists lead_id");
    expect(sql).toContain("references app.leads(id) on delete cascade");
    expect(sql).not.toMatch(
      /add column if not exists lead_id uuid references app\.leads\(id\) on delete set null/,
    );
    expect(sql).toContain("num_nonnulls(student_id, lead_id) = 1");
    expect(sql).toContain("conversion_lead_id");
    expect(sql).toContain("subscriptions_conversion_lead_unique_idx");
    expect(sql).toContain("partition by token_hash");
    expect(sql).toContain("notification_devices_enabled_token_unique_idx");
    expect(sql).toMatch(/where enabled = true\s*;/);
  });

  it("refuses to destroy unconverted lead homework during rollback", async () => {
    const sql = await fs.readFile(
      path.join(migrationsDir, "0072_demo_workflow_invariants.down.sql"),
      "utf8",
    );

    expect(sql).toContain("where student_id is null");
    expect(sql).toContain("Cannot roll back 0072");
    expect(sql).not.toMatch(/delete\s+from\s+app\.lesson_homeworks/i);
  });
});
