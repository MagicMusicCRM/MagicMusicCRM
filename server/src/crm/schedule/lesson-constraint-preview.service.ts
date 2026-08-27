import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { CrmPolicy } from "../crm.policy";
import { LessonConstraintPreviewDto } from "../dto/lesson-constraint-preview.dto";
import { ScheduleConstraintEngine } from "./constraint-engine.service";

@Injectable()
export class LessonConstraintPreviewService {
  constructor(
    private readonly policy: CrmPolicy,
    private readonly constraints: ScheduleConstraintEngine,
  ) {}

  previewConstraints(actor: ActorContext, dto: LessonConstraintPreviewDto) {
    this.policy.assertCanWriteCrm(actor);
    const startAt = new Date(dto.scheduledAt);
    const endAt = new Date(startAt.getTime() + dto.durationMinutes * 60_000);
    return this.constraints.analyze({
      clientRef: dto.clientRef,
      teacherId: dto.teacherId,
      branchId: dto.branchId,
      roomId: dto.roomId,
      startAt,
      endAt,
      excludeLessonId: dto.excludeLessonId,
    });
  }
}
