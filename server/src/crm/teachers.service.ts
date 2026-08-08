import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { managerAdminRolesSql } from "../common/security/role-sql";
import { DatabaseService } from "../db/database.service";
import { CreateTeacherDto } from "./dto/create-teacher.dto";
import { TeacherListQuery } from "./dto/teacher-list.query";
import { UpdateTeacherDto } from "./dto/update-teacher.dto";
import { CrmPolicy } from "./crm.policy";
import {
  rethrowCreatePersonError,
  requiredTrim,
  sanitizeJsonObject,
  trimOptional,
} from "./crm-util";

interface TeacherRow {
  id: string;
  status: string;
  specialization: string | null;
  custom_data?: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  app_role?: string | null;
  is_app_account?: boolean | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  branches?: Array<{ id: string; name: string }> | null;
  students_count?: string | number | null;
  lessons_count?: string | number | null;
  rating?: string | number | null;
  created_at?: Date | string;
  // KVA-238: оклад, актуальная ставка и явные связи (дисциплины/филиалы).
  salary?: string | number | null;
  current_rate?: string | number | null;
  disciplines?: Array<{ id: string; name: string }> | null;
  assigned_branches?: Array<{ id: string; name: string }> | null;
}

/**
 * Teachers domain, extracted from CrmService (SRP): teacher listing (with
 * discipline/level/category/rating/branch/birthday filters + aggregate metadata:
 * branches, student/lesson counts, current rate, disciplines), creation, and
 * update (profile/CRM fields, salary gated to payroll roles, m2m
 * discipline/branch links). Touches `app.teachers` (+ profiles/users/rates/
 * disciplines/branches) and the shared database/audit/policy collaborators. No
 * internal callers.
 */
@Injectable()
export class TeachersService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
  ) {}

  // ponytail: toNumericStat is a tiny coercion copied from CrmService (used 38×
  // there by dashboard/reports). Promote to crm-util if a 3rd owner appears.
  private toNumericStat(value: string | number | null | undefined): number {
    if (value === null || value === undefined) return 0;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }

  private toTeacherDto(row: TeacherRow) {
    const teacher: Record<string, unknown> = {
      id: row.id,
      status: row.status,
      specialization: row.specialization,
      profileId: row.profile_id,
      profileUserId: row.profile_user_id,
      firstName: row.first_name,
      lastName: row.last_name,
      email: row.email,
      phone: row.phone,
    };
    if (row.custom_data !== undefined) {
      teacher.customData = row.custom_data ?? {};
    }
    if (row.app_role !== undefined) {
      teacher.appRole = row.app_role;
    }
    if (row.is_app_account !== undefined) {
      teacher.isAppAccount = row.is_app_account ?? false;
    }
    if (row.branches !== undefined) {
      teacher.branches = row.branches ?? [];
    }
    if (row.students_count !== undefined) {
      teacher.studentsCount = this.toNumericStat(row.students_count);
    }
    if (row.lessons_count !== undefined) {
      teacher.lessonsCount = this.toNumericStat(row.lessons_count);
    }
    if (row.rating !== undefined) {
      teacher.rating =
        row.rating === null || row.rating === undefined
          ? null
          : this.toNumericStat(row.rating);
    }
    if (row.created_at !== undefined) {
      teacher.createdAt = row.created_at;
    }
    // KVA-238: зарплатные поля и явные связи карточки педагога.
    if (row.salary !== undefined) {
      teacher.salary = row.salary === null ? null : Number(row.salary);
    }
    if (row.current_rate !== undefined) {
      teacher.currentRate =
        row.current_rate === null ? null : Number(row.current_rate);
    }
    if (row.disciplines !== undefined) {
      teacher.disciplines = row.disciplines ?? [];
    }
    if (row.assigned_branches !== undefined) {
      teacher.assignedBranches = row.assigned_branches ?? [];
    }
    return teacher;
  }

  // teacherId narrows the very same query (and, crucially, the very same
  // visibility clause) to one row — see getTeacher below.
  async listTeachers(
    actor: ActorContext,
    query: TeacherListQuery,
    teacherId: string | null = null,
  ) {
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<TeacherRow>(
      `
        select t.id, t.status, t.specialization, t.custom_data,
          t.profile_id, p.user_id as profile_user_id, u.role::text as app_role,
          coalesce(u.is_app_account, false) as is_app_account,
          coalesce(p.first_name, t.custom_data->>'firstName') as first_name,
          coalesce(p.last_name, t.custom_data->>'lastName') as last_name,
          u.email, p.phone,
          agg.branches,
          agg.students_count,
          agg.lessons_count,
          -- KVA-238: оклад, актуальная ставка и явные связи для карточки.
          t.salary,
          (
            select tr.rate
            from app.teacher_rates tr
            where tr.teacher_id = t.id and tr.effective_from <= current_date
            order by tr.effective_from desc, tr.created_at desc
            limit 1
          ) as current_rate,
          (
            select coalesce(
              jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name),
              '[]'::jsonb
            )
            from app.teacher_disciplines td
            join app.disciplines d on d.id = td.discipline_id and d.deleted_at is null
            where td.teacher_id = t.id
          ) as disciplines,
          (
            select coalesce(
              jsonb_agg(jsonb_build_object('id', tb_branch.id, 'name', tb_branch.name) order by tb_branch.name),
              '[]'::jsonb
            )
            from app.teacher_branches tb
            join app.branches tb_branch on tb_branch.id = tb.branch_id and tb_branch.deleted_at is null
            where tb.teacher_id = t.id
          ) as assigned_branches,
          case
            when t.custom_data->>'rating' ~ '^-?[0-9]+(\\.[0-9]+)?$'
              then (t.custom_data->>'rating')::numeric
            else null
          end as rating,
          t.created_at
        from app.teachers t
        left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join lateral (
          select
            coalesce(
              (
                select jsonb_agg(distinct jsonb_build_object('id', br.id, 'name', br.name))
                  filter (where br.id is not null)
                from (
                  select b.id, b.name
                  from app.groups gb
                  join app.branches b on b.id = gb.branch_id and b.deleted_at is null
                  where gb.teacher_id = t.id and gb.deleted_at is null
                  union
                  select b.id, b.name
                  from app.lessons lb
                  join app.branches b on b.id = lb.branch_id and b.deleted_at is null
                  where lb.teacher_id = t.id and lb.deleted_at is null
                ) br
              ),
              '[]'::jsonb
            ) as branches,
            (
              select count(*)
              from (
                select l.student_id
                from app.lessons l
                where l.teacher_id = t.id
                  and l.student_id is not null
                  and l.deleted_at is null
                union
                select gs.student_id
                from app.groups g
                join app.group_students gs on gs.group_id = g.id and gs.left_at is null
                where g.teacher_id = t.id
                  and gs.student_id is not null
                  and g.deleted_at is null
              ) teacher_students
            ) as students_count,
            (
              select count(*)
              from app.lessons lesson_count
              where lesson_count.teacher_id = t.id
                and lesson_count.deleted_at is null
            ) as lessons_count
        ) agg on true
        where t.deleted_at is null
          and (
            ${managerAdminRolesSql("$1")}
            or ($1::text = 'teacher' and p.user_id = $2)
            or ($1::text = 'client' and (
              exists (
                select 1
                from app.lessons cl
                join app.students cs on cs.id = cl.student_id and cs.deleted_at is null
                join app.profiles csp on csp.id = cs.profile_id and csp.deleted_at is null
                where cl.teacher_id = t.id and cl.deleted_at is null and csp.user_id = $2
              )
              or exists (
                select 1
                from app.groups cg
                join app.group_students cgs on cgs.group_id = cg.id and cgs.left_at is null
                join app.students cgst on cgst.id = cgs.student_id and cgst.deleted_at is null
                join app.profiles cgsp on cgsp.id = cgst.profile_id and cgsp.deleted_at is null
                where cg.teacher_id = t.id and cg.deleted_at is null and cgsp.user_id = $2
              )
            ))
          )
          and (
            $3::text is null
            or lower(
              coalesce(p.first_name, '') || ' ' ||
              coalesce(p.last_name, '') || ' ' ||
              coalesce(u.email, '') || ' ' ||
              coalesce(p.phone, '') || ' ' ||
              coalesce(t.specialization, '') || ' ' ||
              coalesce(t.custom_data::text, '')
            ) like lower('%' || $3 || '%')
          )
          and ($4::text is null or t.status = $4)
          and (
            $5::uuid is null
            or exists (
              select 1
              from app.teacher_branches assignment
              where assignment.teacher_id = t.id
                and assignment.branch_id = $5
            )
          )
          and (
            $6::text is null
            or lower(concat_ws(' ',
              t.specialization,
              t.custom_data->>'discipline',
              t.custom_data->>'disciplineName',
              t.custom_data->>'discipline_name',
              t.custom_data->>'disciplines'
            )) like lower('%' || $6 || '%')
          )
          and (
            $7::text is null
            or lower(concat_ws(' ',
              t.custom_data->>'level',
              t.custom_data->>'levelName',
              t.custom_data->>'level_name',
              t.custom_data->>'levels'
            )) like lower('%' || $7 || '%')
          )
          and (
            $8::text is null
            or lower(concat_ws(' ',
              t.custom_data->>'category',
              t.custom_data->>'categoryName',
              t.custom_data->>'category_name',
              t.custom_data->>'maturity',
              t.custom_data->>'maturities',
              t.custom_data->>'categories'
            )) like lower('%' || $8 || '%')
          )
          and ($9::text is null or u.role::text = $9)
          and (
            $10::text is null
            or ($10 = 'app' and coalesce(u.is_app_account, false) = true)
            or ($10 = 'technical' and coalesce(u.is_app_account, false) = false)
            or ($10 = 'linked' and exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'teacher'
                and link.entity_id = t.id
                and link.deleted_at is null
            ))
            or ($10 = 'unlinked' and not exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'teacher'
                and link.entity_id = t.id
                and link.deleted_at is null
            ))
          )
          and (
            $11::numeric is null
            or (
              case
                when t.custom_data->>'rating' ~ '^-?[0-9]+(\\.[0-9]+)?$'
                  then (t.custom_data->>'rating')::numeric
                else null
              end
            ) >= $11
          )
          and (
            $12::numeric is null
            or (
              case
                when t.custom_data->>'rating' ~ '^-?[0-9]+(\\.[0-9]+)?$'
                  then (t.custom_data->>'rating')::numeric
                else null
              end
            ) <= $12
          )
          and (
            $13::int is null
            or (
              case
                when p.dob is not null then extract(month from p.dob)::int
                when coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
                  then extract(month from coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date')::date)::int
                when coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date') ~ '^[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}$'
                  then extract(month from to_date(coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date'), 'DD.MM.YYYY'))::int
                else null
              end
            ) = $13
          )
          and ($15::uuid is null or t.id = $15)
        order by p.last_name nulls last, p.first_name nulls last, t.id
        limit $14
      `,
      [
        actor.role,
        actor.userId,
        q || null,
        query.status ?? null,
        query.branchId ?? null,
        query.discipline ?? null,
        query.level ?? null,
        query.category ?? null,
        query.appRole ?? null,
        query.authorization ?? null,
        query.ratingFrom ?? null,
        query.ratingTo ?? null,
        query.birthdayMonth ?? null,
        limit,
        teacherId,
      ],
    );

    return { items: result.rows.map((row) => this.toTeacherDto(row)) };
  }

  // Single teacher by id. Deliberately routed through listTeachers so the
  // role visibility clause is shared verbatim: a client who may not see this
  // teacher in the list gets a 404 here too, instead of a second, divergent
  // copy of the rules. The list endpoint caps at 100 rows, so scanning it
  // client-side would silently miss teachers.
  async getTeacher(actor: ActorContext, teacherId: string) {
    const { items } = await this.listTeachers(
      actor,
      { limit: 1 } as TeacherListQuery,
      teacherId,
    );
    const teacher = items[0];
    if (!teacher) throw new NotFoundException("Преподаватель не найден.");
    return teacher;
  }

  async createTeacher(actor: ActorContext, dto: CreateTeacherDto) {
    this.policy.assertCanWriteCrm(actor);
    const firstName = requiredTrim(
      dto.firstName,
      "Имя преподавателя обязательно.",
    );
    const lastName = trimOptional(dto.lastName);
    const phone = trimOptional(dto.phone);
    const email = trimOptional(dto.email)?.toLowerCase() ?? null;
    const specialization = trimOptional(dto.specialization);
    const status = trimOptional(dto.status) ?? "active";
    const fullName = [firstName, lastName].filter(Boolean).join(" ");

    try {
      const result = await this.database.query<TeacherRow>(
        `
          with identity as (
            select coalesce($3::text, 'teacher-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid') as email
          ),
          inserted_user as (
            insert into app.users (email, full_name, phone, role, profile_completed, is_app_account)
            select identity.email, $4, $5, 'teacher'::app.user_role, false, false
            from identity
            returning id, email
          ),
          inserted_profile as (
            insert into app.profiles (user_id, first_name, last_name, phone)
            select id, $1, $2, $5
            from inserted_user
            returning id, user_id, first_name, last_name, phone
          ),
          inserted_teacher as (
            insert into app.teachers (profile_id, status, specialization)
            select id, $6, $7
            from inserted_profile
            returning id, status, specialization, profile_id
          )
          select t.id, t.status, t.specialization, t.profile_id,
            p.user_id as profile_user_id, p.first_name, p.last_name, u.email, p.phone
          from inserted_teacher t
          join inserted_profile p on p.id = t.profile_id
          join inserted_user u on u.id = p.user_id
          limit 1
        `,
        [firstName, lastName, email, fullName, phone, status, specialization],
      );
      const teacher = result.rows[0];
      await this.audit.record({
        actor,
        action: "crm.teacher_created",
        entityType: "teacher",
        entityId: teacher.id,
      });
      return this.toTeacherDto(teacher);
    } catch (error) {
      rethrowCreatePersonError(error);
    }
  }

  async updateTeacher(
    actor: ActorContext,
    teacherId: string,
    dto: UpdateTeacherDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    // KVA-238: оклад — зарплатное поле, правится только ролями payroll.
    if (dto.salary !== undefined) this.policy.assertCanReadPayroll(actor);
    // KVA-238: custom-поля карточки (birthday, workStartDate, level, category,
    // isPartTime, isBlacklisted) патчатся merge'ем — по образцу updateStudent.
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
    const result = await this.database.query<TeacherRow>(
      `
        with target as (
          select t.id, t.profile_id, p.user_id
          from app.teachers t
          left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
          where t.id = $1 and t.deleted_at is null
          limit 1
        ),
        updated_profile as (
          update app.profiles p
          set first_name = coalesce($2, p.first_name),
            last_name = coalesce($3, p.last_name),
            phone = coalesce($4, p.phone),
            updated_at = now()
          from target
          where p.id = target.profile_id
          returning p.id, p.user_id, p.first_name, p.last_name, p.phone
        ),
        updated_user as (
          update app.users u
          set email = coalesce($5, u.email),
            updated_at = now()
          from target
          where u.id = target.user_id
          returning u.id, u.email
        ),
        updated_teacher as (
          update app.teachers t
          set status = coalesce($6, t.status),
            specialization = coalesce($7, t.specialization),
            custom_data = coalesce(t.custom_data, '{}'::jsonb) || $8::jsonb,
            salary = coalesce($9::numeric, t.salary),
            updated_at = now()
          from target
          where t.id = target.id
          returning t.id, t.status, t.specialization, t.custom_data, t.salary,
            t.profile_id
        )
        select ut.id, ut.status, ut.specialization, ut.custom_data, ut.salary,
          ut.profile_id,
          coalesce(updated_profile_dependency.user_id, p.user_id) as profile_user_id,
          coalesce(updated_profile_dependency.first_name, p.first_name) as first_name,
          coalesce(updated_profile_dependency.last_name, p.last_name) as last_name,
          coalesce(updated_user_dependency.email, u.email) as email,
          coalesce(updated_profile_dependency.phone, p.phone) as phone
        from updated_teacher ut
        left join updated_profile updated_profile_dependency on true
        left join updated_user updated_user_dependency on true
        left join app.profiles p on p.id = ut.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        limit 1
      `,
      [
        teacherId,
        trimOptional(dto.firstName),
        trimOptional(dto.lastName),
        trimOptional(dto.phone),
        trimOptional(dto.email)?.toLowerCase() ?? null,
        trimOptional(dto.status),
        trimOptional(dto.specialization),
        JSON.stringify(customDataPatch),
        dto.salary ?? null,
      ],
    );
    const teacher = result.rows[0];
    if (!teacher) throw new NotFoundException("Преподаватель не найден.");
    // KVA-238: полная замена m2m-связей, если списки переданы. delete+insert
    // идемпотентен и проще диффа; объёмы — единицы строк на педагога.
    if (dto.disciplineIds) {
      await this.database.query(
        `delete from app.teacher_disciplines
         where teacher_id = $1 and not (discipline_id = any($2::uuid[]))`,
        [teacherId, dto.disciplineIds],
      );
      if (dto.disciplineIds.length) {
        await this.database.query(
          `insert into app.teacher_disciplines (teacher_id, discipline_id)
           select $1, unnest($2::uuid[])
           on conflict do nothing`,
          [teacherId, dto.disciplineIds],
        );
      }
    }
    if (dto.branchIds) {
      await this.database.query(
        `delete from app.teacher_branches
         where teacher_id = $1 and not (branch_id = any($2::uuid[]))`,
        [teacherId, dto.branchIds],
      );
      if (dto.branchIds.length) {
        await this.database.query(
          `insert into app.teacher_branches (teacher_id, branch_id)
           select $1, unnest($2::uuid[])
           on conflict do nothing`,
          [teacherId, dto.branchIds],
        );
      }
    }
    await this.audit.record({
      actor,
      action: "crm.teacher_updated",
      entityType: "teacher",
      entityId: teacher.id,
    });
    return this.toTeacherDto(teacher);
  }
}
