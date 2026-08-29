import {
  ConflictException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { ClientReferenceService } from "../clients/client-reference.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import {
  assertLessonCommandMetadata,
  stableLessonCreateId,
} from "./lesson-command-integrity";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonCommandRepository } from "./lesson-command.repository";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { assertLessonPatchUsesTransition } from "./lesson-protected-patch.guard";
import {
  CompleteLessonDraft,
  ExistingLessonDraft,
  LessonRequiredFieldValidator,
} from "./lesson-required-field.validator";

@Injectable()
export class LessonWriteCommandService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly clients: ClientReferenceService,
    private readonly validator: LessonRequiredFieldValidator,
    private readonly constraints: ScheduleConstraintEngine,
    private readonly lifecycle: LessonLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
    private readonly settlement: LessonSettlementService,
    private readonly repository: LessonCommandRepository,
  ) {}

  async create(
    actor: ActorContext,
    dto: UpsertLessonDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    assertLessonCommandMetadata(metadata);
    const canManageTeacherCompensation =
      this.policy.canManageTeacherCompensation(actor);
    const draft = this.validator.create(
      canManageTeacherCompensation
        ? dto
        : {
            ...dto,
            teacherCompensationType: "none",
            teacherCompensationValue: 0,
          },
    );
    if (!dto.financialDecision) {
      throw new UnprocessableEntityException({
        code: "LESSON_SETTLEMENT_PLAN_REQUIRED",
        fields: ["financialDecision"],
      });
    }
    await this.assertClientActive(actor, draft);
    const lessonId = stableLessonCreateId(
      actor.userId,
      metadata.idempotencyKey,
    );
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization:
        this.policy.teacherCompensationMutationAuthorization(actor),
      operation: "schedule.lesson.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: 0,
      requestId: metadata.requestId,
      audit: {
        action: "crm.lesson_created",
        entityType: "lesson",
        entityId: lessonId,
        afterRef: { lessonId },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { lessonId, action: "created" },
      },
      mutate: async (client) => {
        const effectiveDraft = canManageTeacherCompensation
          ? draft
          : await this.withEffectiveTeacherRate(client, draft);
        const financialDecision = canManageTeacherCompensation
          ? dto.financialDecision!
          : await this.settlement.applyDefaultTeacherCompensation(
              client,
              effectiveDraft.branchId,
              dto.financialDecision!,
            );
        await this.acquireLocks(client, effectiveDraft);
        await this.assertConstraints(effectiveDraft, client);
        await this.assertLeadNotConverted(client, effectiveDraft);
        await this.repository.insertLesson(
          client,
          lessonId,
          effectiveDraft,
          actor.userId,
        );
        await this.lifecycle.createSnapshot(client, {
          lessonId,
          clientType: effectiveDraft.clientRef.type,
          clientId: effectiveDraft.clientRef.id,
          completionType: effectiveDraft.completionType,
          clientChargeType: effectiveDraft.clientChargeType,
          clientChargeValue: effectiveDraft.clientChargeValue,
          teacherCompensationType: effectiveDraft.teacherCompensationType,
          teacherCompensationValue: effectiveDraft.teacherCompensationValue,
          subscriptionId: effectiveDraft.subscriptionId ?? undefined,
          trial: effectiveDraft.isTrial,
        });
        const plan = await this.settlement.assignPlan(client, {
          lessonId,
          branchId: effectiveDraft.branchId,
          decision: financialDecision,
          selectedBy: actor.userId,
          reasonText: dto.plannedSettlementReason,
        });
        for (const allocation of await this.settlement.plannedSubscriptionAllocations(
          client,
          lessonId,
          plan,
        )) {
          await this.reservations.allocate(client, {
            lessonId,
            chargeType: "subscription",
            ...allocation,
          });
        }
        return { lessonId };
      },
    });
    return this.repository.response(
      lessonId,
      mutation.version,
      mutation.replayed,
    );
  }

  private async withEffectiveTeacherRate(
    client: PoolClient,
    draft: CompleteLessonDraft,
  ): Promise<CompleteLessonDraft> {
    const rate = await this.repository.loadEffectiveTeacherRate(
      client,
      draft.teacherId,
      draft.scheduledAt,
    );
    return {
      ...draft,
      teacherCompensationType: rate > 0 ? "hourly" : "none",
      teacherCompensationValue: rate,
    };
  }

  async update(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    assertLessonCommandMetadata(metadata);
    assertLessonPatchUsesTransition(dto);
    if (!dto.expectedVersion) {
      throw new UnprocessableEntityException({
        code: "EXPECTED_VERSION_REQUIRED",
        message: "expectedVersion is required for lesson updates.",
        fields: ["expectedVersion"],
      });
    }
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      operation: "schedule.lesson.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: { lessonId, dto },
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.lesson_updated",
        entityType: "lesson",
        entityId: lessonId,
        beforeRef: { lessonId, version: dto.expectedVersion },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { lessonId, action: "updated" },
      },
      mutate: async (client, nextVersion) => {
        const current = await this.repository.loadExisting(
          client,
          lessonId,
          true,
        );
        if (current.version !== dto.expectedVersion) {
          throw new ConflictException({
            code: "STALE_AGGREGATE_VERSION",
            expectedVersion: dto.expectedVersion,
            currentVersion: current.version,
          });
        }
        const updated = await this.repository.updateNotes(
          client,
          lessonId,
          dto.notes?.trim() || null,
          dto.expectedVersion,
        );
        if (!updated.rows[0]) {
          throw new ConflictException({
            code: "STALE_AGGREGATE_VERSION",
            expectedVersion: dto.expectedVersion,
          });
        }
        if (Number(updated.rows[0].version) !== nextVersion) {
          throw new ConflictException({
            code: "LESSON_VERSION_DIVERGED",
            expectedVersion: nextVersion,
            currentVersion: Number(updated.rows[0].version),
          });
        }
        return { lessonId, version: nextVersion };
      },
    });
    return this.repository.response(
      lessonId,
      mutation.version,
      mutation.replayed,
    );
  }

  private async assertClientActive(
    actor: ActorContext,
    draft: CompleteLessonDraft,
  ) {
    const client = await this.clients.resolve(actor, draft.clientRef);
    if (client.tombstone) {
      throw new UnprocessableEntityException({
        code: "ARCHIVED_CLIENT_REFERENCE",
        message: "Archived client cannot be scheduled.",
        fields: ["clientRef"],
      });
    }
  }

  private async assertConstraints(
    draft: CompleteLessonDraft,
    client: PoolClient,
    excludeLessonId?: string,
  ) {
    const result = await this.constraints.validate(
      {
        clientRef: draft.clientRef,
        teacherId: draft.teacherId,
        branchId: draft.branchId,
        roomId: draft.roomId,
        startAt: draft.scheduledAt,
        endAt: draft.endAt,
        excludeLessonId,
      },
      client,
    );
    if (!result.valid) {
      throw new UnprocessableEntityException({
        code: "LESSON_CONSTRAINT_VIOLATIONS",
        message: "Lesson draft violates schedule constraints.",
        violations: result.violations,
      });
    }
  }

  private async acquireLocks(
    client: PoolClient,
    draft: CompleteLessonDraft,
    previous?: ExistingLessonDraft,
  ) {
    const keys = [
      `branch:${draft.branchId}`,
      `client:${draft.clientRef.type}:${draft.clientRef.id}`,
      `room:${draft.roomId}`,
      `teacher:${draft.teacherId}`,
      previous?.branchId ? `branch:${previous.branchId}` : null,
      previous?.roomId ? `room:${previous.roomId}` : null,
      previous?.teacherId ? `teacher:${previous.teacherId}` : null,
    ]
      .filter((key): key is string => key !== null)
      .filter((key, index, values) => values.indexOf(key) === index)
      .sort();
    for (const key of keys) {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [key],
      );
    }
  }

  private async assertLeadNotConverted(
    client: PoolClient,
    draft: CompleteLessonDraft,
  ) {
    if (draft.clientRef.type !== "lead") return;
    if (await this.repository.isLeadConverted(client, draft.clientRef.id)) {
      throw new ConflictException({
        code: "LEAD_ALREADY_CONVERTED",
        message: "Use the converted Student client reference.",
      });
    }
  }
}
