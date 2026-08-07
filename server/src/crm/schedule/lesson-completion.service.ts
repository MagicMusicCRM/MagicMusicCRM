import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  LessonCompletionClaim,
  LessonCompletionResultRef,
} from "./completion-worker.types";
import { LessonCompletionWorkerRepository } from "./completion-worker.repository";

@Injectable()
export class LessonCompletionService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly work: LessonCompletionWorkerRepository,
  ) {}

  async complete(claim: LessonCompletionClaim) {
    const result =
      await this.platform.executeVersionedMutation<LessonCompletionResultRef>({
        actorKey: "worker:lesson-completion",
        operation: "schedule.lesson.queue-settlement",
        idempotencyKey: `lesson-settlement-pending:${claim.lessonId}`,
        payload: {
          lessonId: claim.lessonId,
          scheduledEndAt: claim.scheduledEndAt.toISOString(),
        },
        aggregateType: "schedule:lesson",
        aggregateId: claim.lessonId,
        expectedVersion: claim.lessonVersion,
        requestId: `lesson-settlement-pending:${claim.lessonId}`,
        audit: {
          action: "crm.lesson_settlement_queued",
          entityType: "lesson",
          entityId: claim.lessonId,
          reason: "worker.end-at-reached",
          beforeRef: {
            lessonId: claim.lessonId,
            version: claim.lessonVersion,
            state: "scheduled",
          },
          metadata: { worker: "lesson-completion", financeFactsCreated: 0 },
        },
        outbox: {
          type: "schedule.lesson.changed",
          payload: {
            entityId: claim.lessonId,
            state: "settlement_pending",
          },
        },
        mutate: (client, nextVersion) =>
          this.completeInTransaction(client, claim, nextVersion),
      });
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
    const updated = await client.query<{ version: number | string }>(
      `
        update app.lessons
        set lifecycle_state = 'settlement_pending',
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

    await this.work.markPending(client, claim);
    return {
      lessonId: claim.lessonId,
      state: "settlement_pending",
    };
  }

}

function completionError(code: string): Error {
  const error = new Error(code);
  error.name = code;
  return error;
}
