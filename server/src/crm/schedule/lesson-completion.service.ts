import { Inject, Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  LESSON_SETTLEMENT_PORT,
  LessonSettlementPort,
  LessonSettlementResult,
} from "../commerce/lesson-settlement.port";
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
    private readonly lifecycle: LessonLifecycleRepository,
    @Inject(LESSON_SETTLEMENT_PORT)
    private readonly settlement: LessonSettlementPort,
  ) {}

  complete(claim: LessonCompletionClaim) {
    return this.platform.executeVersionedMutation<LessonCompletionResultRef>({
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
    await this.terminalizeReservation(client, settled);
    const transition = await this.lifecycle.appendTransition(client, {
      lessonId: claim.lessonId,
      toState: "successfully_completed",
      reasonCode: "worker.end-at-reached",
      workerId: claim.workerId,
      financialDecision: {
        chargeClient: settled.clientFact.chargeType !== "none",
        compensateTeacher:
          settled.teacherFact.compensationType !== "none",
      },
      clientFinancialFactId: settled.clientFact.id,
      teacherFinancialFactId: settled.teacherFact.id,
    });
    const transitionId = String(transition.rows[0]!.id);
    await this.work.markCompleted(client, {
      claim,
      transitionId,
      clientFinancialFactId: settled.clientFact.id,
      teacherFinancialFactId: settled.teacherFact.id,
    });
    return {
      lessonId: claim.lessonId,
      state: "successfully_completed",
      transitionId,
      clientFinancialFactId: settled.clientFact.id,
      teacherFinancialFactId: settled.teacherFact.id,
    };
  }

  private async terminalizeReservation(
    client: PoolClient,
    settled: LessonSettlementResult,
  ): Promise<void> {
    await client.query(
      `
        update app.lesson_reservations
        set state = case
              when $2 = 'subscription' then 'consumed'
              else 'released'
            end,
            financial_fact_id = case
              when $2 = 'subscription' then $3::uuid
              else null
            end
        where lesson_id = $1 and state = 'reserved'
      `,
      [
        settled.lessonId,
        settled.clientFact.chargeType,
        settled.clientFact.id,
      ],
    );
  }
}

function completionError(code: string): Error {
  const error = new Error(code);
  error.name = code;
  return error;
}
