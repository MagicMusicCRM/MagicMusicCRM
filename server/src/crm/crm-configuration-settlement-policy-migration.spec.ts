import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const migration = (suffix: "up" | "down") =>
  readFileSync(
    resolve(
      __dirname,
      "../../db/migrations",
      `0149_lesson_settlement_policy_revision.${suffix}.sql`,
    ),
    "utf8",
  );

const legacySettlementTypes = [
  {
    stableKey: "lesson",
    label: "Занятие",
    colorToken: "success",
    hourShareBasisPoints: 10_000,
    allowedContexts: ["settle"],
    active: true,
    order: 0,
  },
  {
    stableKey: "partially_paid_lesson",
    label: "Частично оплачиваемое занятие",
    colorToken: "info",
    hourShareBasisPoints: 5_000,
    allowedContexts: ["settle"],
    active: true,
    order: 1,
  },
  {
    stableKey: "free_lesson",
    label: "Бесплатное занятие",
    colorToken: "warning",
    hourShareBasisPoints: 0,
    allowedContexts: ["cancel", "reschedule", "settle"],
    active: true,
    order: 2,
  },
  {
    stableKey: "penalty_lesson",
    label: "Занятие со штрафом",
    colorToken: "violet",
    hourShareBasisPoints: 10_000,
    fixedPenaltyMinor: "0",
    allowedContexts: ["cancel", "reschedule", "settle"],
    active: true,
    order: 6,
  },
];

describe("lesson settlement policy revision migration", () => {
  it("appends a normalized revision to the 0109 shape and keeps the old row", async () => {
    const db = new PGlite();
    try {
      await db.exec(`
        create schema app;
        create table app.crm_configuration_revisions (
          id uuid primary key default gen_random_uuid(),
          branch_id uuid,
          version bigint not null,
          patch jsonb not null,
          effective_snapshot jsonb not null,
          impact jsonb not null default '{}'::jsonb,
          reason text not null
        );
        create table app.crm_configuration_drafts (
          id uuid primary key default gen_random_uuid(),
          snapshot jsonb not null
        );
      `);
      const legacySnapshot = {
        categories: [],
        fields: [],
        optionSets: [],
        businessSettings: [],
        lessonSettlementTypes: legacySettlementTypes,
        teacherCompensationRules: [],
      };
      await db.query(
        `insert into app.crm_configuration_revisions (
           branch_id, version, patch, effective_snapshot, impact, reason
         ) values (null, 1, $1::jsonb, $1::jsonb, '{"seed":true}', '0109')`,
        [JSON.stringify(legacySnapshot)],
      );
      await db.query(
        "insert into app.crm_configuration_drafts (snapshot) values ($1::jsonb)",
        [JSON.stringify(legacySnapshot)],
      );

      await db.exec(migration("up"));

      const revisions = await db.query<{
        version: string;
        effective_snapshot: typeof legacySnapshot;
      }>(
        `select version::text, effective_snapshot
         from app.crm_configuration_revisions order by version`,
      );
      expect(revisions.rows).toHaveLength(2);
      expect(revisions.rows[0]!.effective_snapshot.lessonSettlementTypes[0])
        .not.toHaveProperty("clientDurationMode");
      const currentTypes = revisions.rows[1]!.effective_snapshot
        .lessonSettlementTypes;
      expect(currentTypes).toEqual(expect.arrayContaining([
        expect.objectContaining({
          stableKey: "lesson",
          clientDurationMode: "full",
          teacherDurationMode: "full",
          defaultTeacherCompensationRuleKey: "standard",
        }),
        expect.objectContaining({
          stableKey: "partially_paid_lesson",
          clientDurationMode: "manual",
          teacherDurationMode: "manual",
          defaultTeacherCompensationRuleKey: "percent",
        }),
        expect.objectContaining({
          stableKey: "free_lesson",
          clientDurationMode: "zero",
          teacherDurationMode: "zero",
          defaultTeacherCompensationRuleKey: "none",
        }),
        expect.objectContaining({ stableKey: "penalty_lesson", active: false }),
      ]));
      const draft = await db.query<{
        snapshot: typeof legacySnapshot;
      }>("select snapshot from app.crm_configuration_drafts");
      expect(draft.rows[0]!.snapshot.lessonSettlementTypes).toEqual(
        currentTypes,
      );
    } finally {
      await db.close();
    }
  });

  it("refuses to delete the immutable forward revision", () => {
    expect(migration("down")).toMatch(
      /lesson settlement policy revision is immutable and cannot be rolled back/iu,
    );
  });
});
