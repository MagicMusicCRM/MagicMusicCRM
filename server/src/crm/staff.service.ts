import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  ROLE_LEVEL,
  UserRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CreateStaffDto } from "./dto/create-staff.dto";
import { StaffListQuery } from "./dto/staff-list.query";
import { UpdateStaffDto } from "./dto/update-staff.dto";
import { ProvisionPersonAccessDto } from "./dto/provision-person-access.dto";
import { CrmPolicy } from "./crm.policy";
import {
  ACTIVE_RESPONSIBLE_STAFF_STATUSES,
  RESPONSIBLE_AUTH_ROLES,
} from "./responsible-eligibility";
import {
  rethrowCreatePersonError,
  requiredTrim,
  sanitizeJsonObject,
  trimOptional,
} from "./crm-util";
import { presentableEmail } from "./crm-mappers";
import { assertSettingsBranchScope } from "./settings-branch-scope";
import { PersonAccountService } from "./person-account.service";

interface StaffRow {
  id: string;
  role: string;
  position: string | null;
  status: string;
  custom_data: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  app_role: string | null;
  is_app_account: boolean | null;
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
  branches: Array<{ id: string; name: string }> | null;
  created_at: Date | string;
}

const USER_ROLES = new Set<UserRole>([
  "client",
  "teacher",
  "admin",
  "manager",
  "director",
  "system_admin",
]);

function isUserRole(value: string): value is UserRole {
  return USER_ROLES.has(value as UserRole);
}

const STAFF_EDITOR_ROLES = new Set<UserRole>([
  "admin",
  "manager",
  "director",
  "system_admin",
]);

function canEditStaffTarget(
  actorRole: UserRole,
  targetRole: UserRole,
): boolean {
  if (actorRole === "system_admin") return true;
  return (
    STAFF_EDITOR_ROLES.has(actorRole) &&
    ROLE_LEVEL[targetRole] < ROLE_LEVEL[actorRole]
  );
}

/**
 * Staff domain, extracted from CrmService (SRP): staff-member listing (with
 * branch/role/app-account/birthday filters), creation (user+profile+staff in one
 * transaction, role-hierarchy gated), and update. Touches `app.staff_members` /
 * `app.profiles` / `app.users` / `app.staff_branch_assignments` and the shared
 * database/audit/policy collaborators. No internal callers.
 */
@Injectable()
export class StaffService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly accounts: PersonAccountService,
  ) {}

  private toStaffDto(row: StaffRow) {
    return {
      id: row.id,
      role: row.role,
      position: row.position,
      status: row.status,
      customData: row.custom_data ?? {},
      profileId: row.profile_id,
      profileUserId: row.profile_user_id,
      appRole: row.app_role,
      isAppAccount: row.is_app_account ?? false,
      passwordConfigured: row.password_configured ?? false,
      passwordChangedAt: row.password_changed_at ?? null,
      emailChangedAt: row.email_changed_at ?? null,
      lifecycleState: row.lifecycle_state ?? "active",
      version: Number(row.version ?? 1),
      offboardedAt: row.offboarded_at ?? null,
      offboardReason: row.offboard_reason ?? null,
      firstName: row.first_name,
      lastName: row.last_name,
      email: presentableEmail(row.email),
      phone: row.phone,
      branches: row.branches ?? [],
      createdAt: row.created_at,
    };
  }

  async listStaff(
    actor: ActorContext,
    query: StaffListQuery,
    staffId: string | null = null,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<StaffRow>(
      `
        select sm.id, sm.role, sm.position, sm.status, sm.custom_data,
          sm.profile_id, p.user_id as profile_user_id, u.role as app_role,
          u.is_app_account, u.password_hash is not null as password_configured,
          u.password_changed_at, u.email_changed_at,
          sm.lifecycle_state, sm.version, sm.offboarded_at, sm.offboard_reason,
          p.first_name, p.last_name, u.email, p.phone,
          coalesce(
            jsonb_agg(
              distinct jsonb_build_object('id', b.id, 'name', b.name)
            ) filter (where b.id is not null),
            '[]'::jsonb
          ) as branches,
          sm.created_at
        from app.staff_members sm
        left join app.profiles p on p.id = sm.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.staff_branch_assignments sba
          on sba.staff_member_id = sm.id and sba.deleted_at is null
        left join app.branches b on b.id = sba.branch_id and b.deleted_at is null
        where sm.deleted_at is null
          and ($1::uuid is null or exists (
            select 1
            from app.staff_branch_assignments branch_filter
            where branch_filter.staff_member_id = sm.id
              and branch_filter.branch_id = $1
              and branch_filter.deleted_at is null
          ))
          and (
            $2::text is null
            or lower(
              coalesce(p.first_name, '') || ' ' ||
              coalesce(p.last_name, '') || ' ' ||
              coalesce(u.email, '') || ' ' ||
              coalesce(p.phone, '') || ' ' ||
              coalesce(sm.role, '') || ' ' ||
              coalesce(sm.position, '')
            ) like lower('%' || $2 || '%')
          )
          and ($3::text is null or sm.role = $3)
          and ($4::text is null or sm.status = $4)
          and ($5::text is null or u.role::text = $5)
          and (
            $9::text = 'system_admin'
            or u.role is null
            or u.role <> 'system_admin'::app.user_role
          )
          and (
            $6::text is null
            or ($6 = 'app' and coalesce(u.is_app_account, false) = true)
            or ($6 = 'technical' and coalesce(u.is_app_account, false) = false)
            or ($6 = 'linked' and exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'staff'
                and link.entity_id = sm.id
                and link.deleted_at is null
            ))
            or ($6 = 'unlinked' and not exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'staff'
                and link.entity_id = sm.id
                and link.deleted_at is null
            ))
          )
          and (
            $7::int is null
            or (
              case
                when p.dob is not null then extract(month from p.dob)::int
                when coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
                  then extract(month from coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date')::date)::int
                when coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date') ~ '^[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}$'
                  then extract(month from to_date(coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date'), 'DD.MM.YYYY'))::int
                else null
              end
            ) = $7
          )
          and ($10::uuid is null or sm.id = $10)
        group by sm.id, p.id, u.id
        order by sm.created_at desc, sm.id desc
        limit $8
      `,
      [
        query.branchId ?? null,
        q || null,
        query.role ?? null,
        query.status ?? null,
        query.appRole ?? null,
        query.authorization ?? null,
        query.birthdayMonth ?? null,
        limit,
        actor.role,
        staffId,
      ],
    );

    return { items: result.rows.map((row) => this.toStaffDto(row)) };
  }

  async getStaff(actor: ActorContext, staffId: string) {
    const result = await this.listStaff(actor, { limit: 1 }, staffId);
    const staff = result.items[0];
    if (!staff) throw new NotFoundException("Сотрудник не найден.");
    return staff;
  }

  async createStaff(actor: ActorContext, dto: CreateStaffDto) {
    const role = this.accounts.resolveInitialRole(
      actor,
      "staff",
      dto.accessRole,
    );
    const firstName = requiredTrim(
      dto.firstName,
      "Имя сотрудника обязательно.",
    );
    const lastName = requiredTrim(
      dto.lastName,
      "Фамилия сотрудника обязательна.",
    );
    const phone = trimOptional(dto.phone);
    const fullName = [firstName, lastName].join(" ");
    for (const branchId of dto.branchIds) {
      await assertSettingsBranchScope(this.database, actor, branchId);
    }
    const credentials = await this.accounts.prepareCreate(
      dto.email,
      dto.password,
    );

    try {
      const result = await this.database.query<StaffRow>(
        `
          with valid_branches as (
            select id, name
            from app.branches
            where id = any($8::uuid[]) and deleted_at is null
          ),
          inserted_user as (
            insert into app.users (
              email, password_hash, full_name, phone, role,
              email_verified_at, profile_completed, is_app_account,
              email_changed_at, password_changed_at
            )
            select coalesce(
                $1,
                'staff-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid'
              ),
              $7, $2, $3, $4::app.user_role,
              case when $10::boolean then now() else null end,
              true, $10::boolean,
              case when $10::boolean then now() else null end,
              case when $10::boolean then now() else null end
            where (select count(*) from valid_branches) = cardinality($8::uuid[])
            returning id, email, role, is_app_account, password_hash,
              password_changed_at, email_changed_at
          ),
          inserted_profile as (
            insert into app.profiles (user_id, first_name, last_name, phone)
            select id, $5, $6, $3
            from inserted_user
            returning id, user_id, first_name, last_name, phone, avatar_file_id, email_otp_2fa_enabled, created_at, updated_at
          ),
          inserted_staff as (
            insert into app.staff_members (profile_id, role, position, status)
            select
              id,
              $4,
              case
                when $4 = 'system_admin' then 'Администратор системы'
                when $4 = 'admin' then 'Администратор'
                                when $4 = 'manager' then 'Управляющий'
                when $4 = 'director' then 'Директор'
                else 'Сотрудник'
              end,
              'working'
            from inserted_profile
            returning *
          ),
          inserted_assignments as (
            insert into app.staff_branch_assignments (staff_member_id, branch_id)
            select inserted_staff.id, valid_branches.id
            from inserted_staff cross join valid_branches
            returning branch_id
          ),
          inserted_link as (
            insert into app.user_crm_links (
              user_id, entity_type, entity_id, matched_phone, link_source,
              confirmed_at, created_by
            )
            select inserted_user.id, 'staff'::app.crm_entity_type,
              inserted_staff.id, $3,
              case when $10::boolean then 'manual_email' else 'manual_phone' end,
              now(), $9
            from inserted_user cross join inserted_staff
            returning id
          )
          select s.id, s.role, s.position, s.status,
            '{}'::jsonb as custom_data, s.profile_id,
            p.user_id as profile_user_id, u.role::text as app_role,
            u.is_app_account, u.password_hash is not null as password_configured,
            u.password_changed_at, u.email_changed_at,
            s.lifecycle_state, s.version, s.offboarded_at, s.offboard_reason,
            p.first_name, p.last_name, u.email, p.phone,
            coalesce(
              jsonb_agg(
                distinct jsonb_build_object('id', b.id, 'name', b.name)
              ) filter (where b.id is not null),
              '[]'::jsonb
            ) as branches,
            now() as created_at
          from inserted_staff s
          join inserted_profile p on p.id = s.profile_id
          join inserted_user u on u.id = p.user_id
          join inserted_link link_guard on true
          join inserted_assignments assignment_guard on true
          join valid_branches b on b.id = assignment_guard.branch_id
          group by s.id, s.role, s.position, s.status, s.profile_id,
            s.lifecycle_state, s.version, s.offboarded_at, s.offboard_reason,
            p.user_id, p.first_name, p.last_name, p.phone,
            u.role, u.is_app_account, u.email, u.password_hash,
            u.password_changed_at, u.email_changed_at
        `,
        [
          credentials.email,
          fullName,
          phone,
          role,
          firstName,
          lastName,
          credentials.passwordHash,
          dto.branchIds,
          actor.userId,
          credentials.isAppAccount,
        ],
      );
      const staff = result.rows[0];
      if (!staff) {
        throw new BadRequestException(
          "Один или несколько выбранных филиалов недоступны.",
        );
      }
      await this.audit.record({
        actor,
        action: "crm.staff_created",
        entityType: "staff",
        entityId: staff.id,
      });
      return this.toStaffDto(staff);
    } catch (error) {
      rethrowCreatePersonError(error);
    }
  }

  async provisionAccess(
    actor: ActorContext,
    staffId: string,
    dto: ProvisionPersonAccessDto,
  ) {
    await this.accounts.manageAccess(actor, "staff", staffId, dto);
    return this.getStaff(actor, staffId);
  }

  async updateStaff(actor: ActorContext, staffId: string, dto: UpdateStaffDto) {
    if (!STAFF_EDITOR_ROLES.has(actor.role)) {
      throw new ForbiddenException(
        "Недостаточно прав для редактирования сотрудников.",
      );
    }

    // Authorization is based on the linked app.users role (the actual auth
    // privilege), never merely on the free-form staff-card display role. This
    // prevents a branch admin from editing a manager/system administrator and
    // closes the old email -> password-reset account-takeover path.
    const current = await this.database.query<{
      role: string | null;
      app_role: string | null;
      profile_user_id: string | null;
      email: string | null;
      status: string;
    }>(
      `select sm.role, sm.status, u.role::text as app_role,
         p.user_id as profile_user_id, u.email
       from app.staff_members sm
       left join app.profiles p
         on p.id = sm.profile_id and p.deleted_at is null
       left join app.users u
         on u.id = p.user_id and u.deleted_at is null
       where sm.id = $1 and sm.deleted_at is null
       limit 1`,
      [staffId],
    );
    const target = current.rows[0];
    if (!target) {
      throw new NotFoundException("Сотрудник не найден.");
    }

    const authRole = target.app_role?.trim() ?? null;
    if (authRole !== null && !isUserRole(authRole)) {
      throw new ForbiddenException(
        "Недостаточно прав для редактирования этого сотрудника.",
      );
    }
    const displayRole = target.role?.trim() ?? null;
    const effectiveRole =
      authRole ??
      (displayRole !== null && isUserRole(displayRole) ? displayRole : null);
    if (
      effectiveRole !== null &&
      !canEditStaffTarget(actor.role, effectiveRole)
    ) {
      throw new ForbiddenException(
        "Недостаточно прав для редактирования этого сотрудника.",
      );
    }

    // The staff-card endpoint is not an identity-management endpoint. Keep an
    // unchanged email in legacy form submissions as a no-op, but never mutate
    // app.users.email here; email changes require a dedicated verified flow.
    if (dto.email !== undefined) {
      const requestedEmail = trimOptional(dto.email)?.toLowerCase() ?? null;
      const currentEmail = target.email?.trim().toLowerCase() ?? null;
      if (requestedEmail !== currentEmail) {
        throw new ForbiddenException(
          "Email для входа нельзя изменить через карточку сотрудника.",
        );
      }
    }

    // Cards cannot elevate or relabel access. The canonical access command also
    // synchronizes staff_members.role after a settings-only role change. Keep a
    // runtime guard as defense in depth for non-controller callers.
    if ("role" in dto) {
      const requestedRole = String(dto.role).trim();
      const currentRole = displayRole;
      const unchangedDisplayRole = requestedRole === currentRole;
      if (!unchangedDisplayRole) {
        throw new ForbiddenException(
          "Роль меняется только в разделе «Настройки → Доступы».",
        );
      }
    }
    if (
      dto.status !== undefined &&
      ["inactive", "archived"].includes(dto.status.trim().toLowerCase()) &&
      dto.status.trim().toLowerCase() !== target.status.trim().toLowerCase()
    ) {
      throw new ForbiddenException(
        "Отключение сотрудника выполняется через сценарий offboarding.",
      );
    }
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
    if (dto.branchIds) {
      for (const branchId of dto.branchIds) {
        await assertSettingsBranchScope(this.database, actor, branchId);
      }
    }

    try {
      const result = await this.database.query<StaffRow>(
        `
          with target as (
            select sm.id, sm.profile_id, p.user_id
            from app.staff_members sm
            left join app.profiles p on p.id = sm.profile_id and p.deleted_at is null
            where sm.id = $1 and sm.deleted_at is null
              and sm.lifecycle_state = 'active'
            limit 1
          ),
          valid_branches as (
            select id, name
            from app.branches
            where $8::uuid[] is not null
              and id = any($8::uuid[]) and deleted_at is null
          ),
          reference_guard as (
            select $8::uuid[] is null
              or (select count(*) from valid_branches) = cardinality($8::uuid[])
              as valid
          ),
          updated_profile as (
            update app.profiles p
            set first_name = coalesce($2, p.first_name),
              last_name = coalesce($3, p.last_name),
              phone = coalesce($4, p.phone),
              updated_at = now()
            from target
            cross join reference_guard
            where p.id = target.profile_id and reference_guard.valid
            returning p.id, p.user_id, p.first_name, p.last_name, p.phone
          ),
          updated_staff as (
            update app.staff_members sm
            set position = coalesce($5, sm.position),
              status = coalesce($6, sm.status),
              custom_data = coalesce(sm.custom_data, '{}'::jsonb) || $7::jsonb,
              updated_at = now()
            from target
            cross join reference_guard
            where sm.id = target.id
              and reference_guard.valid
            returning sm.*
          ),
          restored_assignments as (
            insert into app.staff_branch_assignments (staff_member_id, branch_id)
            select updated_staff.id, valid_branches.id
            from updated_staff cross join valid_branches
            on conflict (staff_member_id, branch_id)
            do update set deleted_at = null
            returning branch_id
          ),
          removed_assignments as (
            update app.staff_branch_assignments assignment
            set deleted_at = now()
            from updated_staff
            where $8::uuid[] is not null
              and assignment.staff_member_id = updated_staff.id
              and assignment.deleted_at is null
              and not (assignment.branch_id = any($8::uuid[]))
            returning assignment.branch_id
          )
          select us.id, us.role, us.position, us.status, us.custom_data,
            us.profile_id,
            coalesce(up.user_id, p.user_id) as profile_user_id,
            u.role as app_role,
            coalesce(u.is_app_account, false) as is_app_account,
            u.password_hash is not null as password_configured,
            u.password_changed_at, u.email_changed_at,
            us.lifecycle_state, us.version, us.offboarded_at,
            us.offboard_reason,
            coalesce(up.first_name, p.first_name) as first_name,
            coalesce(up.last_name, p.last_name) as last_name,
            u.email,
            coalesce(up.phone, p.phone) as phone,
            case when $8::uuid[] is not null then
              coalesce((select jsonb_agg(
                jsonb_build_object('id', vb.id, 'name', vb.name)
                order by vb.name) from valid_branches vb), '[]'::jsonb)
            else coalesce(
              jsonb_agg(distinct jsonb_build_object('id', b.id, 'name', b.name))
                filter (where b.id is not null), '[]'::jsonb
            ) end as branches,
            us.created_at
          from updated_staff us
          left join updated_profile up on true
          left join app.profiles p on p.id = us.profile_id and p.deleted_at is null
          left join app.users u on u.id = coalesce(up.user_id, p.user_id)
            and u.deleted_at is null
          left join app.staff_branch_assignments sba
            on sba.staff_member_id = us.id and sba.deleted_at is null
          left join app.branches b on b.id = sba.branch_id and b.deleted_at is null
          group by us.id, us.role, us.position, us.status, us.custom_data,
            us.profile_id, us.lifecycle_state, us.version, us.offboarded_at,
            us.offboard_reason, us.created_at, p.id, u.id,
            up.user_id, up.first_name, up.last_name, up.phone,
            u.email, u.role, u.is_app_account
          limit 1
        `,
        [
          staffId,
          trimOptional(dto.firstName),
          trimOptional(dto.lastName),
          trimOptional(dto.phone),
          trimOptional(dto.position),
          trimOptional(dto.status),
          JSON.stringify(customDataPatch),
          dto.branchIds ?? null,
        ],
      );
      const staff = result.rows[0];
      if (!staff) throw new NotFoundException("Сотрудник не найден.");
      await this.audit.record({
        actor,
        action: "crm.staff_updated",
        entityType: "staff",
        entityId: staff.id,
      });
      return this.toStaffDto(staff);
    } catch (error) {
      rethrowCreatePersonError(error);
    }
  }

  /**
   * Contract 4 (правки №2): slim picker for the «Ответственный» selector —
   * GET /api/admin/staff?search=&roles=admin,manager,director.
   *
   * Returns app.USERS ids, not staff_members ids: contract 5 stores
   * custom_data.responsibleUserId = users.id (the actor id), so the picker
   * must live in the same id space or the round-trip breaks.
   */
  async listStaffPicker(
    actor: ActorContext,
    query: { search?: string; roles?: string },
  ) {
    this.policy.assertManagerOnly(actor);
    const requested = (query.roles ?? "")
      .split(",")
      .map((role) => role.trim())
      .filter((role) =>
        (RESPONSIBLE_AUTH_ROLES as readonly string[]).includes(role),
      );
    const hasExplicitRoleFilter = Boolean(query.roles?.trim());
    const roles = hasExplicitRoleFilter
      ? requested
      : [...RESPONSIBLE_AUTH_ROLES];
    const search = query.search?.trim() || null;
    const result = await this.database.query<{
      id: string;
      display_name: string | null;
      role: string;
    }>(
      `
        select distinct u.id,
          coalesce(
            nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
            u.full_name,
            u.email
          ) as display_name,
          u.role::text as role
        from app.users u
        join app.profiles p on p.user_id = u.id and p.deleted_at is null
        join app.staff_members sm
          on sm.profile_id = p.id and sm.deleted_at is null
        where u.deleted_at is null
          and u.role::text = any($1::text[])
          and lower(btrim(sm.status)) = any($2::text[])
          and (
            $3::text is null
            or lower(
              coalesce(p.first_name, '') || ' ' ||
              coalesce(p.last_name, '') || ' ' ||
              coalesce(u.full_name, '') || ' ' ||
              coalesce(u.email, '')
            ) like lower('%' || $3 || '%')
          )
        order by display_name asc, u.id asc
        limit 100
      `,
      [roles, [...ACTIVE_RESPONSIBLE_STAFF_STATUSES], search],
    );
    // Contract pins a bare array, not {items}.
    return result.rows.map((row) => ({
      id: row.id,
      displayName: row.display_name ?? "",
      role: row.role,
    }));
  }
}
