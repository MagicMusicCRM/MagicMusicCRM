import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { managerAdminRolesSql } from "../common/security/role-sql";
import { DatabaseService } from "../db/database.service";
import { CreateTeacherDto } from "./dto/create-teacher.dto";
import { ProvisionPersonAccessDto } from "./dto/provision-person-access.dto";
import { TeacherListQuery } from "./dto/teacher-list.query";
import { UpdateTeacherDto } from "./dto/update-teacher.dto";
import { CrmPolicy } from "./crm.policy";
import {
  rethrowCreatePersonError,
  requiredTrim,
  sanitizeJsonObject,
  trimOptional,
} from "./crm-util";
import { assertSettingsBranchScope } from "./settings-branch-scope";
import { presentableEmail } from "./crm-mappers";
import { PersonAccountService } from "./person-account.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import {
  assertVersionedMutationMetadata,
  VersionedMutationMetadata,
} from "../platform/versioned-mutation-metadata";

interface TeacherRow {
  id: string;
  status: string;
  specialization: string | null;
  custom_data?: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  app_role?: string | null;
  is_app_account?: boolean | null;
  password_configured?: boolean | null;
  password_changed_at?: Date | string | null;
  email_changed_at?: Date | string | null;
  lifecycle_state?: "active" | "archived";
  version?: number | string;
  offboarded_at?: Date | string | null;
  offboard_reason?: string | null;
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
  disciplines?: Array<{
    id: string;
    name: string;
    lifecycleState?: "active" | "archived";
  }> | null;
  assigned_branches?: Array<{ id: string; name: string }> | null;
}

type TeacherUpdateExecutor = (
  query: string,
  params: unknown[],
) => Promise<{ rows: TeacherRow[] }>;

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
    private readonly accounts: PersonAccountService,
    private readonly integrity: PlatformIntegrityService,
  ) {}

  // ponytail: toNumericStat is a tiny coercion copied from CrmService (used 38×
  // there by dashboard/reports). Promote to crm-util if a 3rd owner appears.
  private toNumericStat(value: string | number | null | undefined): number {
    if (value === null || value === undefined) return 0;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }

  private toTeacherDto(row: TeacherRow, actor: ActorContext): Record<string, unknown> {
    const canReadCredentials =
      actor.role === "director" || actor.role === "system_admin";
    return {
      id: row.id,
      status: row.status,
      specialization: row.specialization,
      profileId: row.profile_id,
      profileUserId: row.profile_user_id,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      ...this.teacherCredentials(row, canReadCredentials),
      ...this.teacherAccountAndLifecycle(row),
      ...this.teacherStatistics(row),
      ...this.teacherCompensationAndRelations(row),
    };
  }

  private teacherCredentials(
    row: TeacherRow,
    canReadCredentials: boolean,
  ): Record<string, unknown> {
    if (!canReadCredentials) return {};
    return {
      email: presentableEmail(row.email),
      passwordConfigured: row.password_configured ?? false,
      passwordChangedAt: row.password_changed_at ?? null,
      emailChangedAt: row.email_changed_at ?? null,
    };
  }

  private teacherAccountAndLifecycle(
    row: TeacherRow,
  ): Record<string, unknown> {
    const account: Record<string, unknown> = {};
    if (row.custom_data !== undefined) {
      account.customData = row.custom_data ?? {};
    }
    if (row.app_role !== undefined) {
      account.appRole = row.app_role;
    }
    if (row.is_app_account !== undefined) {
      account.isAppAccount = row.is_app_account ?? false;
    }
    account.lifecycleState = row.lifecycle_state ?? "active";
    account.version = Number(row.version ?? 1);
    account.offboardedAt = row.offboarded_at ?? null;
    account.offboardReason = row.offboard_reason ?? null;
    return account;
  }

  private teacherStatistics(row: TeacherRow): Record<string, unknown> {
    const statistics: Record<string, unknown> = {};
    if (row.branches !== undefined) {
      statistics.branches = row.branches ?? [];
    }
    if (row.students_count !== undefined) {
      statistics.studentsCount = this.toNumericStat(row.students_count);
    }
    if (row.lessons_count !== undefined) {
      statistics.lessonsCount = this.toNumericStat(row.lessons_count);
    }
    if (row.rating === null) {
      statistics.rating = null;
    } else if (row.rating !== undefined) {
      statistics.rating = this.toNumericStat(row.rating);
    }
    if (row.created_at !== undefined) {
      statistics.createdAt = row.created_at;
    }
    return statistics;
  }

  private teacherCompensationAndRelations(
    row: TeacherRow,
  ): Record<string, unknown> {
    const compensation: Record<string, unknown> = {};
    // KVA-238: зарплатные поля и явные связи карточки педагога.
    if (row.salary === null) {
      compensation.salary = null;
    } else if (row.salary !== undefined) {
      compensation.salary = Number(row.salary);
    }
    if (row.current_rate === null) {
      compensation.currentRate = null;
    } else if (row.current_rate !== undefined) {
      compensation.currentRate = Number(row.current_rate);
    }
    if (row.disciplines !== undefined) {
      compensation.disciplines = row.disciplines ?? [];
    }
    if (row.assigned_branches !== undefined) {
      compensation.assignedBranches = row.assigned_branches ?? [];
    }
    return compensation;
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
          u.password_hash is not null as password_configured,
          u.password_changed_at, u.email_changed_at,
          t.lifecycle_state, t.version, t.offboarded_at, t.offboard_reason,
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
              where tr.teacher_id = t.id and tr.deleted_at is null
                and tr.effective_from <= current_date
              order by tr.effective_from desc, tr.created_at desc, tr.id desc
            limit 1
          ) as current_rate,
          (
            select coalesce(
              jsonb_agg(jsonb_build_object(
                'id', d.id,
                'name', d.name,
                'lifecycleState', d.lifecycle_state
              ) order by d.name),
              '[]'::jsonb
            )
            from app.teacher_disciplines td
            join app.disciplines d on d.id = td.discipline_id
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
              and tb.active_from <= current_date
              and (tb.active_until is null or tb.active_until >= current_date)
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
              case when $1::text in ('director', 'system_admin')
                then coalesce(u.email, '') else '' end || ' ' ||
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
                and assignment.active_from <= current_date
                and (assignment.active_until is null or assignment.active_until >= current_date)
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

    return { items: result.rows.map((row) => this.toTeacherDto(row, actor)) };
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
    this.policy.assertCanManageSystemSettings(actor);
    const accessRole = this.accounts.resolveInitialRole(
      actor,
      "teacher",
      dto.accessRole,
    );
    if (dto.salary !== undefined) {
      this.policy.assertCanReadPayroll(actor);
    }
    if (dto.rate !== undefined) {
      this.policy.assertCanManagePayrollHistory(actor);
    }
    const firstName = requiredTrim(
      dto.firstName,
      "Имя преподавателя обязательно.",
    );
    const lastName = trimOptional(dto.lastName);
    const phone = trimOptional(dto.phone);
    const status = trimOptional(dto.status) ?? "active";
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
    const disciplineIds = dto.disciplineIds ?? [];
    const fullName = [firstName, lastName].filter(Boolean).join(" ");
    for (const branchId of dto.branchIds) {
      await assertSettingsBranchScope(this.database, actor, branchId);
    }
    const credentials = await this.accounts.prepareCreate(
      dto.email,
      dto.password,
    );

    try {
      const result = await this.database.query<TeacherRow>(
        `
          with valid_branches as (
            select id, name
            from app.branches
            where id = any($8::uuid[])
              and lifecycle_state = 'active' and deleted_at is null
          ),
          valid_disciplines as (
            select distinct d.id, d.name
            from app.disciplines d
            where d.id = any($9::uuid[])
              and d.lifecycle_state = 'active'
              and d.is_active and d.deleted_at is null
          ),
          reference_guard as (
            select string_agg(name, ', ' order by name) as specialization,
              (select count(*) from valid_branches) = cardinality($8::uuid[])
                and (select count(*) from valid_disciplines) = cardinality($9::uuid[])
                as references_valid
            from valid_disciplines
          ),
          inserted_user as (
            insert into app.users (
              email, password_hash, managed_password_ciphertext,
              full_name, phone, role,
              email_verified_at, profile_completed, is_app_account,
              email_changed_at, password_changed_at
            )
            select coalesce(
                $3,
                'teacher-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid'
              ),
              $7, $17, $4, $5, $16::app.user_role,
              case when $15::boolean then now() else null end,
              true, $15::boolean,
              case when $15::boolean then now() else null end,
              case when $15::boolean then now() else null end
            from reference_guard
            where reference_guard.references_valid
            returning id, email, role, is_app_account, password_hash,
              password_changed_at, email_changed_at
          ),
          inserted_profile as (
            insert into app.profiles (user_id, first_name, last_name, phone)
            select id, $1, $2, $5
            from inserted_user
            returning id, user_id, first_name, last_name, phone
          ),
          inserted_teacher as (
            insert into app.teachers (
              profile_id, status, specialization, custom_data, salary
            )
            select inserted_profile.id, $6, reference_guard.specialization,
              $11::jsonb, $12::numeric
            from inserted_profile cross join reference_guard
            returning *
          ),
          inserted_branches as (
            insert into app.teacher_branches (teacher_id, branch_id)
            select inserted_teacher.id, valid_branches.id
            from inserted_teacher cross join valid_branches
            returning branch_id
          ),
          inserted_disciplines as (
            insert into app.teacher_disciplines (teacher_id, discipline_id)
            select inserted_teacher.id, valid_disciplines.id
            from inserted_teacher cross join valid_disciplines
            returning discipline_id
          ),
          inserted_rate as (
            insert into app.teacher_rates (
              teacher_id, rate, effective_from, created_by, created_at
            )
            select inserted_teacher.id, $13::numeric,
              coalesce($14::date, current_date), $10, clock_timestamp()
            from inserted_teacher
            where $13::numeric is not null
            returning id, rate, effective_from, created_at
          ),
          inserted_link as (
            insert into app.user_crm_links (
              user_id, entity_type, entity_id, matched_phone, link_source,
              confirmed_at, created_by
            )
            select inserted_user.id, 'teacher'::app.crm_entity_type,
              inserted_teacher.id, $5,
              case when $15::boolean then 'manual_email' else 'manual_phone' end,
              now(), $10
            from inserted_user cross join inserted_teacher
            returning id
          )
          select t.id, t.status, t.specialization, t.custom_data, t.salary,
            t.profile_id,
            p.user_id as profile_user_id, p.first_name, p.last_name, u.email,
            p.phone, u.role::text as app_role, u.is_app_account,
            u.password_hash is not null as password_configured,
            u.password_changed_at, u.email_changed_at,
            t.lifecycle_state, t.version, t.offboarded_at, t.offboard_reason,
            (select rate from inserted_rate
              where effective_from <= current_date
              order by effective_from desc, created_at desc, id desc limit 1
            ) as current_rate,
            (select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name)
              order by b.name) from valid_branches b) as assigned_branches,
            (select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name)
              order by d.name) from valid_disciplines d) as disciplines
          from inserted_teacher t
          join inserted_profile p on p.id = t.profile_id
          join inserted_user u on u.id = p.user_id
          join inserted_branches branch_guard on true
          join inserted_link link_guard on true
          group by t.id, t.status, t.specialization, t.custom_data, t.salary,
            t.profile_id, t.lifecycle_state, t.version, t.offboarded_at,
            t.offboard_reason,
            p.user_id, p.first_name, p.last_name, u.email, p.phone,
            u.role, u.is_app_account, u.password_hash,
            u.password_changed_at, u.email_changed_at
          limit 1
        `,
        [
          firstName,
          lastName,
          credentials.email,
          fullName,
          phone,
          status,
          credentials.passwordHash,
          dto.branchIds,
          disciplineIds,
          actor.userId,
          JSON.stringify(customDataPatch),
          dto.salary ?? null,
          dto.rate ?? null,
          dto.rateEffectiveFrom ?? null,
          credentials.isAppAccount,
          accessRole,
          credentials.passwordCiphertext,
        ],
      );
      const teacher = result.rows[0];
      if (!teacher) {
        throw new BadRequestException(
          "Выберите действующие филиалы и корректные справочные дисциплины.",
        );
      }
      await this.audit.record({
        actor,
        action: "crm.teacher_created",
        entityType: "teacher",
        entityId: teacher.id,
        metadata: {
          accessRole,
          rateConfigured: dto.rate !== undefined,
          salaryConfigured: dto.salary !== undefined,
        },
      });
      return this.toTeacherDto(teacher, actor);
    } catch (error) {
      rethrowCreatePersonError(error);
    }
  }

  async provisionAccess(
    actor: ActorContext,
    teacherId: string,
    dto: ProvisionPersonAccessDto,
  ) {
    await this.accounts.manageAccess(actor, "teacher", teacherId, dto);
    return this.getTeacher(actor, teacherId);
  }

  readAccess(actor: ActorContext, teacherId: string) {
    return this.accounts.readAccess(actor, "teacher", teacherId);
  }

  async updateTeacher(
    actor: ActorContext,
    teacherId: string,
    dto: UpdateTeacherDto,
    metadata: VersionedMutationMetadata = {
      idempotencyKey: "",
      requestId: "",
    },
  ) {
    this.policy.assertCanWriteCrm(actor);
    if (
      dto.status !== undefined &&
      ["inactive", "archived"].includes(dto.status.trim().toLowerCase())
    ) {
      throw new BadRequestException(
        "Отключение преподавателя выполняется через сценарий offboarding.",
      );
    }
    if (dto.salary !== undefined) {
      this.policy.assertCanReadPayroll(actor);
    }
    if (dto.rate !== undefined) {
      this.policy.assertCanManagePayrollHistory(actor);
    }
    if (dto.branchIds || dto.disciplineIds) {
      this.policy.assertCanManageSystemSettings(actor);
    }
    if (dto.branchIds) {
      for (const branchId of dto.branchIds) {
        await assertSettingsBranchScope(this.database, actor, branchId);
      }
    }
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
    const applyUpdate = async (execute: TeacherUpdateExecutor) => {
      const result = await execute(
        `
        with target as (
          select t.id, t.profile_id, p.user_id, u.email
          from app.teachers t
          left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
          left join app.users u on u.id = p.user_id and u.deleted_at is null
          where t.id = $1 and t.deleted_at is null
            and t.lifecycle_state = 'active'
            and ($5::text is null or lower(u.email) = lower($5))
          limit 1
        ),
        selected_branch_ids as (
          select unnest($10::uuid[]) as id where $10::uuid[] is not null
          union all
          select tb.branch_id from app.teacher_branches tb
          join target on true where $10::uuid[] is null and tb.teacher_id = target.id
            and tb.active_from <= current_date
            and (tb.active_until is null or tb.active_until >= current_date)
        ),
        selected_discipline_ids as (
          select unnest($9::uuid[]) as id where $9::uuid[] is not null
          union all
          select td.discipline_id from app.teacher_disciplines td
          join target on true where $9::uuid[] is null and td.teacher_id = target.id
        ),
        valid_branches as (
          select distinct b.id, b.name
          from selected_branch_ids selected
          join app.branches b on b.id = selected.id
            and b.lifecycle_state = 'active' and b.deleted_at is null
        ),
        valid_disciplines as (
          select distinct d.id, d.name
          from selected_discipline_ids selected
          join app.disciplines d
            on d.id = selected.id
            and (
              (d.lifecycle_state = 'active' and d.is_active and d.deleted_at is null)
              or exists (
                select 1
                from app.teacher_disciplines existing
                join target on target.id = existing.teacher_id
                where existing.discipline_id = d.id
              )
            )
        ),
        reference_guard as (
          select string_agg(name, ', ' order by name) as specialization,
            (select count(*) from valid_branches) =
                (select count(*) from selected_branch_ids)
              and (select count(*) from valid_disciplines) =
                (select count(*) from selected_discipline_ids)
              and exists (select 1 from valid_branches)
              as references_valid
          from valid_disciplines
        ),
        updated_profile as (
          update app.profiles p
          set first_name = coalesce($2, p.first_name),
            last_name = coalesce($3, p.last_name),
            phone = coalesce($4, p.phone),
            updated_at = now()
          from target cross join reference_guard
          where p.id = target.profile_id
            and reference_guard.references_valid
          returning p.id, p.user_id, p.first_name, p.last_name, p.phone
        ),
        updated_teacher as (
          update app.teachers t
          set status = coalesce($6, t.status),
            specialization = reference_guard.specialization,
            custom_data = coalesce(t.custom_data, '{}'::jsonb) || $7::jsonb,
            salary = coalesce($8::numeric, t.salary),
            updated_at = now()
          from target cross join reference_guard
          where t.id = target.id and reference_guard.references_valid
          returning t.*
        ),
        removed_disciplines as (
          delete from app.teacher_disciplines td
          using updated_teacher
          where $9::uuid[] is not null and td.teacher_id = updated_teacher.id
            and not (td.discipline_id = any($9::uuid[]))
          returning td.discipline_id
        ),
        inserted_disciplines as (
          insert into app.teacher_disciplines (teacher_id, discipline_id)
          select updated_teacher.id, valid_disciplines.id
          from updated_teacher cross join valid_disciplines
          where $9::uuid[] is not null
            and not exists (
              select 1 from app.teacher_disciplines existing
              where existing.teacher_id = updated_teacher.id
                and existing.discipline_id = valid_disciplines.id
            )
          on conflict do nothing
          returning discipline_id
        ),
        removed_branches as (
          delete from app.teacher_branches tb
          using updated_teacher
          where $10::uuid[] is not null and tb.teacher_id = updated_teacher.id
            and not (tb.branch_id = any($10::uuid[]))
          returning tb.branch_id
        ),
        inserted_branches as (
          insert into app.teacher_branches (teacher_id, branch_id)
          select updated_teacher.id, valid_branches.id
          from updated_teacher cross join valid_branches
          where $10::uuid[] is not null
          on conflict (teacher_id, branch_id) do update
          set active_from = current_date,
            active_until = null,
            version = app.teacher_branches.version + 1,
            updated_at = now()
          returning branch_id
        ),
        inserted_rate as (
          insert into app.teacher_rates (
            teacher_id, rate, effective_from, created_by, created_at
          )
          select updated_teacher.id, $11::numeric,
            coalesce($12::date, current_date), $13, clock_timestamp()
          from updated_teacher
          where $11::numeric is not null
          returning id, rate, effective_from, created_at
        )
        select ut.id, ut.status, ut.specialization, ut.custom_data, ut.salary,
          ut.profile_id,
          coalesce(updated_profile_dependency.user_id, p.user_id) as profile_user_id,
          u.role::text as app_role, u.is_app_account,
          u.password_hash is not null as password_configured,
          u.password_changed_at, u.email_changed_at,
          ut.lifecycle_state, ut.version, ut.offboarded_at,
          ut.offboard_reason,
          coalesce(updated_profile_dependency.first_name, p.first_name) as first_name,
          coalesce(updated_profile_dependency.last_name, p.last_name) as last_name,
          u.email, coalesce(updated_profile_dependency.phone, p.phone) as phone,
          (select candidate.rate
            from (
              select inserted.id, inserted.rate, inserted.effective_from,
                inserted.created_at
              from inserted_rate inserted
              union all
              select existing.id, existing.rate, existing.effective_from,
                existing.created_at
              from app.teacher_rates existing
              where existing.teacher_id = ut.id
                and existing.deleted_at is null
            ) candidate
            where candidate.effective_from <= current_date
            order by candidate.effective_from desc, candidate.created_at desc,
              candidate.id desc
            limit 1
          ) as current_rate,
          (select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name)
            order by b.name) from valid_branches b) as assigned_branches,
          (select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name)
            order by d.name) from valid_disciplines d) as disciplines
        from updated_teacher ut
        left join updated_profile updated_profile_dependency on true
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
          JSON.stringify(customDataPatch),
          dto.salary ?? null,
          dto.disciplineIds ?? null,
          dto.branchIds ?? null,
          dto.rate ?? null,
          dto.rateEffectiveFrom ?? null,
          actor.userId,
        ],
      );
      const teacher = result.rows[0];
      if (!teacher) {
        throw new BadRequestException(
          "Преподаватель не найден, email изменён вне управления доступом или справочные значения недоступны.",
        );
      }
      return teacher;
    };
    const payrollChanged = dto.salary !== undefined || dto.rate !== undefined;
    if (payrollChanged) {
      const reasonText = dto.payrollReasonText?.trim() ?? "";
      if (dto.payrollExpectedVersion === undefined) {
        throw new BadRequestException(
          "Обновите карточку и повторите: версия расчётов преподавателя не указана.",
        );
      }
      if (!reasonText) {
        throw new BadRequestException(
          "Укажите причину изменения ставки или оклада.",
        );
      }
      assertVersionedMutationMetadata(metadata);
      let updatedTeacher: TeacherRow | undefined;
      const mutation = await this.integrity.executeVersionedMutation({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        operation: "crm.teacher.update-with-payroll",
        idempotencyKey: metadata.idempotencyKey,
        payload: { teacherId, ...dto, payrollReasonText: reasonText },
        aggregateType: "teacher:payroll",
        aggregateId: teacherId,
        expectedVersion: dto.payrollExpectedVersion,
        requestId: metadata.requestId,
        authorization: {
          actor,
          capabilityKey: "commerce.teacher_payroll.write",
        },
        audit: {
          action: "crm.teacher_updated",
          entityType: "teacher",
          entityId: teacherId,
          reason: "TEACHER_PAYROLL_PROFILE_CHANGE",
          reasonText,
          metadata: {
            rateChanged: dto.rate !== undefined,
            rateEffectiveFrom: dto.rateEffectiveFrom ?? null,
            salaryChanged: dto.salary !== undefined,
          },
        },
        outbox: {
          type: "crm.teacher_payroll.changed",
          payload: { action: "profile_payroll_updated", entityId: teacherId },
        },
        mutate: async (client) => {
          updatedTeacher = await applyUpdate((query, params) =>
            client.query<TeacherRow>(query, params),
          );
          return { teacherId: updatedTeacher.id };
        },
      });
      if (updatedTeacher) {
        return {
          ...this.toTeacherDto(updatedTeacher, actor),
          payrollVersion: mutation.version,
        };
      }
      const replayedTeacher = await this.getTeacher(actor, teacherId);
      return { ...replayedTeacher, payrollVersion: mutation.version };
    }

    const teacher = await applyUpdate((query, params) =>
      this.database.query<TeacherRow>(query, params),
    );
    await this.audit.record({
      actor,
      action: "crm.teacher_updated",
      entityType: "teacher",
      entityId: teacher.id,
      metadata: {
        rateChanged: false,
        rateEffectiveFrom: null,
        salaryChanged: false,
      },
    });
    return this.toTeacherDto(teacher, actor);
  }
}
