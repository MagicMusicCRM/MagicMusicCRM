import { Injectable } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import type {
  CreateSchedulePlanDto,
  SchedulePlanConstraintPreviewDto,
  SchedulePlanEndCommandDto,
  SchedulePlanEndPreviewDto,
  SchedulePlanQuery,
  SchedulePlanTrayQuery,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import type {
  SchedulePlanRowRemovalCommandDto,
  SchedulePlanRowRemovalPreviewDto,
} from "../dto/schedule-plan-row-removal.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { SchedulePlanConstraintPreviewService } from "./schedule-plan-constraint-preview.service";
import { SchedulePlanEndService } from "./schedule-plan-end.service";
import { SchedulePlanMutationService } from "./schedule-plan-mutation.service";
import { SchedulePlanQueryService } from "./schedule-plan-query.service";
import { SchedulePlanRowRemovalService } from "./schedule-plan-row-removal.service";

@Injectable()
export class SchedulePlanService {
  constructor(
    private readonly queries: SchedulePlanQueryService,
    private readonly previews: SchedulePlanConstraintPreviewService,
    private readonly mutations: SchedulePlanMutationService,
    private readonly ending: SchedulePlanEndService,
    private readonly rowRemovals: SchedulePlanRowRemovalService,
  ) {}

  list(actor: ActorContext, query: SchedulePlanQuery) {
    return this.queries.list(actor, query);
  }

  previewConstraints(
    actor: ActorContext,
    dto: SchedulePlanConstraintPreviewDto,
  ) {
    return this.previews.previewConstraints(actor, dto);
  }

  previewUpdateConstraints(
    actor: ActorContext,
    planId: string,
    dto: UpdateSchedulePlanDto,
  ) {
    return this.previews.previewUpdateConstraints(actor, planId, dto);
  }

  previewEnd(
    actor: ActorContext,
    planId: string,
    dto: SchedulePlanEndPreviewDto,
  ) {
    return this.ending.previewEnd(actor, planId, dto);
  }

  end(
    actor: ActorContext,
    planId: string,
    dto: SchedulePlanEndCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.ending.end(actor, planId, dto, metadata);
  }

  previewRemoveRow(
    actor: ActorContext,
    planId: string,
    seriesId: string,
    dto: SchedulePlanRowRemovalPreviewDto,
  ) {
    return this.rowRemovals.previewRemoveRow(actor, planId, seriesId, dto);
  }

  removeRow(
    actor: ActorContext,
    planId: string,
    seriesId: string,
    dto: SchedulePlanRowRemovalCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.rowRemovals.removeRow(
      actor,
      planId,
      seriesId,
      dto,
      metadata,
    );
  }

  tray(actor: ActorContext, planId: string, query: SchedulePlanTrayQuery) {
    return this.queries.tray(actor, planId, query);
  }

  create(
    actor: ActorContext,
    dto: CreateSchedulePlanDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.mutations.create(actor, dto, metadata);
  }

  update(
    actor: ActorContext,
    planId: string,
    dto: UpdateSchedulePlanDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.mutations.update(actor, planId, dto, metadata);
  }
}
