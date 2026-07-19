import { promises as fs } from "node:fs";
import * as path from "node:path";

describe("0073 rejected CRM fields migration", () => {
  const migration = (suffix: "up" | "down") =>
    path.resolve(
      process.cwd(),
      "db",
      "migrations",
      `0073_remove_rejected_crm_fields.${suffix}.sql`,
    );

  it("removes only the rejected keys from the persisted field schema", async () => {
    const sql = await fs.readFile(migration("up"), "utf8");

    expect(sql).toContain("update app.system_settings");
    expect(sql).toContain("crm_custom_fields");
    expect(sql).toContain("workplace");
    expect(sql).toContain("position");
    expect(sql).toContain("individualPrice");
    expect(sql).not.toContain("update app.students");
    expect(sql).not.toContain("update app.leads");
  });

  it("documents the intentionally data-preserving rollback", async () => {
    const sql = await fs.readFile(migration("down"), "utf8");

    expect(sql).toContain("Intentionally irreversible");
    expect(sql).toContain("students.custom_data values were never deleted");
  });
});
