import { Inject, Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  LESSON_SETTLEMENT_PORT,
  LessonSettlementPort,
} from "../commerce/lesson-settlement.port";
import {
  LessonCompletionClaim,
  LessonCompletionResultRef,
} from "./completion-worker.types";
import { LessonCompletionWorkerRepository } from "./completion-worker.repository";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";

@Injectable()
export class LessonCompletionService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly work: LessonCompletionWorkerRepository,
    private readonly lifecycle: LessonLifecycleRepository,
    @Inject(LESSON_SETTLEMENT_PORT)
    private readonly settlement: LessonSettlementPort,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  async complete(claim: LessonCompletionClaim) {
    const result =
      await this.platform.executeVersionedMutation<LessonCompletionResultRef>({
        actorKey: "worker:lesson-completion",
        operation: "schedule.lesson.complete",
        idempotencyKey: `lesson-completion:${claim.lessonId}`,
        payload: {
          lessonId: claim.lessonId,
          scheduledEndAt: claim.scheduledEndAt.toISOString(),
        },
        aggregateType: "schedule:lesson",
        aggregateId: claim.lessonId,
        expectedVersion: claim.lessonVersion,
        requestId: `lesson-completion:${claim.lessonId}`,
        audit: {
          action: "crm.lesson_completed",
          entityType: "lesson",
          entityId: claim.lessonId,
          reason: "worker.end-at-reached",
          beforeRef: {
            lessonId: claim.lessonId,
            version: claim.lessonVersion,
            state: "scheduled",
          },
          metadata: { worker: "lesson-completion" },
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
    if (!result.replayed) {
      await this.reservations.publishLessonSettlementPostCommit(
        claim.lessonId,
      );
    }
    return result;
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
    await this.reservations.lockSettlementCoverage(client, claim.lessonId);
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

    const settled = await this.settlement.settle(client, claim.lessonId);
    await this.reservations.terminalize(client, settled);
    const transition = await this.lifecycle.appendTransition(client, {
      lessonId: claim.lessonId,
      toState: "successfully_completed",
      reasonCode: "worker.end-at-reached",
      workerId: claim.workerId,
      financialDecision: {
        chargeClient: settled.clientFacts.some(
          (fact) => fact.chargeType !== "none",
        ),
        clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
        compensateTeacher:
          settled.teacherFact.compensationType !== "none",
      },
      clientFinancialFactId: settled.clientFact.id,
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
    });
    const transitionId = String(transition.rows[0]!.id);
    await this.work.markCompleted(client, {
      claim,
      transitionId,
      clientFinancialFactId: settled.clientFact.id,
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
    });
    return {
      lessonId: claim.lessonId,
      state: "successfully_completed",
      transitionId,
      clientFinancialFactId: settled.clientFact.id,
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
    };
  }

}

function completionError(code: string): Error {
  const error = new Error(code);
  error.name = code;
  return error;
}
