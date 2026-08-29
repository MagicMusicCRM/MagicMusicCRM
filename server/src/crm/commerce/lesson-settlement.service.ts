import { ConflictException, Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  LessonSettlementPort,
  LessonFinancialDecision,
  LessonSettlementInput,
  LessonSettlementResult,
  PreparedLessonSettlementPlan,
} from "./lesson-settlement.port";
import { settleLesson } from "./lesson-settlement-execution";
import { loadLessonSettlementCatalog } from "./lesson-settlement-catalog";
import {
  assignLessonSettlementPlan,
  cloneLessonSettlementPlan,
  loadLessonSettlementPlan,
  markLessonSettlementPlanState,
  plannedLessonSubscriptionAllocations,
  prepareLessonSettlementPlan,
  replaceLessonSettlementPlan,
} from "./lesson-settlement-plan.persistence";

@Injectable()
export class LessonSettlementService implements LessonSettlementPort {
  constructor(private readonly database: DatabaseService) {}

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

  preparePlan(
    client: PoolClient,
    branchId: string,
    decision: LessonFinancialDecision,
  ): Promise<PreparedLessonSettlementPlan> {
    return prepareLessonSettlementPlan(client, branchId, decision);
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
    return {
      ...decision,
      teacherCompensationRuleKey: current.decision.teacherCompensationRuleKey,
      ...(current.decision.teacherCompensationValueMinor === undefined
        ? { teacherCompensationValueMinor: undefined }
        : {
            teacherCompensationValueMinor:
              current.decision.teacherCompensationValueMinor,
          }),
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
