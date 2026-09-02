import { NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { currentActorRoleSql, managerBranchScopeSql } from "../branch-scope";
import type { LessonFinancialDecision } from "../commerce/lesson-settlement.port";
import type { LessonResourcesDto } from "../dto/lesson-resources.dto";
import type { ScheduleConstraintEngine } from "./constraint-engine.service";

/** Runs inside the existing signed settlement transaction and its savepoint preview. */
export async function applyLessonResourceEdit(
  client: PoolClient,
  actor: ActorContext,
  lessonId: string,
  resources: LessonResourcesDto | undefined,
  constraints: ScheduleConstraintEngine,
) {
  const scope = (branch: string) => managerBranchScopeSql({
    roleExpression: currentActorRoleSql("$2"),
    userIdExpression: "$2",
    branchExpression: branch,
  });
  const result = await client.query<{
    teacher_id: string; branch_id: string; room_id: string;
    scheduled_at: Date | string; duration_minutes: number;
    teacher_rate_snapshot: LessonFinancialDecision["teacherRateSnapshot"] | null;
  }>(
    `select lesson.teacher_id, lesson.branch_id, lesson.room_id,
       lesson.scheduled_at, lesson.duration_minutes,
       coalesce((select correction.decision -> 'teacherRateSnapshot'
         from app.lesson_settlement_corrections correction
         where correction.lesson_id = lesson.id order by version desc limit 1),
         (select plan.decision -> 'teacherRateSnapshot'
          from app.lesson_settlement_plans plan where plan.lesson_id = lesson.id))
         as teacher_rate_snapshot
     from app.lessons lesson where lesson.id = $1 and lesson.deleted_at is null
       and ${scope("lesson.branch_id::text")}
       and ($3::uuid is null or ${scope("$3::text")})
     for update of lesson`,
    [lessonId, actor.userId, resources?.branchId ?? null],
  );
  const source = result.rows[0];
  if (!source) throw new NotFoundException("Урок или филиал недоступен.");
  const before = { teacherId: source.teacher_id, branchId: source.branch_id, roomId: source.room_id };
  const changed = resources && Object.entries(before).some(
    ([key, value]) => resources[key as keyof LessonResourcesDto] !== value,
  );
  let teacherRateSnapshot = source.teacher_rate_snapshot ?? undefined;
  if (!changed) return { branchId: source.branch_id, teacherRateSnapshot, change: null };

  const participants = await client.query<{ type: "student" | "lead"; id: string }>(
    `select client_type as type, client_id as id from app.lesson_snapshots
     where lesson_id = $1 and group_id is null
     union all
     select 'student', student_id from app.lesson_snapshot_participants participant
     where lesson_id = $1 and not exists (
       select 1 from app.lesson_participant_exclusions exclusion
       where exclusion.lesson_id = participant.lesson_id
         and exclusion.student_id = participant.student_id)
     order by id`, [lessonId],
  );
  const keys = [...new Set([
    `branch:${resources.branchId}`,
    `teacher:${before.teacherId}`, `teacher:${resources.teacherId}`,
    `room:${before.roomId}`, `room:${resources.roomId}`,
    ...participants.rows.map((item) => `client:${item.type}:${item.id}`),
  ])].sort();
  for (const key of keys) {
    await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [key]);
  }
  if (!participants.rows.length) throw new UnprocessableEntityException({ code: "LESSON_SNAPSHOT_INCOMPLETE" });
  for (const participant of participants.rows) {
    const validation = await constraints.validate({
      clientRef: participant,
      ...resources,
      startAt: new Date(source.scheduled_at).toISOString(),
      endAt: new Date(new Date(source.scheduled_at).getTime() + source.duration_minutes * 60000).toISOString(),
      excludeLessonId: lessonId,
    }, client);
    if (!validation.valid) throw new UnprocessableEntityException({
      code: "LESSON_CONSTRAINT_VIOLATIONS", violations: validation.violations,
    });
  }
  if (before.teacherId !== resources.teacherId) {
    const rate = await client.query<{ rate: string }>(
      `select coalesce((select rate from app.teacher_rates where teacher_id = $1
         and deleted_at is null and effective_from <= $2::timestamptz::date
         order by effective_from desc, created_at desc limit 1), 0)::text as rate`,
      [resources.teacherId, source.scheduled_at],
    );
    teacherRateSnapshot = { type: "hourly", value: rate.rows[0]!.rate };
  }
  await client.query(
    `update app.lessons set teacher_id = $2, branch_id = $3, room_id = $4,
       teacher_rate = coalesce($5::numeric, teacher_rate), updated_at = now()
     where id = $1`,
    [lessonId, resources.teacherId, resources.branchId, resources.roomId,
      before.teacherId !== resources.teacherId ? teacherRateSnapshot!.value : null],
  );
  return { branchId: resources.branchId, teacherRateSnapshot, change: { before, after: resources } };
}
