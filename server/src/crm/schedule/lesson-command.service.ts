import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { LessonConstraintPreviewDto } from "../dto/lesson-constraint-preview.dto";
import {
  LessonSettlementPlanCommandDto,
  LessonSettlementPlanPreviewDto,
} from "../dto/lesson-settlement-plan.dto";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { LessonConstraintPreviewService } from "./lesson-constraint-preview.service";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonPlannedSettlementCommandService } from "./lesson-planned-settlement-command.service";
import { LessonWriteCommandService } from "./lesson-write-command.service";
export type { LessonCommandMetadata } from "./lesson-command-metadata";

@Injectable()
export class LessonCommandService {
  constructor(
    private readonly preview: LessonConstraintPreviewService,
    private readonly write: LessonWriteCommandService,
    private readonly settlement: LessonPlannedSettlementCommandService,
  ) {}

  previewConstraints(actor: ActorContext, dto: LessonConstraintPreviewDto) {
    return this.preview.previewConstraints(actor, dto);
  }

  create(
    actor: ActorContext,
    dto: UpsertLessonDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.write.create(actor, dto, metadata);
  }

  update(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.write.update(actor, lessonId, dto, metadata);
  }

  previewSettlementPlan(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementPlanPreviewDto,
  ) {
    return this.settlement.previewSettlementPlan(actor, lessonId, dto);
  }

  updateSettlementPlan(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlementPlanCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.settlement.updateSettlementPlan(actor, lessonId, dto, metadata);
  }
}
