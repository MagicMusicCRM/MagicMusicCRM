import { Injectable, NotFoundException } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { DatabaseService } from "../../db/database.service";
import { branchIdExpr, managerBranchScopeSql } from "../branch-scope";
import { CrmPolicy } from "../crm.policy";
import { CrmListQuery } from "../dto/crm-list.query";
import { StudentSearchQuery } from "../dto/student-search.query";
import { assertGroupBranchScope } from "../group-branch-scope";
import { StudentRow, findStudent } from "../student-read";
import {
  StudentGroupRow,
  StudentSearchRow,
  toStudentDto,
  toStudentGroupDto,
  toStudentSearchDto,
} from "./student-presenter";
import { buildStudentSearchFilter } from "./student-search-filter";
import { studentContactEmailSql } from "./student-contact-email";
import { typedClientTableFieldsSql } from "../clients/client-config.repository";

@Injectable()
export class StudentDirectoryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  async listStudents(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanListStudents(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.version, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason,
          p.first_name, p.last_name, ${studentContactEmailSql()} as email,
          p.phone, s.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where s.deleted_at is null
          and (
            ${managerAdminRolesSql("$1")}
            or ($1::text = 'teacher' and tp.user_id = $2)
          )
          and ${managerBranchScopeSql({
            roleExpression: "$1",
            userIdExpression: "$2",
            branchExpression: branchIdExpr("s"),
          })}
          and (
            $3::text is null
            or lower(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || coalesce(${studentContactEmailSql()}, '')) like lower('%' || $3 || '%')
          )
        group by s.id, p.id, u.id
        order by s.created_at desc, s.id desc
        limit $4
      `,
      [actor.role, actor.userId, q || null, limit],
    );

    return { items: result.rows.map((row) => toStudentDto(row)) };
  }

  async searchStudents(actor: ActorContext, query: StudentSearchQuery) {
    this.policy.assertCanListStudents(actor);
    const limit = Math.min(query.limit ?? 50, 500);
    const filter = buildStudentSearchFilter(actor, query);
    const result = await this.database.query<StudentSearchRow>(
      `
        select s.id, s.version, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason,
          ${typedClientTableFieldsSql("student", "s.id")} as table_custom_fields,
          p.first_name, p.last_name, ${studentContactEmailSql()} as email,
          p.phone,
          s.created_at, count(*) over() as total_count,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids,
          ${branchIdExpr("s")} as branch_id,
          b.name as branch_name,
          (
            select count(*)
            from app.group_students active_groups
            where active_groups.student_id = s.id
              and active_groups.left_at is null
          ) as groups_count,
          (
            select count(*)
          from app.canonical_tasks open_task
            where open_task.entity_type = 'student'
              and open_task.entity_id = s.id
              and open_task.deleted_at is null
              and open_task.status in ('open', 'in_progress')
              and exists (
                select 1 from app.shared_task_visibility visibility
                where visibility.task_id = open_task.id
                  and visibility.user_id = $2::uuid
              )
          ) as open_tasks_count,
          (
            select count(*)
            from app.lessons lesson
            where lesson.student_id = s.id
              and lesson.deleted_at is null
          ) as lessons_count,
          (
            select coalesce(sum(payment.amount), 0)
            from app.commerce_ordinary_payments payment
            where payment.student_id = s.id
              and payment.deleted_at is null
          ) as payments_total,
          coalesce(link_user.id, case when u.is_app_account = true then u.id else null end) as linked_user_id,
          coalesce(link_user.email, case when u.is_app_account = true then u.email else null end) as linked_user_email,
          coalesce(link_user.is_app_account, u.is_app_account, false) as is_app_account,
          (
            select coalesce(
              json_agg(json_build_object('id', d.id, 'name', d.name) order by d.name),
              '[]'::json
            )
            from app.student_disciplines sd
            join app.disciplines d on d.id = sd.discipline_id
            where sd.student_id = s.id
          ) as disciplines
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b
          on b.id::text = ${branchIdExpr("s")}
         and b.deleted_at is null
        left join app.user_crm_links link
          on link.entity_type = 'student'
         and link.entity_id = s.id
         and link.deleted_at is null
        left join app.users link_user
          on link_user.id = link.user_id
         and link_user.deleted_at is null
        where ${filter.where}
        group by s.id, p.id, u.id, b.id, link_user.id
        order by ${filter.searchRank ? `${filter.searchRank} asc,` : ""} s.created_at desc, s.id desc
        limit $${filter.params.length + 1}
      `,
      [...filter.params, limit + 1],
    );
    const page = result.rows.slice(0, limit);
    const hasMore = result.rows.length > limit;
    const boundary = page.at(-1);
    return {
      items: page.map((row) => toStudentSearchDto(row)),
      totalCount: Number(result.rows[0]?.total_count ?? page.length),
      nextCursor:
        hasMore && boundary
          ? `${new Date(boundary.created_at).toISOString()}|${boundary.id}`
          : null,
    };
  }

  async getStudent(actor: ActorContext, studentId: string) {
    const student = await findStudent(this.database, studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });
    return toStudentDto(student);
  }

  async listStudentGroups(
    actor: ActorContext,
    studentId: string,
    query: CrmListQuery,
  ) {
    const student = await findStudent(this.database, studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });

    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<StudentGroupRow>(
      `
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.created_at
        from app.group_students gs
        join app.groups g on g.id = gs.group_id and g.deleted_at is null
        left join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = g.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = g.room_id and r.deleted_at is null
        where gs.student_id = $1
          and gs.left_at is null
        order by g.name asc, g.id asc
        limit $2
      `,
      [studentId, limit],
    );

    return { items: result.rows.map((row) => toStudentGroupDto(row)) };
  }

  async listGroupStudents(
    actor: ActorContext,
    groupId: string,
    query: CrmListQuery,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    await assertGroupBranchScope(this.database, actor, groupId);
    const limit = Math.min(query.limit ?? 100, 100);
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.version, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason,
          p.first_name, p.last_name, ${studentContactEmailSql()} as email,
          p.phone, s.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
        from app.group_students gs
        join app.groups g on g.id = gs.group_id and g.deleted_at is null
        join app.students s on s.id = gs.student_id and s.deleted_at is null
        left join app.teachers group_teacher
          on group_teacher.id = g.teacher_id
         and group_teacher.deleted_at is null
        left join app.profiles group_teacher_profile
          on group_teacher_profile.id = group_teacher.profile_id
         and group_teacher_profile.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where gs.group_id = $1
          and gs.left_at is null
          and (
            ${managerAdminRolesSql("$2")}
            or (
              $2::text = 'teacher'
              and group_teacher_profile.user_id = $3
            )
          )
        group by s.id, p.id, u.id
        order by p.last_name nulls last, p.first_name nulls last, s.id
        limit $4
      `,
      [groupId, actor.role, actor.userId, limit],
    );
    return { items: result.rows.map((row) => toStudentDto(row)) };
  }
}
