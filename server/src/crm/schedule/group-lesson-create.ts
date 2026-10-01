import { ConflictException, UnprocessableEntityException } from "@nestjs/common";
import { acquireScheduleLockKeys } from "./schedule-locks";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { assertActiveClientReferences } from "../clients/client-reference.service";
import { assertGroupBranchScope } from "../group-branch-scope";
import type { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import type { LessonRequiredFieldValidator } from "./lesson-required-field.validator";

export async function prepareGroupLessonCreate(client: PoolClient, actor: ActorContext, dto: UpsertLessonDto, validator: LessonRequiredFieldValidator) {
    const groupId = dto.groupId!;
    await assertGroupBranchScope(client, actor, groupId);
    type GroupDefaults = {
      teacher_id: string; branch_id: string; room_id: string;
      settlement_type_key: string | null; teacher_compensation_rule_key: string | null;
    };
    const query = "select teacher_id, branch_id, room_id, settlement_type_key, teacher_compensation_rule_key from app.groups where id = $1 and deleted_at is null";
    const group = (await client.query<GroupDefaults>(query, [groupId])).rows[0];
    if (!group?.settlement_type_key || !group.teacher_compensation_rule_key) {
      throw new UnprocessableEntityException({ code: "GROUP_LESSON_DEFAULTS_REQUIRED" });
    }
    if (dto.branchId && dto.branchId !== group.branch_id) {
      throw new UnprocessableEntityException({ code: "GROUP_BRANCH_MISMATCH" });
    }
    const membershipQuery = "select student_id from app.group_students where group_id = $1 and left_at is null order by student_id";
    const memberIds = (await client.query<{ student_id: string }>(membershipQuery, [groupId])).rows.map(item => item.student_id);
    if (!memberIds.length) throw new UnprocessableEntityException({ code: "GROUP_PARTICIPANTS_REQUIRED" });
    const teacherId = dto.teacherId ?? group.teacher_id;
    const roomId = dto.roomId ?? group.room_id;
    const keys = [
      `branch:${group.branch_id}`, `group:${groupId}`, `room:${roomId}`, `teacher:${teacherId}`,
      ...memberIds.map(id => `client:student:${id}`),
    ].sort();
    await acquireScheduleLockKeys(client, keys);
    const locked = (await client.query<GroupDefaults>(`${query} for share`, [groupId])).rows[0];
    const lockedMembers = (await client.query<{ student_id: string }>(membershipQuery, [groupId])).rows.map(item => item.student_id);
    if (JSON.stringify(group) !== JSON.stringify(locked) || JSON.stringify(memberIds) !== JSON.stringify(lockedMembers)) {
      throw new ConflictException({ code: "GROUP_DEFAULTS_CHANGED" });
    }
    await assertActiveClientReferences(client, memberIds.map(id => ({ type: "student" as const, id })));
    const draft = validator.create({
      ...dto, clientRef: { type: "student", id: memberIds[0]! },
      teacherId, branchId: group.branch_id, roomId,
      clientChargeType: "none", clientChargeValue: 0, subscriptionId: undefined,
      teacherCompensationType: "none", teacherCompensationValue: 0,
      financialDecision: { settlementTypeKey: group.settlement_type_key },
    });
    return {
      draft, memberIds,
      settlementTypeKey: group.settlement_type_key,
      teacherCompensationRuleKey: group.teacher_compensation_rule_key,
    };
  }

