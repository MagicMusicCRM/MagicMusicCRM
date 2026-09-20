import { ConflictException, Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import {
  type FuturePlanLessonCancellationImpact,
  SchedulePlanRepository,
} from "./schedule-plan.repository";

export interface FuturePlanLessonCancellationInput {
  planId: string;
  seriesIds: string[];
  effectiveFrom: string;
  actorUserId: string;
  reasonText: string;
  lifecycleReasonCode?: string;
  lifecycleReasonText?: string;
  lifecycleFinancialDecision?: Record<string, unknown>;
}

export interface FuturePlanLessonCancellationResult {
  cancelledLessonIds: string[];
  releasedReservationIds: string[];
  preservedTerminalLessonIds: string[];
  preservedChangedLessonIds: string[];
}

const SYSTEM_REASON = "Строка постоянного расписания удалена";

@Injectable()
export class FuturePlanLessonCancellationService {
  constructor(
    private readonly repository: SchedulePlanRepository,
    private readonly lifecycle: LessonLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  inspectEligible(
    client: PoolClient,
    input: Pick<
      FuturePlanLessonCancellationInput,
      "planId" | "seriesIds" | "effectiveFrom"
    >,
    lock = false,
  ): Promise<FuturePlanLessonCancellationImpact> {
    return this.repository.futureLessonCancellationImpact(client, input, lock);
  }

  async cancelEligible(
    client: PoolClient,
    input: FuturePlanLessonCancellationInput,
  ): Promise<FuturePlanLessonCancellationResult> {
    const impact = await this.inspectEligible(client, input, true);
    for (const lesson of impact.eligibleLessons) {
      const updated = await this.repository.cancelLesson(
        client,
        lesson.id,
        lesson.version,
      );
      if (
        !updated.rows[0] ||
        Number(updated.rows[0].version) !== lesson.version + 1
      ) {
        throw new ConflictException({
          code: "STALE_LESSON_VERSION",
          lessonId: lesson.id,
        });
      }
      await this.lifecycle.appendTransition(client, {
        lessonId: lesson.id,
        fromState: lesson.lifecycleState,
        toState: "cancelled",
        reasonCode: input.lifecycleReasonCode ?? "schedule.plan.row.remove",
        reasonText: input.lifecycleReasonText ?? SYSTEM_REASON,
        actorUserId: input.actorUserId,
        financialDecision:
          input.lifecycleFinancialDecision ?? {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "none",
            clientDecisions: lesson.clientIds.map((clientId) => ({
              clientId,
              chargeType: "none",
              chargeDurationMinutes: 0,
            })),
          },
      });
    }
    const lessonIds = impact.eligibleLessons.map((lesson) => lesson.id);
    const released = await this.reservations.releaseForLessons(client, lessonIds);
    if (released !== impact.reservations.length) {
      throw new ConflictException({ code: "LESSON_RESERVATION_STATE_STALE" });
    }
    return {
      cancelledLessonIds: lessonIds,
      releasedReservationIds: impact.reservations.map(
        (reservation) => reservation.id,
      ),
      preservedTerminalLessonIds: impact.preservedTerminalLessonIds,
      preservedChangedLessonIds: impact.preservedChangedLessonIds,
    };
  }
}
