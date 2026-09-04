import {
  ConflictException,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import type {
  LessonSettlementTypeConfig,
  TeacherCompensationRuleConfig,
} from "../crm-configuration.contracts";
import { LessonSettlementCalculationError } from "./lesson-settlement.calculation";
import type {
  LessonFinancialDecision,
  LessonSettlementInput,
} from "./lesson-settlement.port";

export interface LessonSettlementCatalog {
  settlement_revision_id: string;
  compensation_revision_id: string;
  settlement_types: LessonSettlementTypeConfig[];
  compensation_rules: TeacherCompensationRuleConfig[];
}

export type LessonSettlementRevisionIds = NonNullable<
  LessonSettlementInput["configurationRevisionIds"]
>;

export function invalidLessonSettlementDecision(
  code: string,
  field?: string,
): never {
  throw new UnprocessableEntityException({ code, field });
}

export function rethrowLessonSettlementCalculation(error: unknown): never {
  if (error instanceof LessonSettlementCalculationError) {
    invalidLessonSettlementDecision(error.code);
  }
  throw error;
}

export async function loadLessonSettlementCatalog(
  client: PoolClient,
  branchId: string,
  revisions?: LessonSettlementRevisionIds,
): Promise<LessonSettlementCatalog> {
  if (revisions) {
    return loadFrozenLessonSettlementCatalog(client, revisions);
  }
  return loadEffectiveLessonSettlementCatalog(client, branchId);
}

async function loadFrozenLessonSettlementCatalog(
  client: PoolClient,
  revisions: LessonSettlementRevisionIds,
): Promise<LessonSettlementCatalog> {
  const frozen = await client.query<LessonSettlementCatalog>(
    `select settlement.id as settlement_revision_id,
       compensation.id as compensation_revision_id,
       settlement.effective_snapshot->'lessonSettlementTypes'
         as settlement_types,
       compensation.effective_snapshot->'teacherCompensationRules'
         as compensation_rules
     from app.crm_configuration_revisions settlement
     join app.crm_configuration_revisions compensation
       on compensation.id = $2
     where settlement.id = $1`,
    [revisions.settlementRevisionId, revisions.compensationRevisionId],
  );
  const catalog = frozen.rows[0];
  assertLessonSettlementCatalog(
    catalog,
    "COMMERCE_CATALOG_REVISION_MISSING",
  );
  return catalog;
}

async function loadEffectiveLessonSettlementCatalog(
  client: PoolClient,
  _branchId: string,
): Promise<LessonSettlementCatalog> {
  const result = await client.query<LessonSettlementCatalog>(
    `
      with school as (
        select id, effective_snapshot
        from app.crm_configuration_revisions
        where branch_id is null order by version desc limit 1
      )
      select
        school.id as settlement_revision_id,
        school.id as compensation_revision_id,
        school.effective_snapshot->'lessonSettlementTypes'
          as settlement_types,
        school.effective_snapshot->'teacherCompensationRules'
          as compensation_rules
      from school
    `,
  );
  const catalog = result.rows[0];
  assertLessonSettlementCatalog(catalog, "COMMERCE_CATALOG_NOT_PUBLISHED");
  return catalog;
}

function assertLessonSettlementCatalog(
  catalog: LessonSettlementCatalog | undefined,
  code: string,
): asserts catalog is LessonSettlementCatalog {
  if (
    !catalog ||
    !Array.isArray(catalog.settlement_types) ||
    !Array.isArray(catalog.compensation_rules)
  ) {
    throw new ConflictException({ code });
  }
}

export function assertPlannedLessonSettlementDecision(
  catalog: LessonSettlementCatalog,
  decision: LessonFinancialDecision,
): void {
  const settlement = catalog.settlement_types.find(
    (item) => item.active && item.stableKey === decision.settlementTypeKey,
  );
  if (!settlement || !settlement.allowedContexts.includes("settle")) {
    invalidLessonSettlementDecision(
      "SETTLEMENT_TYPE_NOT_ALLOWED",
      "settlementTypeKey",
    );
  }
  const rule = catalog.compensation_rules.find(
    (item) =>
      item.active && item.stableKey === decision.teacherCompensationRuleKey,
  );
  if (!rule) {
    invalidLessonSettlementDecision(
      "TEACHER_COMPENSATION_RULE_NOT_FOUND",
      "teacherCompensationRuleKey",
    );
  }
  assertTeacherCompensationOverride(rule.mode, decision);
}

function assertTeacherCompensationOverride(
  mode: TeacherCompensationRuleConfig["mode"],
  decision: LessonFinancialDecision,
): void {
  const value = decision.teacherCompensationValueMinor;
  if (value !== undefined && !/^\d{1,19}$/.test(value)) {
    invalidLessonSettlementDecision(
      "INVALID_TEACHER_VALUE",
      "teacherCompensationValueMinor",
    );
  }
  if ((mode === "none" || mode === "standard") && value !== undefined) {
    invalidLessonSettlementDecision(
      "TEACHER_OVERRIDE_NOT_ALLOWED",
      "teacherCompensationValueMinor",
    );
  }
  if (mode === "percent" && value !== undefined && BigInt(value) > 20_000n) {
    invalidLessonSettlementDecision(
      "INVALID_TEACHER_PERCENT",
      "teacherCompensationValueMinor",
    );
  }
}
