import { ConflictException, Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import type {
  SchedulePlanEndCommandDto,
  SchedulePlanEndPreviewDto,
} from "../dto/schedule-plan.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { lockSchedulePlanSeries } from "./schedule-locks";
import {
  type NormalizedSchedulePlanEnd,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import { failSchedulePlan } from "./schedule-plan-definition.service";
import {
  type LockedSchedulePlan,
  type SchedulePlanEndImpact,
  SchedulePlanRepository,
} from "./schedule-plan.repository";

export interface SchedulePlanEndPreviewProjection {
  plan: { id: string; title: string; version: number; lastDate: string };
  impact: {
    activeSeries: number;
    futureUnsettledLessons: number;
    activeReservations: number;
    reservedUnits: string;
    preservedTerminalLessons: number;
  };
  canConfirm: true;
  confirmRequired: true;
  previewToken: string;
  previewExpiresAt: string;
}

export interface SchedulePlanEndResult {
  id: string;
  status: "ended";
  version: number;
  endedLessons: number;
  releasedReservations: number;
  preservedTerminalLessons: number;
  replayed: boolean;
}

interface EndMutationReference extends Record<string, unknown> {
  planId: string;
  endedLessons: number;
  releasedReservations: number;
  preservedTerminalLessons: number;
}

const assertMetadata = (metadata: LessonCommandMetadata) => {
  if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
    failSchedulePlan("IDEMPOTENCY_KEY_REQUIRED", ["Idempotency-Key"]);
  }
  if (!metadata.requestId || metadata.requestId.length > 160) {
    failSchedulePlan("REQUEST_ID_REQUIRED", ["X-Request-Id"]);
  }
};

@Injectable()
export class SchedulePlanEndService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly repository: SchedulePlanRepository,
    private readonly database: DatabaseService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly lifecycle: LessonLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
    private readonly definition: SchedulePlanDefinitionService,
  ) {}

  async previewEnd(
    actor: ActorContext,
    planId: string,
    dto: SchedulePlanEndPreviewDto,
  ): Promise<SchedulePlanEndPreviewProjection> {
    this.policy.assertCanWriteCrm(actor);
    const normalized = this.definition.normalizeEnd(dto);
    return this.database.transaction(async (client) => {
      const plan = await this.repository.lock(client, planId);
      await this.definition.assertEndable(client, plan, normalized);
      const impact = await this.repository.endImpact(
        client,
        planId,
        normalized.lastDate,
      );
      const impactFingerprint = this.endFingerprint(plan, normalized, impact);
      const signed = this.previewTokens.issueSchedulePlanEnd({
        kind: "schedule.plan.end",
        actorUserId: actor.userId,
        planId,
        expectedVersion: normalized.expectedVersion,
        lastDate: normalized.lastDate,
        impactFingerprint,
      });
      return {
        plan: {
          id: plan.id,
          title: plan.title,
          version: Number(plan.version),
          lastDate: normalized.lastDate,
        },
        impact: this.endImpactProjection(impact),
        canConfirm: true,
        confirmRequired: true,
        previewToken: signed.token,
        previewExpiresAt: signed.expiresAt,
      };
    });
  }

  async end(
    actor: ActorContext,
    planId: string,
    dto: SchedulePlanEndCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<SchedulePlanEndResult> {
    this.policy.assertCanWriteCrm(actor);
    assertMetadata(metadata);
    if (dto.confirm !== true) {
      failSchedulePlan("SCHEDULE_PLAN_END_CONFIRMATION_REQUIRED", ["confirm"]);
    }
    const normalized = this.definition.normalizeEnd(dto);
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: "schedule.plan.end",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:plan",
      aggregateId: planId,
      expectedVersion: normalized.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_plan_ended",
        entityType: "schedule_plan",
        entityId: planId,
        reason: "schedule.plan.end",
        reasonText: normalized.reasonText,
      },
      outbox: {
        type: "schedule.plan.changed",
        payload: { entityId: planId, state: "ended" },
      },
      mutate: (client, version) =>
        this.endInTransaction(client, actor, planId, dto, normalized, version),
    });
    return {
      id: planId,
      status: "ended",
      version: mutation.version,
      endedLessons: mutation.resultRef.endedLessons as number,
      releasedReservations: mutation.resultRef.releasedReservations as number,
      preservedTerminalLessons: mutation.resultRef
        .preservedTerminalLessons as number,
      replayed: mutation.replayed,
    };
  }

  private async endInTransaction(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    dto: SchedulePlanEndCommandDto,
    normalized: NormalizedSchedulePlanEnd,
    version: number,
  ): Promise<EndMutationReference> {
    const signed = this.previewTokens.verifySchedulePlanEnd(dto.previewToken);
    const plan = await this.repository.lock(client, planId);
    await this.definition.assertEndable(client, plan, normalized);
    const currentSeries = await this.repository.currentSeriesIds(
      client,
      planId,
    );
    await lockSchedulePlanSeries(
      client,
      currentSeries.rows.map((series) => series.id),
    );
    const impact = await this.repository.endImpact(
      client,
      planId,
      normalized.lastDate,
      true,
    );
    const impactFingerprint = this.endFingerprint(plan, normalized, impact);
    this.assertSignedPreview(
      signed,
      actor.userId,
      planId,
      normalized,
      impactFingerprint,
    );
    await this.finishPlan(client, actor.userId, planId, normalized, version);
    await this.cancelLessons(
      client,
      actor.userId,
      normalized.reasonText,
      impact,
    );
    const releasedReservations = await this.reservations.releaseForLessons(
      client,
      impact.lessons.map((lesson) => lesson.id),
    );
    return {
      planId,
      endedLessons: impact.lessons.length,
      releasedReservations,
      preservedTerminalLessons: impact.terminalLessonCount,
    };
  }

  private assertSignedPreview(
    signed: ReturnType<
      SubscriptionPreviewTokenService["verifySchedulePlanEnd"]
    >,
    actorUserId: string,
    planId: string,
    normalized: NormalizedSchedulePlanEnd,
    impactFingerprint: string,
  ) {
    if (
      signed.actorUserId !== actorUserId ||
      signed.planId !== planId ||
      signed.expectedVersion !== normalized.expectedVersion ||
      signed.lastDate !== normalized.lastDate ||
      signed.impactFingerprint !== impactFingerprint
    ) {
      failSchedulePlan("SCHEDULE_PLAN_END_PREVIEW_STALE", ["previewToken"]);
    }
  }

  private async finishPlan(
    client: PoolClient,
    actorUserId: string,
    planId: string,
    normalized: NormalizedSchedulePlanEnd,
    version: number,
  ) {
    const finished = await this.repository.finish(client, {
      planId,
      expectedVersion: normalized.expectedVersion,
      version,
      lastDate: normalized.lastDate,
      actorUserId,
      reasonText: normalized.reasonText,
    });
    if (!finished.rows[0]) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
    }
  }

  private async cancelLessons(
    client: PoolClient,
    actorUserId: string,
    reasonText: string,
    impact: SchedulePlanEndImpact,
  ) {
    for (const lesson of impact.lessons) {
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
        reasonCode: "schedule.plan.end",
        reasonText,
        actorUserId,
        financialDecision: {
          settlementTypeKey: "schedule.plan.end",
          clientChargeType: "none",
          teacherCompensationRuleKey: "none",
        },
      });
    }
  }

  private endFingerprint(
    plan: LockedSchedulePlan,
    input: NormalizedSchedulePlanEnd,
    impact: SchedulePlanEndImpact,
  ) {
    return fingerprintPayload({
      planId: plan.id,
      expectedVersion: input.expectedVersion,
      lastDate: input.lastDate,
      reasonText: input.reasonText,
      series: impact.series,
      lessons: impact.lessons,
      reservations: impact.reservations,
      terminalLessonCount: impact.terminalLessonCount,
    });
  }

  private endImpactProjection(impact: SchedulePlanEndImpact) {
    return {
      activeSeries: impact.series.length,
      futureUnsettledLessons: impact.lessons.length,
      activeReservations: impact.reservations.length,
      reservedUnits: this.sumUnits(
        impact.reservations.map((reservation) => reservation.units),
      ),
      preservedTerminalLessons: impact.terminalLessonCount,
    };
  }

  private sumUnits(values: string[]) {
    const total = values.reduce((sum, value) => {
      const [whole, fraction = ""] = value.split(".");
      return (
        sum + BigInt(whole) * 100n + BigInt(fraction.padEnd(2, "0").slice(0, 2))
      );
    }, 0n);
    return `${total / 100n}.${String(total % 100n).padStart(2, "0")}`;
  }
}
