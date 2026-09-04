import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { CrmPolicy } from "../crm.policy";
import type {
  SchedulePlanRowRemovalCommandDto,
  SchedulePlanRowRemovalPreviewDto,
} from "../dto/schedule-plan-row-removal.dto";
import {
  assertSchedulePlanMetadata,
  failSchedulePlan,
} from "./schedule-plan-definition.service";
import {
  FuturePlanLessonCancellationService,
  type FuturePlanLessonCancellationInput,
} from "./future-plan-lesson-cancellation.service";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { lockSchedulePlanSeries } from "./schedule-locks";
import {
  type LockedSchedulePlan,
  type LockedSchedulePlanSeries,
  type FuturePlanLessonCancellationImpact,
  SchedulePlanRepository,
} from "./schedule-plan.repository";
import { SchedulePlanEndService } from "./schedule-plan-end.service";

interface NormalizedRowRemoval {
  expectedVersion: number;
  effectiveFrom: string;
  reasonText: string;
}

interface RowRemovalMutationReference extends Record<string, unknown> {
  planId: string;
  seriesId: string;
  status: "active" | "ended";
  endsPlan: boolean;
  cancelledLessons: number;
  releasedReservations: number;
  preservedTerminalLessons: number;
  preservedChangedLessons: number;
}

export interface SchedulePlanRowRemovalPreviewProjection {
  plan: { id: string; title: string; version: number };
  row: { id: string; validFrom: string; validUntil: string | null };
  effectiveFrom: string;
  impact: {
    futureUnfinishedLessons: number;
    terminalLessonsPreserved: number;
    changedLessonsPreserved: number;
    activeReservationsToRelease: number;
    endsPlan: boolean;
  };
  canConfirm: true;
  confirmRequired: true;
  previewToken: string;
  previewExpiresAt: string;
}

export interface SchedulePlanRowRemovalResult {
  id: string;
  seriesId: string;
  status: "active" | "ended";
  version: number;
  endsPlan: boolean;
  cancelledLessons: number;
  releasedReservations: number;
  preservedTerminalLessons: number;
  preservedChangedLessons: number;
  replayed: boolean;
}

@Injectable()
export class SchedulePlanRowRemovalService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly repository: SchedulePlanRepository,
    private readonly database: DatabaseService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly cancellations: FuturePlanLessonCancellationService,
    private readonly ending: SchedulePlanEndService,
  ) {}

  async previewRemoveRow(
    actor: ActorContext,
    planId: string,
    seriesId: string,
    dto: SchedulePlanRowRemovalPreviewDto,
  ): Promise<SchedulePlanRowRemovalPreviewProjection> {
    this.policy.assertCanWriteCrm(actor);
    return this.database.transaction(async (client) => {
      const plan = await this.repository.lock(client, planId);
      this.assertActiveVersion(plan, dto.expectedVersion);
      const row = await this.repository.lockCurrentRow(client, planId, seriesId);
      const normalized = await this.normalize(client, plan, row, dto);
      const currentSeries = await this.repository.currentSeriesIds(client, planId);
      const endsPlan = this.endsPlan(currentSeries.rows, seriesId);
      const impact = await this.cancellations.inspectEligible(client, {
        planId,
        seriesIds: [seriesId],
        effectiveFrom: normalized.effectiveFrom,
      });
      const impactFingerprint = this.fingerprint(
        plan,
        row,
        normalized,
        impact,
        endsPlan,
      );
      const signed = this.previewTokens.issueSchedulePlanRowRemoval({
        kind: "schedule.plan.row.remove",
        actorUserId: actor.userId,
        planId,
        seriesId,
        expectedVersion: normalized.expectedVersion,
        effectiveFrom: normalized.effectiveFrom,
        impactFingerprint,
      });
      return {
        plan: { id: plan.id, title: plan.title, version: Number(plan.version) },
        row: {
          id: row.id,
          validFrom: row.validFrom,
          validUntil: row.validUntil,
        },
        effectiveFrom: normalized.effectiveFrom,
        impact: this.impactProjection(impact, endsPlan),
        canConfirm: true,
        confirmRequired: true,
        previewToken: signed.token,
        previewExpiresAt: signed.expiresAt,
      };
    });
  }

  async removeRow(
    actor: ActorContext,
    planId: string,
    seriesId: string,
    dto: SchedulePlanRowRemovalCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<SchedulePlanRowRemovalResult> {
    this.policy.assertCanWriteCrm(actor);
    assertSchedulePlanMetadata(metadata);
    if (dto.confirm !== true) {
      failSchedulePlan("SCHEDULE_PLAN_ROW_CONFIRMATION_REQUIRED", ["confirm"]);
    }
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: "schedule.plan.row.remove",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:plan",
      aggregateId: planId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_plan_row_removed",
        entityType: "schedule_plan",
        entityId: planId,
        reason: "schedule.plan.row.remove",
        reasonText: dto.reasonText.trim(),
        metadata: { seriesId, effectiveFrom: dto.effectiveFrom ?? null },
      },
      outbox: {
        type: "schedule.plan.changed",
        payload: { entityId: planId, state: "row_removed", seriesId },
      },
      mutate: (client, version) =>
        this.removeInTransaction(
          client,
          actor,
          planId,
          seriesId,
          dto,
          version,
        ),
    });
    return {
      id: planId,
      seriesId,
      status: mutation.resultRef.status as "active" | "ended",
      version: mutation.version,
      endsPlan: mutation.resultRef.endsPlan as boolean,
      cancelledLessons: mutation.resultRef.cancelledLessons as number,
      releasedReservations: mutation.resultRef.releasedReservations as number,
      preservedTerminalLessons: mutation.resultRef
        .preservedTerminalLessons as number,
      preservedChangedLessons: mutation.resultRef
        .preservedChangedLessons as number,
      replayed: mutation.replayed,
    };
  }

  private async removeInTransaction(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    seriesId: string,
    dto: SchedulePlanRowRemovalCommandDto,
    version: number,
  ): Promise<RowRemovalMutationReference> {
    const signed = this.verifyToken(dto.previewToken);
    const plan = await this.repository.lock(client, planId);
    this.assertActiveVersion(plan, dto.expectedVersion);
    const currentSeries = await this.repository.currentSeriesIds(client, planId);
    await lockSchedulePlanSeries(
      client,
      currentSeries.rows.map((series) => series.id),
    );
    const row = await this.repository.lockCurrentRow(client, planId, seriesId);
    const normalized = await this.normalize(client, plan, row, dto);
    const endsPlan = this.endsPlan(currentSeries.rows, seriesId);
    const impact = await this.cancellations.inspectEligible(
      client,
      {
        planId,
        seriesIds: [seriesId],
        effectiveFrom: normalized.effectiveFrom,
      },
      true,
    );
    const fingerprint = this.fingerprint(
      plan,
      row,
      normalized,
      impact,
      endsPlan,
    );
    this.assertSigned(
      signed,
      actor.userId,
      planId,
      seriesId,
      normalized,
      fingerprint,
    );
    if (endsPlan) {
      const ended = await this.ending.endLockedInTransaction(client, {
        plan,
        seriesIds: [seriesId],
        effectiveFrom: normalized.effectiveFrom,
        actorUserId: actor.userId,
        reasonText: normalized.reasonText,
        version,
        cancellationMode: "row-removal",
      });
      return {
        planId,
        seriesId,
        status: "ended",
        endsPlan: true,
        cancelledLessons: ended.endedLessons,
        releasedReservations: ended.releasedReservations,
        preservedTerminalLessons: ended.preservedTerminalLessons,
        preservedChangedLessons: ended.preservedChangedLessons,
      };
    }
    const retired = await this.repository.retireRow(client, {
      planId,
      seriesId,
      effectiveFrom: normalized.effectiveFrom,
      version,
    });
    if (!retired.rows[0]) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_ROW_STALE" });
    }
    const updated = await this.repository.bumpAfterRowRemoval(client, {
      planId,
      expectedVersion: normalized.expectedVersion,
      version,
    });
    if (!updated.rows[0]) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
    }
    const cancelled = await this.cancellations.cancelEligible(client, {
      planId,
      seriesIds: [seriesId],
      effectiveFrom: normalized.effectiveFrom,
      actorUserId: actor.userId,
      reasonText: normalized.reasonText,
    });
    return {
      planId,
      seriesId,
      status: "active",
      endsPlan: false,
      cancelledLessons: cancelled.cancelledLessonIds.length,
      releasedReservations: cancelled.releasedReservationIds.length,
      preservedTerminalLessons: cancelled.preservedTerminalLessonIds.length,
      preservedChangedLessons: cancelled.preservedChangedLessonIds.length,
    };
  }

  private async normalize(
    client: PoolClient,
    plan: LockedSchedulePlan,
    row: LockedSchedulePlanSeries,
    dto: SchedulePlanRowRemovalPreviewDto,
  ): Promise<NormalizedRowRemoval> {
    const reasonText = dto.reasonText.trim();
    if (!reasonText || reasonText.length > 500 || reasonText.includes("\0")) {
      failSchedulePlan("SCHEDULE_PLAN_ROW_REASON_REQUIRED", ["reasonText"]);
    }
    const today = await this.repository.localToday(client, plan.id);
    const defaultEffectiveFrom = row.validFrom > today ? row.validFrom : today;
    const effectiveFrom =
      dto.effectiveFrom?.slice(0, 10) ?? defaultEffectiveFrom;
    if (
      effectiveFrom < defaultEffectiveFrom ||
      (row.validUntil !== null && effectiveFrom > row.validUntil)
    ) {
      failSchedulePlan("SCHEDULE_PLAN_ROW_HAS_NO_FUTURE_BOUNDARY", [
        "effectiveFrom",
      ]);
    }
    return {
      expectedVersion: dto.expectedVersion,
      effectiveFrom,
      reasonText,
    };
  }

  private assertActiveVersion(plan: LockedSchedulePlan, expectedVersion: number) {
    if (plan.status !== "active") {
      throw new ConflictException({ code: "SCHEDULE_PLAN_ENDED" });
    }
    if (Number(plan.version) !== expectedVersion) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_VERSION_STALE" });
    }
  }

  private endsPlan(rows: Array<{ id: string }>, seriesId: string) {
    if (!rows.some((row) => row.id === seriesId)) {
      throw new ConflictException({ code: "SCHEDULE_PLAN_ROW_STALE" });
    }
    return rows.length === 1;
  }

  private impactProjection(
    impact: FuturePlanLessonCancellationImpact,
    endsPlan: boolean,
  ) {
    return {
      futureUnfinishedLessons: impact.eligibleLessons.length,
      terminalLessonsPreserved: impact.preservedTerminalLessonIds.length,
      changedLessonsPreserved: impact.preservedChangedLessonIds.length,
      activeReservationsToRelease: impact.reservations.length,
      endsPlan,
    };
  }

  private fingerprint(
    plan: LockedSchedulePlan,
    row: LockedSchedulePlanSeries,
    input: NormalizedRowRemoval,
    impact: FuturePlanLessonCancellationImpact,
    endsPlan: boolean,
  ) {
    return fingerprintPayload({
      planId: plan.id,
      seriesId: row.id,
      rowVersion: row.version,
      rowValidFrom: row.validFrom,
      rowValidUntil: row.validUntil,
      expectedVersion: input.expectedVersion,
      effectiveFrom: input.effectiveFrom,
      reasonText: input.reasonText,
      eligibleLessons: impact.eligibleLessons,
      reservations: impact.reservations,
      preservedTerminalLessonIds: impact.preservedTerminalLessonIds,
      preservedChangedLessonIds: impact.preservedChangedLessonIds,
      endsPlan,
    });
  }

  private verifyToken(token: string) {
    try {
      return this.previewTokens.verifySchedulePlanRowRemoval(token);
    } catch (error) {
      if (error instanceof UnprocessableEntityException) {
        throw new UnprocessableEntityException({
          code: "SCHEDULE_PLAN_ROW_PREVIEW_INVALID",
          fields: ["previewToken"],
        });
      }
      throw error;
    }
  }

  private assertSigned(
    signed: ReturnType<
      SubscriptionPreviewTokenService["verifySchedulePlanRowRemoval"]
    >,
    actorUserId: string,
    planId: string,
    seriesId: string,
    input: NormalizedRowRemoval,
    impactFingerprint: string,
  ) {
    if (
      signed.actorUserId !== actorUserId ||
      signed.planId !== planId ||
      signed.seriesId !== seriesId ||
      signed.expectedVersion !== input.expectedVersion ||
      signed.effectiveFrom !== input.effectiveFrom ||
      signed.impactFingerprint !== impactFingerprint
    ) {
      throw new UnprocessableEntityException({
        code: "SCHEDULE_PLAN_ROW_PREVIEW_INVALID",
        fields: ["previewToken"],
      });
    }
  }
}
