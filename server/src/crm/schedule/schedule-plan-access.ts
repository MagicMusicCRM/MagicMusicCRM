import { NotFoundException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import {
  branchIdExpr,
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../branch-scope";
import type { SchedulePlanValidationInput } from "./schedule-plan-definition.types";

const managementRoleSql = (actor: string) =>
  `${currentActorRoleSql(actor)} = any(array['admin','manager','director','system_admin'])`;

/** Every branch represented by the aggregate must be inside delegated scope. */
export function schedulePlanBranchScopeSql(
  plan: string,
  actor: string,
): string {
  const role = currentActorRoleSql(actor);
  return `(${role} <> all(array['admin','manager']::text[]) or (
    (exists (select 1 from app.students scope_subject where scope_subject.id = ${plan}.student_id)
      or exists (select 1 from app.groups scope_subject where scope_subject.id = ${plan}.group_id))
    and not exists (
      select 1 from (
        select scope_series.branch_id::text as branch_id from app.schedule_series scope_series
          where scope_series.plan_id = ${plan}.id
        union all
        select scope_lesson.branch_id::text from app.lessons scope_lesson
          join app.schedule_series scope_series on scope_series.id = scope_lesson.series_id
          where scope_series.plan_id = ${plan}.id
        union all
        select ${branchIdExpr("scope_student")} from app.students scope_student
          where scope_student.id = ${plan}.student_id or exists (
            select 1 from app.schedule_plan_participants scope_participant
            where scope_participant.plan_id = ${plan}.id
              and scope_participant.student_id = scope_student.id)
        union all
        select scope_group.branch_id::text from app.groups scope_group where scope_group.id = ${plan}.group_id
      ) scope_branches
      where not coalesce(${managerBranchScopeSql({
        roleExpression: role,
        userIdExpression: actor,
        branchExpression: "scope_branches.branch_id",
      })}, false)
    )
  ))`;
}

export const schedulePlanWriteScopeSql = (plan: string, actor: string) =>
  `(${managementRoleSql(actor)} and ${schedulePlanBranchScopeSql(plan, actor)})`;

/** Hold the identities/assignments used by authorization until command commit. */
export async function lockSchedulePlanActorScope(
  client: PoolClient,
  actor: ActorContext,
) {
  await client.query(
    "select id from app.users where id=$1 and deleted_at is null for share",
    [actor.userId],
  );
  await client.query(
    `select scope_assignment.id
    from app.user_crm_links scope_link
    join app.staff_members scope_staff on scope_staff.id=scope_link.entity_id
      and scope_link.entity_type='staff' and scope_link.deleted_at is null and scope_staff.deleted_at is null
    join app.staff_branch_assignments scope_assignment on scope_assignment.staff_member_id=scope_staff.id
      and scope_assignment.deleted_at is null
    where scope_link.user_id=$1 order by scope_assignment.id
    for share of scope_link, scope_staff, scope_assignment`,
    [actor.userId],
  );
}

export async function assertSchedulePlanDraftScope(
  client: PoolClient,
  actor: ActorContext,
  input: SchedulePlanValidationInput,
) {
  await lockSchedulePlanActorScope(client, actor);
  const students =
    input.kind === "individual"
      ? [input.studentId!]
      : input.participants.map((p) => p.studentId);
  const role = currentActorRoleSql("$1");
  const result = await client.query<{ allowed: boolean }>(
    `select
    ${managementRoleSql("$1")} and not exists (
      select 1 from (
        select unnest($2::text[]) as branch_id
        union all select ${branchIdExpr("scope_student")} from app.students scope_student
          where scope_student.id=any($3::uuid[])
        union all select branch_id::text from app.groups where id=$4::uuid
      ) scope_branches
      where not coalesce(${managerBranchScopeSql({
        roleExpression: role,
        userIdExpression: "$1",
        branchExpression: "scope_branches.branch_id",
      })},false)
    ) as allowed`,
    [
      actor.userId,
      input.rows.map((row) => row.branchId),
      students,
      input.groupId,
    ],
  );
  if (!result.rows[0]?.allowed)
    throw new NotFoundException("План расписания не найден.");
}
