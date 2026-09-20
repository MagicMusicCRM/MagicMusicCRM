import { Injectable, Optional } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { acquireLessonSettlementCoordinationGate } from "../commerce/lesson-settlement-locks";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { CrmPolicy } from "../crm.policy";
import type {
  LessonCancelPreviewDto,
  LessonReschedulePreviewDto,
  LessonSettlePreviewDto,
} from "../dto/lesson-transition.dto";
import { normalizeRescheduleDto } from "../dto/lesson-transition.dto";
import { LessonActionableChainService } from "./lesson-actionable-chain.service";
import { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import { assertTransitionReason } from "./lesson-transition.rules";
import type {
  LessonTransitionPreviewResult,
  TransitionOperation,
  TransitionPreviewDto,
} from "./lesson-transition.types";

@Injectable()
export class LessonTransitionPreviewService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly preparation: LessonTransitionPreparationService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    @Optional()
    private readonly actionableChains?: LessonActionableChainService,
  ) {}

  previewReschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonReschedulePreviewDto,
  ): Promise<LessonTransitionPreviewResult> {
    return this.preview(actor, lessonId, normalizeRescheduleDto(dto), "reschedule");
  }

  previewCancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelPreviewDto,
  ): Promise<LessonTransitionPreviewResult> {
    return this.preview(
      actor,
      lessonId,
      { ...dto, operation: "cancel" },
      "cancel",
    );
  }

  previewSettle(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlePreviewDto,
  ): Promise<LessonTransitionPreviewResult> {
    return this.preview(
      actor,
      lessonId,
      { ...dto, operation: "settle" },
      "settle",
    );
  }

  private async preview(
    actor: ActorContext,
    lessonId: string,
    dto: TransitionPreviewDto,
    operation: TransitionOperation,
  ): Promise<LessonTransitionPreviewResult> {
    this.policy.assertCanWriteCrm(actor);
    assertTransitionReason(dto, operation);
    return this.database.transaction(async (client) => {
      if (operation === "reschedule") {
        await acquireLessonSettlementCoordinationGate(client);
      }
      const resolution = this.actionableChains
        ? await this.actionableChains.resolve(actor, lessonId, client)
        : {
            requestedLessonId: lessonId,
            actionableLessonId: lessonId,
            chainIds: [lessonId],
            redirected: false,
          };
      const calculated = await this.preparation.calculatePreview(
        client,
        actor,
        resolution.actionableLessonId,
        dto,
        operation,
      );
      const { transitionFingerprint, ...calculatedPreview } = calculated;
      const preview = {
        ...calculatedPreview,
        requestedLessonId: resolution.requestedLessonId,
        actionableLessonId: resolution.actionableLessonId,
        redirected: resolution.redirected,
      };
      if (!calculated.canConfirm || !transitionFingerprint) return preview;
      const signed = this.previewTokens.issueLessonTransition({
        kind: "lesson.transition",
        operation,
        actorUserId: actor.userId,
        lessonId: resolution.actionableLessonId,
        expectedVersion: dto.expectedVersion,
        transitionFingerprint,
      });
      return {
        ...preview,
        previewToken: signed.token,
        previewExpiresAt: signed.expiresAt,
      };
    });
  }
}
