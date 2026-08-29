import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const migration = (suffix: "up" | "down") =>
  readFileSync(
    resolve(
      __dirname,
      "../../../db/migrations",
      `0142_schedule_plan_series_subscription_snapshot.${suffix}.sql`,
    ),
    "utf8",
  );

describe("schedule Plan series subscription snapshot migration", () => {
  it("keeps old application inserts nullable while validating new snapshots", () => {
    const source = migration("up");
    expect(source).not.toMatch(/add\s+column/iu);
    expect(source).toMatch(
      /plan_kind\s*=\s*'individual'\s+and\s+new\.subscription_id\s+is\s+not\s+null/iu,
    );
    expect(source).toMatch(
      /old\.subscription_id\s+is\s+not\s+null[\s\S]*new\.subscription_id\s+is\s+distinct\s+from\s+old\.subscription_id/iu,
    );
    expect(source).not.toMatch(/schedule_plan_series_subscription_repairs/iu);
    expect(source).not.toMatch(/update\s+app\.schedule_series/iu);
  });

  it("refuses schema rollback after any new snapshot without rewriting data", () => {
    const source = migration("down");
    const guard = source.indexOf("rollback is unsafe");
    const schemaChange = source.indexOf(
      "drop constraint if exists schedule_series_template_shape_check",
    );
    expect(guard).toBeGreaterThan(0);
    expect(schemaChange).toBeGreaterThan(guard);
    expect(source).toMatch(
      /series\.plan_id\s+is\s+not\s+null\s+and\s+series\.subscription_id\s+is\s+not\s+null/iu,
    );
    expect(source).not.toMatch(/update\s+app\.schedule_series/iu);
    expect(source).not.toMatch(/delete\s+from\s+app\.schedule_series/iu);
  });
});
