import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { acquireLessonSettlementCoordinationGate } from "../commerce/lesson-settlement-locks";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import type {
  LessonBulkTransitionCommandDto,
  LessonBulkTransitionPreviewDto,
} from "../dto/lesson-transition.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonTransitionCommitService } from "./lesson-transition-commit.service";
import { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import {
  assertTransitionConfirmed,
  assertTransitionMetadata,
  bulkTransitionFingerprint,
  bulkTransitionItemDto,
  bulkTransitionPreviewId,
  normalizeBulkTransitionItems,
  stableTransitionId,
} from "./lesson-transition.rules";
import type {
  BulkTransitionResultRef,
  CalculatedTransitionPreview,
  CommittedTransition,
  LessonBulkTransitionCommandResult,
  LessonBulkTransitionPreviewResult,
} from "./lesson-transition.types";

@Injectable()
export class LessonBulkTransitionService {
  constructor(
    private readonly database: DatabaseService,
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly preparation: LessonTransitionPreparationService,
    private readonly commits: LessonTransitionCommitService,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  async previewBulk(
    actor: ActorContext,
    dto: LessonBulkTransitionPreviewDto,
  ): Promise<LessonBulkTransitionPreviewResult> {
    this.policy.assertCanWriteCrm(actor);
    const items = normalizeBulkTransitionItems(dto);
    return this.database.transaction(async (client) => {
      if (this.needsSettlementCoordinationGate(items)) {
        await acquireLessonSettlementCoordinationGate(client);
      }
      const calculated: Array<{
        lessonId: string;
        operation: (typeof items)[number]["operation"];
        preview: CalculatedTransitionPreview;
      }> = [];
      for (const item of items) {
        calculated.push({
          lessonId: item.lessonId,
          operation: item.operation,
          preview: await this.preparation.calculatePreview(
            client,
            actor,
            item.lessonId,
            bulkTransitionItemDto(dto, item),
            item.operation,
          ),
        });
      }
      const canConfirm = calculated.every(
        (item) => item.preview.canConfirm && item.preview.transitionFingerprint,
      );
      const previews = calculated.map(({ preview, ...item }) => {
        const { transitionFingerprint: _fingerprint, ...publicPreview } =
          preview;
        return { ...item, ...publicPreview };
      });
      if (!canConfirm) {
        return { items: previews, canConfirm: false, confirmRequired: true };
      }
      const transitionFingerprint = bulkTransitionFingerprint(dto, calculated);
      const signed = this.previewTokens.issueLessonTransition({
        kind: "lesson.transition",
        operation: "bulk",
        actorUserId: actor.userId,
        lessonId: bulkTransitionPreviewId(items),
        expectedVersion: 1,
        transitionFingerprint,
      });
      return {
        items: previews,
        canConfirm: true,
        confirmRequired: true,
        previewToken: signed.token,
        previewExpiresAt: signed.expiresAt,
      };
    });
  }

  async bulk(
    actor: ActorContext,
    dto: LessonBulkTransitionCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<LessonBulkTransitionCommandResult> {
    this.policy.assertCanWriteCrm(actor);
    assertTransitionConfirmed(dto.confirm);
    assertTransitionMetadata(metadata);
    const items = normalizeBulkTransitionItems(dto);
    const previewId = bulkTransitionPreviewId(items);
    const bulkId = stableTransitionId(
      `schedule.lesson.bulk\0${actor.userId}\0${metadata.idempotencyKey}`,
    );
    const mutation =
      await this.platform.executeVersionedMutation<BulkTransitionResultRef>({
        actorKey: `user:${actor.userId}`,
        actorUserId: actor.userId,
        authorization:
          this.policy.teacherCompensationMutationAuthorization(actor),
        operation: "schedule.lesson.bulk-transition",
        idempotencyKey: metadata.idempotencyKey,
        payload: { dto },
        aggregateType: "schedule:lesson-bulk",
        aggregateId: bulkId,
        expectedVersion: 0,
        requestId: metadata.requestId,
        audit: {
          action: "crm.lessons_bulk_transitioned",
          entityType: "lesson_batch",
          entityId: bulkId,
          reason: dto.reasonCode?.trim() || "manual",
          reasonText: dto.reasonText.trim(),
          beforeRef: {
            items: items.map((item) => ({
              lessonId: item.lessonId,
              version: item.expectedVersion,
            })),
          },
        },
        outbox: {
          type: "schedule.lessons.changed",
          payload: { entityIds: items.map((item) => item.lessonId) },
        },
        ...(this.needsSettlementCoordinationGate(items)
          ? { beforeVersionAdvance: acquireLessonSettlementCoordinationGate }
          : {}),
        mutate: async (client) => {
          const signed = this.previewTokens.verifyLessonTransition(
            dto.previewToken,
          );
          this.assertBulkPreview(signed, actor, previewId);
          const committed: CommittedTransition[] = [];
          for (const item of items) {
            const common = {
                actor,
                lessonId: item.lessonId,
                nextVersion: item.expectedVersion + 1,
            };
            if (item.operation === "reschedule") {
              committed.push(await this.commits.commit(client, {
                ...common,
                dto: bulkTransitionItemDto(dto, item),
                operation: "reschedule",
                successorId: stableTransitionId(
                  `schedule.lesson.bulk-successor\0${bulkId}\0${item.lessonId}`,
                ),
              }));
              continue;
            }
            committed.push(await this.commits.commit(client, {
              ...common,
              dto: bulkTransitionItemDto(dto, item),
              operation: item.operation,
              successorId: null,
            }));
          }
          this.assertBulkFingerprint(
            signed.transitionFingerprint,
            dto,
            items,
            committed,
          );
          return { bulkId, items: committed };
        },
      });
    for (const item of items) {
      await this.reservations.publishLessonSettlementPostCommit(item.lessonId);
      if (item.operation !== "reschedule") continue;
      const committed = mutation.resultRef.items.find(
        (result) => result.lessonId === item.lessonId,
      );
      if (committed?.successorId) {
        await this.reservations.publishLessonSettlementPostCommit(
          committed.successorId,
        );
      }
    }
    return {
      bulkId,
      items: mutation.resultRef.items,
      replayed: mutation.replayed,
    };
  }

  private needsSettlementCoordinationGate(
    items: ReturnType<typeof normalizeBulkTransitionItems>,
  ): boolean {
    return (
      items.length > 1 ||
      items.some((item) => item.operation === "reschedule")
    );
  }

  private assertBulkPreview(
    signed: ReturnType<
      SubscriptionPreviewTokenService["verifyLessonTransition"]
    >,
    actor: ActorContext,
    previewId: string,
  ): void {
    if (
      signed.actorUserId === actor.userId &&
      signed.operation === "bulk" &&
      signed.lessonId === previewId &&
      signed.expectedVersion === 1
    )
      return;
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_PREVIEW_STALE",
      message: "Signed preview does not match this bulk command.",
    });
  }

  private assertBulkFingerprint(
    expected: string,
    dto: LessonBulkTransitionPreviewDto,
    items: ReturnType<typeof normalizeBulkTransitionItems>,
    committed: CommittedTransition[],
  ): void {
    const operations = new Map(
      items.map((item) => [item.lessonId, item.operation]),
    );
    const actual = bulkTransitionFingerprint(
      dto,
      committed.map((item) => ({
        lessonId: item.lessonId,
        operation: operations.get(item.lessonId)!,
        preview: { transitionFingerprint: item.transitionFingerprint },
      })),
    );
    if (expected === actual) return;
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_PREVIEW_STALE",
      message: "Bulk transition inputs changed after preview.",
    });
  }
}
