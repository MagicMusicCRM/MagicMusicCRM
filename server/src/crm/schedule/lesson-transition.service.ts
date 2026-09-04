import { Injectable } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import type {
  LessonBulkTransitionCommandDto,
  LessonBulkTransitionPreviewDto,
  LessonCancelCommandDto,
  LessonCancelPreviewDto,
  LessonRescheduleCommandDto,
  LessonReschedulePreviewDto,
  LessonSettleCommandDto,
  LessonSettlePreviewDto,
} from "../dto/lesson-transition.dto";
import { LessonBulkTransitionService } from "./lesson-bulk-transition.service";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonTransitionCommandService } from "./lesson-transition-command.service";
import { LessonTransitionPreviewService } from "./lesson-transition-preview.service";

export type {
  CommittedTransition,
  LessonTransitionPreviewResult,
} from "./lesson-transition.types";
export type { LessonActionableResolution } from "./lesson-actionable-chain.service";

@Injectable()
export class LessonTransitionService {
  constructor(
    private readonly previews: LessonTransitionPreviewService,
    private readonly commands: LessonTransitionCommandService,
    private readonly bulkTransitions: LessonBulkTransitionService,
  ) {}

  previewReschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonReschedulePreviewDto,
  ) {
    return this.previews.previewReschedule(actor, lessonId, dto);
  }

  previewCancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelPreviewDto,
  ) {
    return this.previews.previewCancel(actor, lessonId, dto);
  }

  previewSettle(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlePreviewDto,
  ) {
    return this.previews.previewSettle(actor, lessonId, dto);
  }

  reschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonRescheduleCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.commands.reschedule(actor, lessonId, dto, metadata);
  }

  cancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.commands.cancel(actor, lessonId, dto, metadata);
  }

  settle(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettleCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.commands.settle(actor, lessonId, dto, metadata);
  }

  previewBulk(
    actor: ActorContext,
    dto: LessonBulkTransitionPreviewDto,
  ) {
    return this.bulkTransitions.previewBulk(actor, dto);
  }

  bulk(
    actor: ActorContext,
    dto: LessonBulkTransitionCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.bulkTransitions.bulk(actor, dto, metadata);
  }
}
