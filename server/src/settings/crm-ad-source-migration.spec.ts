import { promises as fs } from "node:fs";
import * as path from "node:path";

describe("0069 crm ad-source migration", () => {
  const migration = (suffix: "up" | "down") =>
    path.resolve(
      process.cwd(),
      "db",
      "migrations",
      `0069_crm_ad_source_field.${suffix}.sql`,
    );

  it("is update-only for settings and preserves legacy source values idempotently", async () => {
    const sql = await fs.readFile(migration("up"), "utf8");
    expect(sql).toContain("update app.students");
    expect(sql).toContain("update app.leads");
    expect(sql).toContain("jsonb_set");
    expect(sql).toContain("custom_data->>'adSource'");
    expect(sql).toContain("is null");
    expect(sql).toContain("update app.system_settings");
    expect(sql).not.toContain("insert into app.system_settings");
    expect(sql).not.toMatch(/custom_data\s*-\s*'source'/);
  });

  it("documents why rollback intentionally preserves the normalized data", async () => {
    const sql = await fs.readFile(migration("down"), "utf8");
    expect(sql).toContain("Intentionally irreversible");
    expect(sql).toContain("source -> adSource");
  });
});
