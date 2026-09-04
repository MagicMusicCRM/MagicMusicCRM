import { Injectable } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { DatabaseService } from "../../db/database.service";
import {
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../branch-scope";

export interface StudentLessonTimelineCursor {
  scheduledAt: string;
  id: string;
}

export interface StudentLessonTimelineRow {
  id: string;
  version: string | number;
  scheduled_at: Date | string;
  duration_minutes: number;
  lifecycle_state:
    | "scheduled"
    | "settlement_pending"
    | "successfully_completed"
    | "cancelled"
    | "rescheduled";
  student_id: string;
  student_name: string | null;
  group_id: string | null;
  group_name: string | null;
  teacher_id: string | null;
  teacher_name: string | null;
  room_id: string | null;
  room_name: string | null;
  branch_id: string | null;
  branch_name: string | null;
  origin_kind: "manual" | "generated" | "one_off_exception";
  plan_id: string | null;
  series_id: string | null;
  covered_by_subscription: boolean;
  settlement_type_key: string | null;
  predecessor_id: string | null;
  successor_id: string | null;
  actionable_lesson_id: string;
}

@Injectable()
export class StudentLessonTimelineRepository {
  constructor(private readonly database: DatabaseService) {}

  async listPage(
    actor: ActorContext,
    studentId: string,
    direction: "previous" | "next",
    cursor: StudentLessonTimelineCursor,
    limit: number,
    inclusive = false,
  ): Promise<StudentLessonTimelineRow[]> {
    const comparison = direction === "previous" ? "<" : inclusive ? ">=" : ">";
    const order = direction === "previous" ? "desc" : "asc";
    const databaseRole = currentActorRoleSql("$2");
    const lessonBranch =
      "coalesce(lesson.branch_id::text, lesson_group.branch_id::text, room.branch_id::text)";
    const canSeePayments = `(${managerAdminRolesSql(databaseRole)}
      or ${databaseRole} = 'client')`;
    const result = await this.database.query<StudentLessonTimelineRow>(
      `with recursive visible_student as (
         select student.id,
           profile.user_id as profile_user_id,
           nullif(trim(coalesce(profile.first_name, '') || ' ' || coalesce(profile.last_name, '')), '')
             as student_name
         from app.students student
         left join app.profiles profile
           on profile.id = student.profile_id and profile.deleted_at is null
         where student.id = $3::uuid
           and student.deleted_at is null
           and ${databaseRole} = $1::text
           and (
             ${managerAdminRolesSql(databaseRole)}
             or ${databaseRole} in ('teacher', 'client')
           )
       ),
       student_lesson_ids as (
         select lesson.id
         from visible_student
         join app.lessons lesson on lesson.student_id = visible_student.id
         where lesson.deleted_at is null
         union
         select participant.lesson_id
         from visible_student
         join app.lesson_snapshot_participants participant
           on participant.student_id = visible_student.id
         join app.lessons lesson
           on lesson.id = participant.lesson_id and lesson.deleted_at is null
         where not exists (
           select 1 from app.lesson_participant_exclusions exclusion
           where exclusion.lesson_id = participant.lesson_id
             and exclusion.student_id = participant.student_id
         )
         union
         select lesson.id
         from visible_student
         join app.group_students membership
           on membership.student_id = visible_student.id
         join app.lessons lesson
           on lesson.group_id = membership.group_id and lesson.deleted_at is null
         where membership.joined_at <= lesson.scheduled_at
           and (membership.left_at is null or membership.left_at > lesson.scheduled_at)
           and not exists (
             select 1 from app.lesson_snapshot_participants snapshotted
             where snapshotted.lesson_id = lesson.id
           )
       ),
       lesson_ancestry(root_id, id, predecessor_id, series_id, depth) as (
         select lesson.id, lesson.id, lesson.predecessor_id, lesson.series_id, 0
         from student_lesson_ids target
         join app.lessons lesson on lesson.id = target.id
         union all
         select ancestry.root_id, predecessor.id, predecessor.predecessor_id,
           predecessor.series_id, ancestry.depth + 1
         from lesson_ancestry ancestry
         join app.lessons predecessor on predecessor.id = ancestry.predecessor_id
         where ancestry.depth < 100
       ),
       origin_series_by_lesson as (
         select distinct on (root_id) root_id, series_id
         from lesson_ancestry
         where series_id is not null
         order by root_id, depth asc
       ),
       lesson_successors(root_id, id, successor_id, depth) as (
         select lesson.id, lesson.id, lesson.successor_id, 0
         from student_lesson_ids target
         join app.lessons lesson on lesson.id = target.id
         union all
         select successors.root_id, successor.id, successor.successor_id,
           successors.depth + 1
         from lesson_successors successors
         join app.lessons successor on successor.id = successors.successor_id
         where successors.depth < 100
       ),
       actionable_lesson as (
         select distinct on (root_id) root_id, id
         from lesson_successors
         order by root_id, depth desc
       )
       select lesson.id, lesson.version, lesson.scheduled_at,
         lesson.duration_minutes, lesson.lifecycle_state,
         visible_student.id as student_id,
         visible_student.student_name,
         lesson.group_id, lesson_group.name as group_name,
         lesson.teacher_id,
         nullif(trim(coalesce(teacher_profile.first_name, '') || ' ' ||
           coalesce(teacher_profile.last_name, '')), '') as teacher_name,
         lesson.room_id, room.name as room_name,
         branch.id as branch_id, branch.name as branch_name,
         case
           when lesson.predecessor_id is not null then 'one_off_exception'
           when origin_series.id is null then 'manual'
           when lesson.series_id is null then 'one_off_exception'
           when lesson.teacher_id is distinct from origin_series.teacher_id
             or lesson.room_id is distinct from origin_series.room_id
             or lesson.branch_id is distinct from origin_series.branch_id
             or lesson.duration_minutes is distinct from origin_series.duration_minutes
             or lesson.series_date is distinct from
               timezone(coalesce(branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at)::date
             or timezone(coalesce(branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at)::time
               is distinct from origin_series.begin_time
             then 'one_off_exception'
           else 'generated'
         end as origin_kind,
         plan.id as plan_id, origin_series.id as series_id,
         case when ${canSeePayments} then (
           case when charge.charge_type is not null
             then charge.charge_type = 'subscription'
             else (
               target_funding.charge_type = 'subscription'
               and target_funding.subscription_id is not null
               and exists (
                 select 1
                 from app.lesson_reservations reservation
                 where reservation.lesson_id = lesson.id
                   and reservation.state = 'reserved'
                   and reservation.subscription_id = target_funding.subscription_id
               )
             )
           end
         ) else false end as covered_by_subscription,
         case when ${canSeePayments} then coalesce(
           charge.settlement_type_key,
           participant_decision.item->>'settlementTypeKey',
           effective_decision.decision->>'settlementTypeKey'
         ) else null::text end as settlement_type_key,
         lesson.predecessor_id, lesson.successor_id,
         actionable_lesson.id as actionable_lesson_id
       from visible_student
       join student_lesson_ids target on true
       join app.lessons lesson on lesson.id = target.id
       left join app.groups lesson_group on lesson_group.id = lesson.group_id
       left join app.teachers teacher
         on teacher.id = lesson.teacher_id and teacher.deleted_at is null
       left join app.profiles teacher_profile
         on teacher_profile.id = teacher.profile_id
        and teacher_profile.deleted_at is null
       left join app.rooms room on room.id = lesson.room_id
       left join app.branches branch
         on branch.id = coalesce(lesson.branch_id, lesson_group.branch_id, room.branch_id)
       left join origin_series_by_lesson lineage on lineage.root_id = lesson.id
       left join app.schedule_series origin_series on origin_series.id = lineage.series_id
       left join app.schedule_plans plan on plan.id = origin_series.plan_id
       left join actionable_lesson on actionable_lesson.root_id = lesson.id
       left join app.lesson_settlement_plans settlement_plan
         on settlement_plan.lesson_id = lesson.id
       left join lateral (
         select settlement_correction.decision
         from app.lesson_settlement_corrections settlement_correction
         where settlement_correction.lesson_id = lesson.id
         order by settlement_correction.version desc
         limit 1
       ) correction on true
       left join lateral (
         select fact.charge_type, fact.settlement_type_key
         from app.lesson_client_charge_facts_effective fact
         where fact.lesson_id = lesson.id
           and fact.client_type = 'student'
           and fact.client_id = visible_student.id
         order by fact.created_at desc, fact.id desc
         limit 1
       ) charge on true
       left join lateral (
         select lesson_transition.financial_decision
         from app.lesson_transitions lesson_transition
         where lesson_transition.lesson_id = lesson.id
           and lesson_transition.financial_decision <> '{}'::jsonb
         order by lesson_transition.created_at desc, lesson_transition.id desc
         limit 1
       ) transition on true
       left join lateral (
         select coalesce(
           correction.decision,
           transition.financial_decision,
           settlement_plan.decision
         ) as decision
       ) effective_decision on true
       left join lateral (
         select choice.item
         from jsonb_array_elements(coalesce(
           effective_decision.decision->'clientDecisions',
           '[]'::jsonb
         )) choice(item)
         where choice.item->>'clientId' = visible_student.id::text
         limit 1
       ) participant_decision on true
       left join lateral (
         select source.charge_type, source.subscription_id
         from (
           select participant.charge_type, participant.subscription_id, 1 as priority
           from app.lesson_snapshot_participants participant
           where participant.lesson_id = lesson.id
             and participant.student_id = visible_student.id
             and not exists (
               select 1 from app.lesson_participant_exclusions exclusion
               where exclusion.lesson_id = participant.lesson_id
                 and exclusion.student_id = participant.student_id
             )
           union all
           select snapshot.client_charge_type, snapshot.subscription_id, 2 as priority
           from app.lesson_snapshots snapshot
           where snapshot.lesson_id = lesson.id
             and snapshot.client_type = 'student'
             and snapshot.client_id = visible_student.id
         ) source
         order by source.priority
         limit 1
       ) participant_snapshot on true
       left join lateral (
         select coalesce(
           nullif(participant_decision.item->>'chargeType', ''),
           case when nullif(participant_decision.item->>'subscriptionId', '') is not null
             then 'subscription' end,
           participant_snapshot.charge_type
         ) as charge_type,
         coalesce(
           nullif(participant_decision.item->>'subscriptionId', '')::uuid,
           participant_snapshot.subscription_id
         ) as subscription_id
       ) target_funding on true
       where (lesson.scheduled_at, lesson.id) ${comparison}
         ($4::timestamptz, $5::uuid)
         and (
           ${managerAdminRolesSql(databaseRole)}
           or (${databaseRole} = 'teacher' and teacher_profile.user_id = $2::uuid)
           or (${databaseRole} = 'client' and (
             visible_student.profile_user_id = $2::uuid
             or exists (
               select 1
               from app.user_crm_links student_link
               where student_link.user_id = $2::uuid
                 and student_link.entity_type = 'student'
                 and student_link.entity_id = visible_student.id
                 and student_link.deleted_at is null
             )
             or exists (
               select 1
               from app.profiles account_profile
               join app.family_members account_member
                 on account_member.entity_type = 'profile'
                and account_member.entity_id = account_profile.id
                and account_member.role in ('parent', 'payer')
                and account_member.deleted_at is null
               join app.families family
                 on family.id = account_member.family_id
                and family.deleted_at is null
               join app.family_members student_member
                 on student_member.family_id = family.id
                and student_member.entity_type = 'student'
                and student_member.entity_id = visible_student.id
                and student_member.deleted_at is null
               where account_profile.user_id = $2::uuid
                 and account_profile.deleted_at is null
             )
           ))
         )
         and ${managerBranchScopeSql({
           roleExpression: databaseRole,
           userIdExpression: "$2",
           branchExpression: lessonBranch,
         })}
       order by lesson.scheduled_at ${order}, lesson.id ${order}
       limit $6`,
      [
        actor.role,
        actor.userId,
        studentId,
        cursor.scheduledAt,
        cursor.id,
        limit + 1,
      ],
    );
    return result.rows;
  }
}
