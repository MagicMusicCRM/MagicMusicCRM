import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import {
  LessonCompletionClaim,
  LessonCompletionResultRef,
} from "./completion-worker.types";
import { LessonCompletionWorkerRepository } from "./completion-worker.repository";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";

@Injectable()
export class LessonCompletionService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly work: LessonCompletionWorkerRepository,
    private readonly settlement: LessonSettlementService,
    private readonly reservations: SubscriptionReservationService,
    private readonly lifecycle: LessonLifecycleRepository,
  ) {}

  async complete(claim: LessonCompletionClaim) {
    const result =
      await this.platform.executeVersionedMutation<LessonCompletionResultRef>({
        actorKey: "worker:lesson-completion",
        operation: "schedule.lesson.complete-settlement",
        idempotencyKey: `lesson-settlement-complete:${claim.lessonId}`,
        payload: {
          lessonId: claim.lessonId,
          scheduledEndAt: claim.scheduledEndAt.toISOString(),
        },
        aggregateType: "schedule:lesson",
        aggregateId: claim.lessonId,
        expectedVersion: claim.lessonVersion,
        requestId: `lesson-settlement-complete:${claim.lessonId}`,
        audit: {
          action: "crm.lesson_settlement_completed",
          entityType: "lesson",
          entityId: claim.lessonId,
          reason: "worker.end-at-reached",
          beforeRef: {
            lessonId: claim.lessonId,
            version: claim.lessonVersion,
            state: "scheduled",
          },
          metadata: { worker: "lesson-completion", plannedDecision: true },
        },
        outbox: {
          type: "schedule.lesson.changed",
          payload: {
            entityId: claim.lessonId,
            state: "successfully_completed",
          },
        },
        mutate: (client, nextVersion) =>
          this.completeInTransaction(client, claim, nextVersion),
      });
    return result;
  }

  markReviewRequired(claim: LessonCompletionClaim, failureCode: string) {
    return this.platform.executeVersionedMutation<LessonCompletionResultRef>({
      actorKey: "worker:lesson-completion",
      operation: "schedule.lesson.settlement-review-required",
      idempotencyKey: `lesson-settlement-review:${claim.lessonId}`,
      payload: { lessonId: claim.lessonId, failureCode },
      aggregateType: "schedule:lesson",
      aggregateId: claim.lessonId,
      expectedVersion: claim.lessonVersion,
      requestId: `lesson-settlement-review:${claim.lessonId}`,
      audit: {
        action: "crm.lesson_settlement_review_required",
        entityType: "lesson",
        entityId: claim.lessonId,
        reason: failureCode,
        beforeRef: {
          lessonId: claim.lessonId,
          version: claim.lessonVersion,
          state: "scheduled",
        },
        metadata: { worker: "lesson-completion" },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { entityId: claim.lessonId, state: "settlement_pending" },
      },
      mutate: async (client, nextVersion) => {
        const source = await this.work.lockPoisonAndLesson(client, claim);
        if (source.lifecycle_state !== "scheduled" ||
            Number(source.version) !== claim.lessonVersion) {
          throw completionError("LESSON_COMPLETION_STALE_VERSION");
        }
        const updated = await client.query<{ version: number | string }>(
          `update app.lessons
           set lifecycle_state = 'settlement_pending', updated_at = now()
           where id = $1 and version = $2 and lifecycle_state = 'scheduled'
           returning version`,
          [claim.lessonId, claim.lessonVersion],
        );
        if (!updated.rows[0] || Number(updated.rows[0].version) !== nextVersion) {
          throw completionError("LESSON_COMPLETION_STALE_VERSION");
        }
        const plan = await this.settlement.loadPlan(client, claim.lessonId, true);
        if (plan?.state === "planned") {
          await this.settlement.markPlanState(
            client,
            claim.lessonId,
            "review_required",
            failureCode,
          );
        }
        await this.work.markReviewRequired(client, claim);
        return { lessonId: claim.lessonId, state: "settlement_pending" };
      },
    });
  }

  private async completeInTransaction(
    client: PoolClient,
    claim: LessonCompletionClaim,
    nextVersion: number,
  ): Promise<LessonCompletionResultRef> {
    const source = await this.work.lockClaimAndLesson(client, claim);
    if (source.lifecycle_state !== "scheduled") {
      throw completionError("LESSON_COMPLETION_TERMINAL_GUARD");
    }
    if (Number(source.version) !== claim.lessonVersion) {
      throw completionError("LESSON_COMPLETION_STALE_VERSION");
    }
    const plan = await this.settlement.loadPlan(client, claim.lessonId, true);
    if (!plan || plan.state !== "planned") {
      throw completionError("LESSON_SETTLEMENT_PLAN_MISSING");
    }
    const updated = await client.query<{ version: number | string }>(
      `
        update app.lessons
        set lifecycle_state = 'successfully_completed',
            updated_at = now()
        where id = $1
          and version = $2
          and lifecycle_state = 'scheduled'
          and scheduled_at + make_interval(mins => duration_minutes) <= now()
        returning version
      `,
      [claim.lessonId, claim.lessonVersion],
    );
    if (
      !updated.rows[0] ||
      Number(updated.rows[0].version) !== nextVersion
    ) {
      throw completionError("LESSON_COMPLETION_STALE_VERSION");
    }

    const settled = await this.settlement.settle(client, claim.lessonId, {
      context: "settle",
      decision: plan.decision,
      reasonText: plan.reasonText ?? undefined,
      configurationRevisionIds: {
        settlementRevisionId: plan.settlementRevisionId,
        compensationRevisionId: plan.compensationRevisionId,
      },
    });
    await this.reservations.terminalize(client, settled);
    const transition = await this.lifecycle.appendTransition(client, {
      lessonId: claim.lessonId,
      fromState: "scheduled",
      toState: "successfully_completed",
      reasonCode: "worker.end-at-reached",
      reasonText: plan.reasonText ?? undefined,
      workerId: claim.workerId,
      financialDecision: { ...plan.decision },
      clientFinancialFactId: settled.clientFact.id,
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
    });
    const result = {
      transitionId: String(transition.rows[0]!.id),
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
    };
    await this.settlement.markPlanState(client, claim.lessonId, "settled");
    await this.work.markCompleted(client, claim, result);
    return {
      lessonId: claim.lessonId,
      state: "successfully_completed",
      ...result,
    };
  }

}

function completionError(code: string): Error {
  const error = new Error(code);
  error.name = code;
  return error;
}
