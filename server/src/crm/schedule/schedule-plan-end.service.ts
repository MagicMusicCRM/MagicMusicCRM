import { ConflictException, Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { CrmPolicy } from "../crm.policy";
import type {
  SchedulePlanEndCommandDto,
  SchedulePlanEndPreviewDto,
} from "../dto/schedule-plan.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { FuturePlanLessonCancellationService } from "./future-plan-lesson-cancellation.service";
import { lockSchedulePlanSeries } from "./schedule-locks";
import {
  type NormalizedSchedulePlanEnd,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import { assertSchedulePlanMetadata as assertMetadata, failSchedulePlan } from "./schedule-plan-definition.service";
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

export interface LockedSchedulePlanEndInput {
  plan: LockedSchedulePlan;
  seriesIds: string[];
  effectiveFrom: string;
  actorUserId: string;
  reasonText: string;
  version: number;
  cancellationMode?: "plan-end" | "row-removal";
}

interface EndMutationReference extends Record<string, unknown> {
  planId: string;
  endedLessons: number;
  releasedReservations: number;
  preservedTerminalLessons: number;
}

@Injectable()
export class SchedulePlanEndService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly repository: SchedulePlanRepository,
    private readonly database: DatabaseService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly cancellations: FuturePlanLessonCancellationService,
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
    const ending = await this.endLockedInTransaction(client, {
      plan,
      seriesIds: currentSeries.rows.map((series) => series.id),
      effectiveFrom: this.nextDate(normalized.lastDate),
      actorUserId: actor.userId,
      reasonText: normalized.reasonText,
      version,
    });
    return {
      planId,
      endedLessons: ending.endedLessons,
      releasedReservations: ending.releasedReservations,
      preservedTerminalLessons: ending.preservedTerminalLessons,
    };
  }

  async endLockedInTransaction(
    client: PoolClient,
    input: LockedSchedulePlanEndInput,
  ): Promise<{
    endedLessons: number;
    releasedReservations: number;
    preservedTerminalLessons: number;
    preservedChangedLessons: number;
  }> {
    const lastDate = this.previousDate(input.effectiveFrom);
    await this.finishPlan(
      client,
      input.actorUserId,
      input.plan.id,
      {
        expectedVersion: Number(input.plan.version),
        lastDate,
        reasonText: input.reasonText,
      },
      input.version,
    );
    const planEndLifecycle =
      input.cancellationMode === "row-removal"
        ? {}
        : {
            lifecycleReasonCode: "schedule.plan.end",
            lifecycleReasonText: input.reasonText,
            lifecycleFinancialDecision: {
              settlementTypeKey: "schedule.plan.end",
              clientChargeType: "none",
              teacherCompensationRuleKey: "none",
            },
          };
    const cancellation = await this.cancellations.cancelEligible(client, {
      planId: input.plan.id,
      seriesIds: input.seriesIds,
      effectiveFrom: input.effectiveFrom,
      actorUserId: input.actorUserId,
      reasonText: input.reasonText,
      ...planEndLifecycle,
    });
    return {
      endedLessons: cancellation.cancelledLessonIds.length,
      releasedReservations: cancellation.releasedReservationIds.length,
      preservedTerminalLessons:
        cancellation.preservedTerminalLessonIds.length,
      preservedChangedLessons: cancellation.preservedChangedLessonIds.length,
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
      changedLessonCount: impact.changedLessonCount,
    });
  }

  private nextDate(date: string) {
    const value = new Date(`${date}T00:00:00.000Z`);
    value.setUTCDate(value.getUTCDate() + 1);
    return value.toISOString().slice(0, 10);
  }

  private previousDate(date: string) {
    const value = new Date(`${date}T00:00:00.000Z`);
    value.setUTCDate(value.getUTCDate() - 1);
    return value.toISOString().slice(0, 10);
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
