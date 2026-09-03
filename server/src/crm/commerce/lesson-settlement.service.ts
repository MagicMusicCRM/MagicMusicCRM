import {
  ConflictException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import type { CrmPolicy } from "../crm.policy";
import {
  LessonSettlementPort,
  LessonFinancialDecision,
  LessonSettlementInput,
  LessonSettlementResult,
  PreparedLessonSettlementPlan,
} from "./lesson-settlement.port";
import { previewLessonSettlement, settleLesson } from "./lesson-settlement-execution";
import {
  invalidLessonSettlementDecision,
  loadLessonSettlementCatalog,
} from "./lesson-settlement-catalog";
import {
  durationShareBasisPoints,
  LessonSettlementCalculationError,
} from "./lesson-settlement.calculation";
import { resolveSettlementPolicy } from "./lesson-settlement-policy";
import {
  assignLessonSettlementPlan,
  cloneLessonSettlementPlan,
  loadLessonSettlementPlan,
  markLessonSettlementPlanState,
  plannedLessonSubscriptionAllocations,
  prepareLessonSettlementPlan,
  prepareLessonSettlementPlanWithCatalog,
  replaceLessonSettlementPlan,
} from "./lesson-settlement-plan.persistence";

export type TeacherCompensationMutationAuthorization = ReturnType<
  CrmPolicy["teacherCompensationMutationAuthorization"]
>;

type PreservedTeacherDecision = Pick<
  LessonFinancialDecision,
  | "teacherCompensationRuleKey"
  | "teacherCompensationValueMinor"
  | "teacherCreditedDurationMinutes"
  | "teacherCompensationSource"
>;

interface ResolvePlannedDecisionInput {
  branchId: string;
  durationMinutes: number;
  decision: LessonFinancialDecision;
  actorUserId: string;
  authorization: TeacherCompensationMutationAuthorization;
  reasonText?: string;
  preservedTeacherDecision?: PreservedTeacherDecision;
  requiredClientIds?: string[];
  configurationRevisionIds?: NonNullable<
    LessonSettlementInput["configurationRevisionIds"]
  >;
}

@Injectable()
export class LessonSettlementService implements LessonSettlementPort {
  constructor(private readonly database: DatabaseService) {}

  preview(client: PoolClient, lessonId: string, input: LessonSettlementInput) {
    return previewLessonSettlement(client, lessonId, input);
  }

  settle(
    client: PoolClient,
    lessonId: string,
    input?: LessonSettlementInput,
  ): Promise<LessonSettlementResult> {
    return settleLesson(client, lessonId, input);
  }

  settleStandalone(
    lessonId: string,
    input?: LessonSettlementInput,
  ): Promise<LessonSettlementResult> {
    return this.database.transaction((client) =>
      this.settle(client, lessonId, input),
    );
  }

  async resolvePlannedDecision(
    client: PoolClient,
    input: ResolvePlannedDecisionInput,
  ): Promise<LessonFinancialDecision> {
    this.assertPlannedActor(input);
    assertExactClientDecisions(input.decision, input.requiredClientIds);
    const catalog = await loadLessonSettlementCatalog(
      client,
      input.branchId,
      input.configurationRevisionIds,
    );
    return this.resolvePlannedDecisionWithCatalog(catalog, input);
  }

  async resolvePlannedPlan(
    client: PoolClient,
    input: ResolvePlannedDecisionInput,
  ): Promise<PreparedLessonSettlementPlan> {
    this.assertPlannedActor(input);
    assertExactClientDecisions(input.decision, input.requiredClientIds);
    const catalog = await loadLessonSettlementCatalog(
      client,
      input.branchId,
      input.configurationRevisionIds,
    );
    const decision = this.resolvePlannedDecisionWithCatalog(catalog, input);
    return prepareLessonSettlementPlanWithCatalog(
      client,
      catalog,
      decision,
      input.actorUserId,
    );
  }

  private assertPlannedActor(input: ResolvePlannedDecisionInput): void {
    if (input.authorization.actor.userId !== input.actorUserId) {
      throw new ForbiddenException({
        code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED",
      });
    }
  }

  private resolvePlannedDecisionWithCatalog(
    catalog: Awaited<ReturnType<typeof loadLessonSettlementCatalog>>,
    input: ResolvePlannedDecisionInput,
  ): LessonFinancialDecision {
    assertDurationWithinLesson(
      input.durationMinutes,
      input.durationMinutes,
      "durationMinutes",
    );
    const clientDecisions = input.decision.clientDecisions?.map((decision) => {
      const policy = resolveSettlementPolicy(
        catalog,
        decision.settlementTypeKey ?? input.decision.settlementTypeKey,
      );
      if (
        policy.clientDurationMode === "manual" &&
        decision.chargeDurationMinutes === undefined
      ) {
        invalidLessonSettlementDecision(
          "CLIENT_PARTIAL_DURATION_REQUIRED",
          `clientDecisions.${decision.clientId}.chargeDurationMinutes`,
        );
      }
      const chargeDurationMinutes = resolveDurationMinutes(
        policy.clientDurationMode,
        input.durationMinutes,
        decision.chargeDurationMinutes,
      );
      assertDurationWithinLesson(
        chargeDurationMinutes,
        input.durationMinutes,
        `clientDecisions.${decision.clientId}.chargeDurationMinutes`,
      );
      return { ...decision, chargeDurationMinutes };
    });
    const decision = {
      ...input.decision,
      ...(clientDecisions ? { clientDecisions } : {}),
    };
    if (input.preservedTeacherDecision) {
      if (
        input.preservedTeacherDecision.teacherCreditedDurationMinutes !==
        undefined
      ) {
        assertDurationWithinLesson(
          input.preservedTeacherDecision.teacherCreditedDurationMinutes,
          input.durationMinutes,
          "teacherCreditedDurationMinutes",
        );
      }
      return { ...decision, ...input.preservedTeacherDecision };
    }
    return this.resolveTeacherDecision(catalog, input, decision);
  }

  async partialDurationWarnings(
    client: PoolClient,
    input: {
      branchId: string;
      durationMinutes: number;
      decision: LessonFinancialDecision;
      configurationRevisionIds?: NonNullable<
        LessonSettlementInput["configurationRevisionIds"]
      >;
    },
  ): Promise<string[]> {
    const catalog = await loadLessonSettlementCatalog(
      client,
      input.branchId,
      input.configurationRevisionIds,
    );
    const warnings = new Set<string>();
    for (const decision of input.decision.clientDecisions ?? []) {
      const policy = resolveSettlementPolicy(
        catalog,
        decision.settlementTypeKey ?? input.decision.settlementTypeKey,
      );
      if (policy.clientDurationMode === "manual") {
        addDurationBoundaryWarning(
          warnings,
          "CLIENT",
          decision.chargeDurationMinutes,
          input.durationMinutes,
        );
      }
    }
    const teacherPolicy = resolveSettlementPolicy(
      catalog,
      input.decision.settlementTypeKey,
    );
    if (
      input.decision.teacherCreditedDurationMinutes !== undefined &&
      (teacherPolicy.teacherDurationMode === "manual" ||
        input.decision.teacherCompensationSource !== "automatic")
    ) {
      addDurationBoundaryWarning(
        warnings,
        "TEACHER",
        input.decision.teacherCreditedDurationMinutes,
        input.durationMinutes,
      );
    }
    return [...warnings];
  }

  private resolveTeacherDecision(
    catalog: Awaited<ReturnType<typeof loadLessonSettlementCatalog>>,
    input: {
      durationMinutes: number;
      decision: LessonFinancialDecision;
      authorization: TeacherCompensationMutationAuthorization;
      reasonText?: string;
    },
    decision: LessonFinancialDecision,
  ): LessonFinancialDecision {
    const policy = resolveSettlementPolicy(
      catalog,
      decision.settlementTypeKey,
    );
    if (
      !decision.teacherCompensationRuleKey ||
      !catalog.compensation_rules.some(
        (rule) =>
          rule.active &&
          rule.stableKey === decision.teacherCompensationRuleKey,
      )
    ) {
      invalidLessonSettlementDecision(
        "TEACHER_COMPENSATION_RULE_NOT_FOUND",
        "teacherCompensationRuleKey",
      );
    }
    if (
      policy.teacherDurationMode === "manual" &&
      decision.teacherCreditedDurationMinutes === undefined
    ) {
      invalidLessonSettlementDecision(
        "TEACHER_PARTIAL_DURATION_REQUIRED",
        "teacherCreditedDurationMinutes",
      );
    }
    const recommendedMinutes = policy.teacherDurationMode === "manual"
      ? undefined
      : resolveDurationMinutes(
          policy.teacherDurationMode,
          input.durationMinutes,
          undefined,
        );
    const legacyAutomatic = decision.teacherCompensationSource === undefined &&
      policy.teacherDurationMode !== "manual" &&
      decision.teacherCompensationValueMinor === undefined &&
      decision.teacherCreditedDurationMinutes === undefined &&
      (decision.teacherCompensationRuleKey === "standard" ||
        decision.teacherCompensationRuleKey ===
          policy.teacherCompensationRuleKey);
    const manual = !legacyAutomatic && (
      policy.teacherDurationMode === "manual" ||
      decision.teacherCompensationSource === "manual" ||
      decision.teacherCompensationRuleKey !==
        policy.teacherCompensationRuleKey ||
      decision.teacherCompensationValueMinor !== undefined ||
      decision.teacherCreditedDurationMinutes !== recommendedMinutes
    );
    if (!manual) {
      return {
        ...decision,
        teacherCompensationRuleKey: policy.teacherCompensationRuleKey,
        teacherCompensationValueMinor: undefined,
        teacherCreditedDurationMinutes: recommendedMinutes,
        teacherCompensationSource: "automatic",
      };
    }
    if (input.authorization.capabilityKey !== "config.commerce.manage") {
      throw new ForbiddenException({
        code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED",
      });
    }
    if (!input.reasonText?.trim()) {
      invalidLessonSettlementDecision(
        "TEACHER_COMPENSATION_REASON_REQUIRED",
        "reasonText",
      );
    }
    const requestedMinutes = decision.teacherCreditedDurationMinutes;
    if (requestedMinutes !== undefined) {
      assertDurationWithinLesson(
        requestedMinutes,
        input.durationMinutes,
        "teacherCreditedDurationMinutes",
      );
    }
    const derivePercent = policy.teacherDurationMode === "manual" ||
      (requestedMinutes !== undefined && requestedMinutes !== recommendedMinutes);
    if (derivePercent) {
      const percentRule = catalog.compensation_rules.find(
        (rule) =>
          rule.active &&
          rule.mode === "percent" &&
          (rule.stableKey === policy.teacherCompensationRuleKey ||
            policy.teacherDurationMode !== "manual"),
      );
      if (!percentRule) {
        invalidLessonSettlementDecision(
          "TEACHER_COMPENSATION_RULE_NOT_FOUND",
          "teacherCompensationRuleKey",
        );
      }
      return {
        ...decision,
        teacherCompensationRuleKey: percentRule.stableKey,
        teacherCompensationValueMinor: durationShareBasisPoints(
          requestedMinutes!,
          input.durationMinutes,
        ).toString(),
        teacherCreditedDurationMinutes: requestedMinutes,
        teacherCompensationSource: "manual",
      };
    }
    const selectedRule = catalog.compensation_rules.find(
      (rule) =>
        rule.active && rule.stableKey === decision.teacherCompensationRuleKey,
    );
    return {
      ...decision,
      teacherCreditedDurationMinutes:
        requestedMinutes ?? creditedMinutesForRule(
          selectedRule?.mode,
          input.durationMinutes,
        ),
      teacherCompensationSource: "manual",
    };
  }

  preparePlan(
    client: PoolClient,
    branchId: string,
    decision: LessonFinancialDecision,
    actorUserId?: string,
  ): Promise<PreparedLessonSettlementPlan> {
    return prepareLessonSettlementPlan(client, branchId, decision, actorUserId);
  }

  assignPlan(
    client: PoolClient,
    input: {
      lessonId: string;
      branchId: string;
      decision: LessonFinancialDecision;
      selectedBy: string;
      reasonText?: string;
    },
  ) {
    return assignLessonSettlementPlan(client, input);
  }

  clonePlan(
    client: PoolClient,
    input: {
      sourceLessonId: string;
      targetLessonId: string;
      selectedBy: string;
      reasonText?: string;
      fallback?: {
        branchId: string;
        decision: LessonFinancialDecision;
      };
    },
  ) {
    return cloneLessonSettlementPlan(client, input);
  }

  loadPlan(client: PoolClient, lessonId: string, lock = false) {
    return loadLessonSettlementPlan(client, lessonId, lock);
  }

  markPlanState(
    client: PoolClient,
    lessonId: string,
    state: "settled" | "review_required" | "cancelled",
    failureCode?: string,
  ) {
    return markLessonSettlementPlanState(client, lessonId, state, failureCode);
  }

  plannedSubscriptionAllocations(
    client: PoolClient,
    lessonId: string,
    plan: PreparedLessonSettlementPlan,
  ) {
    return plannedLessonSubscriptionAllocations(client, lessonId, plan);
  }

  replacePlan(
    client: PoolClient,
    input: PreparedLessonSettlementPlan & {
      lessonId: string;
      expectedVersion: number;
      selectedBy: string;
      reasonText: string;
    },
  ) {
    return replaceLessonSettlementPlan(client, input);
  }

  async reuseStoredTeacherCompensation(
    client: PoolClient,
    lessonId: string,
    decision: LessonFinancialDecision,
  ): Promise<LessonFinancialDecision> {
    const current = await this.loadPlan(client, lessonId, true);
    if (!current) {
      throw new ConflictException({ code: "LESSON_SETTLEMENT_PLAN_MISSING" });
    }
    const correction = await client.query<{ decision: LessonFinancialDecision }>(
      `select decision from app.lesson_settlement_corrections
       where lesson_id = $1 order by version desc limit 1`, [lessonId],
    );
    const effective = correction.rows[0]?.decision ?? current.decision;
    return {
      ...decision,
      teacherCompensationRuleKey: effective.teacherCompensationRuleKey,
      ...(effective.teacherCompensationValueMinor === undefined
        ? { teacherCompensationValueMinor: undefined }
        : {
            teacherCompensationValueMinor:
              effective.teacherCompensationValueMinor,
          }),
      teacherCreditedDurationMinutes:
        effective.teacherCreditedDurationMinutes,
      teacherCompensationSource: effective.teacherCompensationSource,
    };
  }

  async applyDefaultTeacherCompensation(
    client: PoolClient,
    branchId: string,
    decision: LessonFinancialDecision,
  ): Promise<LessonFinancialDecision> {
    const catalog = await loadLessonSettlementCatalog(client, branchId);
    const activeRules = [...catalog.compensation_rules]
      .filter((candidate) => candidate.active)
      .sort((left, right) => left.order - right.order);
    const rule =
      activeRules.find((candidate) => candidate.stableKey === "standard") ??
      activeRules[0];
    if (!rule) {
      throw new ConflictException({
        code: "TEACHER_COMPENSATION_DEFAULT_MISSING",
      });
    }
    return {
      ...decision,
      teacherCompensationRuleKey: rule.stableKey,
      teacherCompensationValueMinor: undefined,
    };
  }
}

function resolveDurationMinutes(
  mode: "zero" | "full" | "manual",
  durationMinutes: number,
  selectedMinutes: number | undefined,
): number {
  if (mode === "zero") return 0;
  if (mode === "full") return durationMinutes;
  return selectedMinutes!;
}

function assertExactClientDecisions(
  decision: LessonFinancialDecision,
  requiredClientIds: string[] | undefined,
): void {
  if (requiredClientIds === undefined) return;
  const required = new Set(requiredClientIds);
  const seen = new Set<string>();
  for (const clientDecision of decision.clientDecisions ?? []) {
    if (seen.has(clientDecision.clientId)) {
      invalidLessonSettlementDecision(
        "DUPLICATE_CLIENT_DECISION",
        "clientDecisions",
      );
    }
    seen.add(clientDecision.clientId);
    if (!required.has(clientDecision.clientId)) {
      invalidLessonSettlementDecision(
        "UNKNOWN_LESSON_CLIENT",
        "clientDecisions",
      );
    }
  }
  if ([...required].some((clientId) => !seen.has(clientId))) {
    invalidLessonSettlementDecision(
      "CLIENT_DECISION_MISSING",
      "clientDecisions",
    );
  }
}

function assertDurationWithinLesson(
  selectedMinutes: number,
  durationMinutes: number,
  field: string,
): void {
  try {
    durationShareBasisPoints(selectedMinutes, durationMinutes);
  } catch (error) {
    if (error instanceof LessonSettlementCalculationError) {
      invalidLessonSettlementDecision(error.code, field);
    }
    throw error;
  }
}

function creditedMinutesForRule(
  mode: "none" | "standard" | "percent" | "fixed" | "hourly" | undefined,
  durationMinutes: number,
): number | undefined {
  if (mode === "none") return 0;
  if (mode === "standard" || mode === "fixed" || mode === "hourly") {
    return durationMinutes;
  }
  return undefined;
}

function addDurationBoundaryWarning(
  warnings: Set<string>,
  subject: "CLIENT" | "TEACHER",
  selectedMinutes: number | undefined,
  durationMinutes: number,
): void {
  if (selectedMinutes === 0) {
    warnings.add(`${subject}_ZERO_DURATION_SETTLEMENT_TYPE_RECOMMENDED`);
  } else if (selectedMinutes === durationMinutes) {
    warnings.add(`${subject}_FULL_DURATION_SETTLEMENT_TYPE_RECOMMENDED`);
  }
}
