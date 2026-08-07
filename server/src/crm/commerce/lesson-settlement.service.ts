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
import { LessonSettlementRepository } from "./lesson-settlement.repository";

@Injectable()
export class LessonSettlementService implements LessonSettlementPort {
  constructor(
    private readonly database: DatabaseService,
    private readonly repository: LessonSettlementRepository,
  ) {}

  settle(
    client: PoolClient,
    lessonId: string,
    input?: LessonSettlementInput,
  ): Promise<LessonSettlementResult> {
    return this.repository.settle(client, lessonId, input);
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
    return this.repository.preparePlan(client, branchId, decision);
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
    return this.repository.assignPlan(client, input);
  }

  loadPlan(client: PoolClient, lessonId: string, lock = false) {
    return this.repository.loadPlan(client, lessonId, lock);
  }

  markPlanState(
    client: PoolClient,
    lessonId: string,
    state: "settled" | "review_required" | "cancelled",
    failureCode?: string,
  ) {
    return this.repository.markPlanState(
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
    return this.repository.plannedSubscriptionAllocations(
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
    return this.repository.replacePlan(client, input);
  }
}
