import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const migration = (suffix: "up" | "down") =>
  readFileSync(
    resolve(
      __dirname,
      "../../../db/migrations",
      `0148_teacher_compensation_fact_source.${suffix}.sql`,
    ),
    "utf8",
  );

describe("teacher compensation source migration", () => {
  it("adds nullable immutable provenance without guessing historical values", () => {
    const source = migration("up");
    expect(source).toMatch(
      /add\s+column\s+if\s+not\s+exists\s+compensation_source\s+text/iu,
    );
    expect(source).toMatch(
      /compensation_source\s+is\s+null[\s\S]*'automatic'[\s\S]*'manual'/iu,
    );
    expect(source).toMatch(
      /create\s+or\s+replace\s+view\s+app\.lesson_teacher_compensation_facts_effective/iu,
    );
    expect(source).not.toMatch(
      /update\s+app\.lesson_teacher_compensation_facts/iu,
    );
  });

  it("refuses rollback after explicit provenance has been written", () => {
    const source = migration("down");
    const lock = source.indexOf(
      "lock table app.lesson_teacher_compensation_facts in share row exclusive mode",
    );
    const guard = source.indexOf("compensation_source is not null");
    const drop = source.indexOf("drop column if exists compensation_source");
    expect(lock).toBeGreaterThanOrEqual(0);
    expect(guard).toBeGreaterThan(lock);
    expect(guard).toBeGreaterThan(0);
    expect(drop).toBeGreaterThan(guard);
    expect(source).toMatch(
      /create\s+view\s+app\.lesson_teacher_compensation_facts_effective/iu,
    );
    expect(source).not.toMatch(
      /update\s+app\.lesson_teacher_compensation_facts/iu,
    );
  });
});
