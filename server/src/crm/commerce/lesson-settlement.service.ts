import { Injectable } from "@nestjs/common";
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
      this.settle(client, lessonId, input));
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
    return markLessonSettlementPlanState(
      client,
      lessonId,
      state,
      failureCode,
    );
  }

  plannedSubscriptionAllocations(
    client: PoolClient,
    lessonId: string,
    plan: PreparedLessonSettlementPlan,
  ) {
    return plannedLessonSubscriptionAllocations(
      client,
      lessonId,
      plan,
    );
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
}
