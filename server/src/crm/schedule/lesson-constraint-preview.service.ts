import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { DatabaseService } from "../../db/database.service";
import { assertGroupBranchScope } from "../group-branch-scope";
import { groupScheduleConflicts } from "./schedule-analyzer";
import { ActorContext } from "../../common/security/actor-context";
import { CrmPolicy } from "../crm.policy";
import { LessonConstraintPreviewDto } from "../dto/lesson-constraint-preview.dto";
import { ScheduleConstraintEngine } from "./constraint-engine.service";

@Injectable()
export class LessonConstraintPreviewService {
  constructor(
    private readonly policy: CrmPolicy,
    private readonly constraints: ScheduleConstraintEngine,
    private readonly database: DatabaseService,
  ) {}

  async previewConstraints(actor: ActorContext, dto: LessonConstraintPreviewDto) {
    this.policy.assertCanWriteCrm(actor);
    if (Boolean(dto.clientRef) === Boolean(dto.groupId)) {
      throw new UnprocessableEntityException({ code: "LESSON_SUBJECT_REQUIRED" });
    }
    const startAt = new Date(dto.scheduledAt);
    const endAt = new Date(startAt.getTime() + dto.durationMinutes * 60_000);
    const draft = {
      clientRef: dto.clientRef!,
      teacherId: dto.teacherId,
      branchId: dto.branchId,
      roomId: dto.roomId,
      startAt,
      endAt,
      excludeLessonId: dto.excludeLessonId,
    };
    if (dto.groupId) {
      await assertGroupBranchScope(this.database, actor, dto.groupId);
      const members = await this.database.query<{ student_id: string }>(
        "select membership.student_id from app.group_students membership join app.groups target on target.id = membership.group_id and target.deleted_at is null where membership.group_id = $1 and membership.left_at is null order by membership.student_id",
        [dto.groupId],
      );
      if (!members.rows.length) throw new UnprocessableEntityException({ code: "GROUP_PARTICIPANTS_REQUIRED" });
      const results = await Promise.all(members.rows.map(member => this.constraints.validate({
        ...draft, clientRef: { type: "student", id: member.student_id },
      })));
      const violations = results.flatMap(result => result.violations);
      return { valid: results.every(result => result.valid), violations,
        conflicts: groupScheduleConflicts(violations.map(violation => ({ violation }))), suggestions: [] };
    }
    return dto.includeSuggestions === false
      ? this.constraints.validate(draft)
      : this.constraints.analyze(draft);
  }
}
