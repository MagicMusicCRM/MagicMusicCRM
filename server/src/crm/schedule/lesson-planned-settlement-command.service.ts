import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import {
  LessonSettlementPlanCommandDto,
  LessonSettlementPlanPreviewDto,
} from "../dto/lesson-settlement-plan.dto";
import {
  assertLessonCommandMetadata,
  lessonFinancialProjection,
} from "./lesson-command-integrity";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonCommandRepository } from "./lesson-command.repository";

@Injectable()
export class LessonPlannedSettlementCommandService {
  constructor(
    private readonly database: DatabaseService,
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly reservations: SubscriptionReservationService,
    private readonly settlement: LessonSettlementService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly repository: LessonCommandRepository,
  ) {}

  async previewSettlementPlan(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementPlanPreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const calculated = await this.database.transaction(async (client) => {
      await client.query("savepoint lesson_planned_settlement_preview");
      try {
        return await this.calculateSettlementPlanChange(
          client,
          actor,
          lessonId,
          dto,
        );
      } finally {
        await client.query(
          "rollback to savepoint lesson_planned_settlement_preview",
        );
        await client.query(
          "release savepoint lesson_planned_settlement_preview",
        );
      }
    });
    const signed = this.previewTokens.issueLessonTransition({
      kind: "lesson.transition",
      operation: "planned-settlement",
      actorUserId: actor.userId,
      lessonId,
      expectedVersion: dto.expectedVersion,
      transitionFingerprint: calculated.fingerprint,
    });
    return {
      canConfirm: true,
      financialPreview: calculated.financial,
      reservationPreview: calculated.reservations,
      previewToken: signed.token,
      previewExpiresAt: signed.expiresAt,
    };
  }

  async updateSettlementPlan(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementPlanCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    assertLessonCommandMetadata(metadata);
    const signed = this.previewTokens.verifyLessonTransition(dto.previewToken);
    if (
      signed.operation !== "planned-settlement" ||
      signed.actorUserId !== actor.userId ||
      signed.lessonId !== lessonId ||
      signed.expectedVersion !== dto.expectedVersion
    ) {
      throw new UnprocessableEntityException({
        code: "LESSON_SETTLEMENT_PLAN_PREVIEW_INVALID",
      });
    }
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      operation: "schedule.lesson.settlement-plan.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: { lessonId, ...dto },
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.lesson_settlement_plan_updated",
        entityType: "lesson",
        entityId: lessonId,
        reason: "lesson.settlement-plan.update",
        reasonText: dto.reasonText.trim(),
        beforeRef: { lessonId, version: dto.expectedVersion },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { lessonId, action: "settlement-plan-updated" },
      },
      mutate: async (client, nextVersion) => {
        const calculated = await this.calculateSettlementPlanChange(
          client,
          actor,
          lessonId,
          dto,
        );
        if (calculated.fingerprint !== signed.transitionFingerprint) {
          throw new UnprocessableEntityException({
            code: "LESSON_SETTLEMENT_PLAN_PREVIEW_STALE",
          });
        }
        const planVersion = await this.settlement.replacePlan(client, {
          lessonId,
          expectedVersion: calculated.currentPlanVersion,
          selectedBy: actor.userId,
          reasonText: dto.reasonText,
          ...calculated.prepared,
        });
        const updated = await this.repository.touchSettlementPlan(
          client,
          lessonId,
          dto.expectedVersion,
        );
        if (
          !updated.rows[0] ||
          Number(updated.rows[0].version) !== nextVersion
        ) {
          throw new ConflictException({ code: "LESSON_VERSION_DIVERGED" });
        }
        return { lessonId, planVersion };
      },
    });
    return { lessonId, version: mutation.version, replayed: mutation.replayed };
  }

  private async calculateSettlementPlanChange(
    client: PoolClient,
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementPlanPreviewDto,
  ) {
    const source = await this.repository.loadSettlementSource(client, lessonId);
    if (!source) throw new NotFoundException("Урок не найден.");
    if (Number(source.version) !== dto.expectedVersion) {
      throw new ConflictException({ code: "STALE_AGGREGATE_VERSION" });
    }
    if (
      source.lifecycle_state !== "scheduled" ||
      new Date(source.scheduled_at).getTime() <= Date.now()
    ) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_PLAN_CHANGE_CLOSED",
      });
    }
    const current = await this.settlement.loadPlan(client, lessonId, true);
    if (!current || current.state !== "planned") {
      throw new ConflictException({ code: "LESSON_SETTLEMENT_PLAN_MISSING" });
    }
    const before = await this.repository.listReservedAllocations(
      client,
      lessonId,
    );
    const decision = this.policy.canManageTeacherCompensation(actor)
      ? dto.financialDecision
      : await this.settlement.reuseStoredTeacherCompensation(
          client,
          lessonId,
          dto.financialDecision,
        );
    const prepared = await this.settlement.preparePlan(
      client,
      source.branch_id,
      decision,
    );
    const allocations = await this.settlement.plannedSubscriptionAllocations(
      client,
      lessonId,
      prepared,
    );
    await this.reservations.releaseForLessons(client, [lessonId]);
    for (const allocation of allocations) {
      await this.reservations.allocate(client, {
        lessonId,
        chargeType: "subscription",
        ...allocation,
      });
    }
    const financial = lessonFinancialProjection(
      await this.previewPlannedFinancial(client, lessonId, dto, prepared),
    );
    const reservations = {
      before: before.map((row) => ({
        subscriptionId: row.subscription_id,
        units: row.units,
      })),
      after: allocations.map((item) => ({
        subscriptionId: item.subscriptionId,
        clientId: item.clientId,
        ...(item.payerStudentId ? { payerStudentId: item.payerStudentId } : {}),
        units: item.units.toFixed(2),
      })),
    };
    const fingerprint = fingerprintPayload({
      lessonId,
      expectedVersion: dto.expectedVersion,
      currentPlanVersion: current.version,
      reasonText: dto.reasonText.trim(),
      decision: prepared.decision,
      settlementRevisionId: prepared.settlementRevisionId,
      compensationRevisionId: prepared.compensationRevisionId,
      reservations,
      financial,
    });
    return {
      currentPlanVersion: current.version,
      prepared,
      financial,
      reservations,
      fingerprint,
    };
  }

  private async previewPlannedFinancial(
    client: PoolClient,
    lessonId: string,
    dto: LessonSettlementPlanPreviewDto,
    prepared: Awaited<ReturnType<LessonSettlementService["preparePlan"]>>,
  ) {
    await client.query("savepoint lesson_planned_financial_preview");
    try {
      await this.repository.markCompletedForFinancialPreview(client, lessonId);
      const settled = await this.settlement.settle(client, lessonId, {
        context: "settle",
        decision: prepared.decision,
        reasonText: dto.reasonText.trim(),
        configurationRevisionIds: {
          settlementRevisionId: prepared.settlementRevisionId,
          compensationRevisionId: prepared.compensationRevisionId,
        },
      });
      await this.reservations.terminalize(client, settled);
      return settled;
    } finally {
      await client.query(
        "rollback to savepoint lesson_planned_financial_preview",
      );
      await client.query("release savepoint lesson_planned_financial_preview");
    }
  }
}
