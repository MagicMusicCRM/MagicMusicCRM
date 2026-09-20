import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import type { PoolClient } from "pg";
import { loadLessonSettlementCatalog } from "./commerce/lesson-settlement-catalog";

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
    stableKey: "paid_miss",
    label: "Оплачиваемый пропуск",
    colorToken: "blue",
    hourShareBasisPoints: 10_000,
    allowedContexts: ["cancel", "reschedule", "settle"],
    active: true,
    order: 3,
  },
  {
    stableKey: "partially_paid_miss",
    label: "Частично оплачиваемый пропуск",
    colorToken: "cyan",
    hourShareBasisPoints: 5_000,
    allowedContexts: ["cancel", "reschedule", "settle"],
    active: true,
    order: 4,
  },
  {
    stableKey: "unpaid_miss",
    label: "Неоплачиваемый пропуск",
    colorToken: "neutral",
    hourShareBasisPoints: 0,
    allowedContexts: ["cancel", "reschedule", "settle"],
    active: true,
    order: 5,
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

const legacyCompensationRules = [
  { stableKey: "none", label: "Не оплачивать", mode: "none", value: "0", active: true, order: 0 },
  { stableKey: "standard", label: "Полная ставка", mode: "standard", value: "0", active: true, order: 1 },
  { stableKey: "percent", label: "Процент", mode: "percent", value: "10000", active: true, order: 2 },
  { stableKey: "fixed", label: "Фиксированная", mode: "fixed", value: "0", active: true, order: 3 },
  { stableKey: "hourly", label: "Почасовая", mode: "hourly", value: "0", active: true, order: 4 },
];

const legacySnapshot = (lessonSettlementTypes = legacySettlementTypes) => ({
  categories: [],
  fields: [],
  optionSets: [],
  businessSettings: [],
  lessonSettlementTypes,
  teacherCompensationRules: legacyCompensationRules,
});

async function createConfigurationDatabase(): Promise<PGlite> {
  const db = new PGlite();
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
  return db;
}

async function insertSchoolSnapshot(
  db: PGlite,
  snapshot: ReturnType<typeof legacySnapshot>,
): Promise<void> {
  await db.query(
    `insert into app.crm_configuration_revisions (
       branch_id, version, patch, effective_snapshot, impact, reason
     ) values (null, 1, $1::jsonb, $1::jsonb, '{"seed":true}', '0109')`,
    [JSON.stringify(snapshot)],
  );
}

describe("lesson settlement policy revision migration", () => {
  it("appends a normalized revision to the 0109 shape and keeps the old row", async () => {
    const db = await createConfigurationDatabase();
    try {
      const snapshot = legacySnapshot();
      await insertSchoolSnapshot(db, snapshot);
      await db.query(
        "insert into app.crm_configuration_drafts (snapshot) values ($1::jsonb)",
        [JSON.stringify(snapshot)],
      );

      await db.exec(migration("up"));

      const revisions = await db.query<{
        version: string;
        effective_snapshot: typeof snapshot;
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
        snapshot: typeof snapshot;
      }>("select snapshot from app.crm_configuration_drafts");
      expect(draft.rows[0]!.snapshot.lessonSettlementTypes).toEqual(
        currentTypes,
      );
    } finally {
      await db.close();
    }
  });

  it("maps every approved policy by stable key when school hour shares were customized", async () => {
    const db = await createConfigurationDatabase();
    try {
      const customized = legacySettlementTypes.map((type) => ({
        ...type,
        hourShareBasisPoints: type.hourShareBasisPoints === 0 ? 10_000 : 0,
      }));
      await insertSchoolSnapshot(db, legacySnapshot(customized));

      await db.exec(migration("up"));

      const result = await db.query<{
        effective_snapshot: ReturnType<typeof legacySnapshot>;
      }>(
        `select effective_snapshot from app.crm_configuration_revisions
         where branch_id is null order by version desc limit 1`,
      );
      const policies = new Map(
        result.rows[0]!.effective_snapshot.lessonSettlementTypes.map((type) => [
          type.stableKey,
          type,
        ]),
      );
      expect(policies.get("lesson")).toMatchObject({
        clientDurationMode: "full",
        teacherDurationMode: "full",
        defaultTeacherCompensationRuleKey: "standard",
      });
      expect(policies.get("partially_paid_lesson")).toMatchObject({
        clientDurationMode: "manual",
        teacherDurationMode: "manual",
        defaultTeacherCompensationRuleKey: "percent",
      });
      expect(policies.get("free_lesson")).toMatchObject({
        clientDurationMode: "zero",
        teacherDurationMode: "zero",
        defaultTeacherCompensationRuleKey: "none",
      });
      expect(policies.get("paid_miss")).toMatchObject({
        clientDurationMode: "full",
        teacherDurationMode: "full",
        defaultTeacherCompensationRuleKey: "standard",
      });
      expect(policies.get("partially_paid_miss")).toMatchObject({
        clientDurationMode: "manual",
        teacherDurationMode: "manual",
        defaultTeacherCompensationRuleKey: "percent",
      });
      expect(policies.get("unpaid_miss")).toMatchObject({
        clientDurationMode: "zero",
        teacherDurationMode: "zero",
        defaultTeacherCompensationRuleKey: "none",
      });
      expect(policies.get("penalty_lesson")).toMatchObject({
        clientDurationMode: "full",
        teacherDurationMode: "full",
        defaultTeacherCompensationRuleKey: "standard",
        active: false,
      });
    } finally {
      await db.close();
    }
  });

  it("ignores legacy branch catalog patches for effective decisions but keeps frozen revisions readable", async () => {
    const db = await createConfigurationDatabase();
    try {
      const school = legacySnapshot();
      await insertSchoolSnapshot(db, school);
      const branchId = "00000000-0000-4000-8000-000000000149";
      const branchTypes = legacySettlementTypes.map((type) =>
        type.stableKey === "lesson"
          ? { ...type, label: "Филиальный патч", hourShareBasisPoints: 0 }
          : type,
      );
      const branchPatch = {
        lessonSettlementTypes: branchTypes,
        teacherCompensationRules: legacyCompensationRules,
      };
      const branchSnapshot = legacySnapshot(branchTypes);
      const inserted = await db.query<{ id: string }>(
        `insert into app.crm_configuration_revisions (
           branch_id, version, patch, effective_snapshot, impact, reason
         ) values ($1, 1, $2::jsonb, $3::jsonb, '{}', 'legacy branch')
         returning id`,
        [branchId, JSON.stringify(branchPatch), JSON.stringify(branchSnapshot)],
      );

      await db.exec(migration("up"));

      const frozen = await loadLessonSettlementCatalog(
        db as unknown as PoolClient,
        branchId,
        {
          settlementRevisionId: inserted.rows[0]!.id,
          compensationRevisionId: inserted.rows[0]!.id,
        },
      );
      expect(frozen.settlement_types.find((type) => type.stableKey === "lesson"))
        .toMatchObject({ label: "Филиальный патч", hourShareBasisPoints: 0 });

      const effective = await loadLessonSettlementCatalog(
        db as unknown as PoolClient,
        branchId,
      );
      expect(effective.settlement_types.find((type) => type.stableKey === "lesson"))
        .toMatchObject({
          label: "Занятие",
          clientDurationMode: "full",
          teacherDurationMode: "full",
          defaultTeacherCompensationRuleKey: "standard",
        });
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
