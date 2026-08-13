import { readFileSync } from "node:fs";
import { resolve } from "node:path";

describe("canonical Client migration contracts", () => {
  const migration = (name: string) =>
    readFileSync(resolve(process.cwd(), "db/migrations", name), "utf8");

  it("preserves configured option order while merging legacy field copies", () => {
    const sql = migration("0133_canonical_client_fields.up.sql");

    expect(sql).toContain("with ordinality option(value, ordinality)");
    expect(sql).toContain(
      "option_label order by merge_rank, option_order, option_label",
    );
    expect(sql).not.toContain("jsonb_agg(option_label order by option_label)");
  });

  it("keeps canonical identity correct after either projection is deleted", () => {
    const up = migration("0134_canonical_clients.up.sql");
    const down = migration("0134_canonical_clients.down.sql");

    expect(up).toContain("references app.clients(id) on delete cascade");
    expect(up).toContain("cleanup_canonical_client_identity_trigger");
    expect(up).toContain("after delete on app.leads");
    expect(up).toContain("after delete on app.students");
    expect(up).toContain(
      "enable always trigger leads_cleanup_canonical_client",
    );
    expect(up).toContain(
      "enable always trigger students_cleanup_canonical_client",
    );
    expect(up).toContain("perform app.refresh_canonical_client_identity");
    expect(up).toContain("delete from app.client_custom_field_values value");
    expect(up).toContain("delete from app.clients client");
    expect(down).toContain(
      "drop trigger if exists students_cleanup_canonical_client",
    );
    expect(down).toContain(
      "drop trigger if exists leads_cleanup_canonical_client",
    );
    expect(down).toContain(
      "drop function if exists app.cleanup_canonical_client_identity_trigger()",
    );
  });
});
