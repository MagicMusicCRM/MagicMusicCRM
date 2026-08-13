import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { PasswordService } from "../auth/password.service";
import {
  ActorContext,
  ROLE_LEVEL,
  UserRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { ProvisionPersonAccessDto } from "./dto/provision-person-access.dto";
import { rethrowCreatePersonError } from "./crm-util";

export type PersonAccountType = "teacher" | "staff";

export interface PreparedPersonCredentials {
  email: string | null;
  passwordHash: string | null;
  isAppAccount: boolean;
}

interface PersonAccountTarget {
  entity_id: string;
  profile_id: string | null;
  user_id: string | null;
  current_email: string | null;
  current_password_hash: string | null;
  current_role: string | null;
  is_app_account: boolean;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  account_role: string;
  lifecycle_state: string;
}

interface ManagedAccountResult {
  userId: string;
  email: string;
  role: UserRole;
  isAppAccount: true;
  passwordConfigured: boolean;
  passwordChangedAt: Date | string | null;
  emailChangedAt: Date | string | null;
}

const APP_ROLES = new Set<UserRole>([
  "client",
  "teacher",
  "admin",
  "manager",
  "director",
  "system_admin",
]);

const PERSON_INITIAL_ROLES: Record<PersonAccountType, ReadonlySet<UserRole>> = {
  teacher: new Set<UserRole>(["teacher", "admin", "manager", "director"]),
  staff: new Set<UserRole>(["admin", "manager", "director"]),
};

/**
 * One identity boundary for Teacher/Staff cards. CRM creation may prepare a
 * technical identity without login; later activation and director-managed
 * email/password changes upgrade that same user/profile/link atomically.
 */
@Injectable()
export class PersonAccountService {
  constructor(
    private readonly database: DatabaseService,
    private readonly passwords: PasswordService,
    private readonly audit: AuditService,
  ) {}

  async prepareCreate(
    emailInput?: string,
    password?: string,
  ): Promise<PreparedPersonCredentials> {
    const email = emailInput?.trim().toLowerCase() || null;
    const hasEmail = email !== null;
    const hasPassword = Boolean(password);
    if (hasEmail !== hasPassword) {
      throw new BadRequestException(
        "Для доступа укажите одновременно email и пароль либо оставьте оба поля пустыми.",
      );
    }
    return {
      email,
      passwordHash: password ? await this.passwords.hash(password) : null,
      isAppAccount: hasEmail,
    };
  }

  resolveInitialRole(
    actor: ActorContext,
    personType: PersonAccountType,
    requestedRole?: string,
  ): UserRole {
    const role = (requestedRole ??
      (personType === "teacher" ? "teacher" : "admin")) as UserRole;
    if (!APP_ROLES.has(role) || !PERSON_INITIAL_ROLES[personType].has(role)) {
      throw new BadRequestException(
        "Для карточки выбрана недопустимая роль доступа.",
      );
    }
    if (
      actor.role !== "system_admin" &&
      ROLE_LEVEL[role] >= ROLE_LEVEL[actor.role]
    ) {
      throw new ForbiddenException(
        "Можно назначить только роль ниже собственной.",
      );
    }
    return role;
  }

  async manageAccess(
    actor: ActorContext,
    personType: PersonAccountType,
    entityId: string,
    dto: ProvisionPersonAccessDto,
  ): Promise<ManagedAccountResult> {
    this.assertCanManage(actor);
    if ("role" in dto) {
      throw new ForbiddenException(
        "Роль меняется только в разделе «Настройки → Доступы».",
      );
    }
    const requestedEmail = dto.email?.trim().toLowerCase() || null;
    const requestedPassword = dto.password || null;
    if (!requestedEmail && !requestedPassword) {
      throw new BadRequestException("Укажите новый email и/или пароль.");
    }
    const passwordHash = requestedPassword
      ? await this.passwords.hash(requestedPassword)
      : null;

    try {
      const result = await this.database.transaction(async (client) => {
        const target = await this.lockTarget(client, personType, entityId);
        if (target.lifecycle_state !== "active") {
          throw new BadRequestException(
            "Сначала восстановите карточку сотрудника из архива.",
          );
        }
        const role = target.account_role as UserRole;
        if (!APP_ROLES.has(role) || role === "client") {
          throw new BadRequestException(
            "Для карточки не определена допустимая роль доступа.",
          );
        }
        if (target.user_id === actor.userId) {
          throw new ForbiddenException(
            "Собственные данные для входа меняются в настройках профиля.",
          );
        }
        if (
          actor.role !== "system_admin" &&
          ROLE_LEVEL[role] >= ROLE_LEVEL[actor.role]
        ) {
          throw new ForbiddenException(
            "Директор может управлять доступом только более низкой роли.",
          );
        }
        const activation = !target.is_app_account;
        if (activation && (!requestedEmail || !requestedPassword)) {
          throw new BadRequestException(
            "Для первого доступа одновременно укажите email и пароль.",
          );
        }

        const userId = await this.ensureIdentity(client, {
          personType,
          entityId,
          target,
          role,
          email: requestedEmail ?? target.current_email,
          passwordHash: passwordHash ?? target.current_password_hash,
          emailChanged: requestedEmail !== null,
          passwordChanged: passwordHash !== null,
          actorUserId: actor.userId,
        });
        const account = await client.query<{
          id: string;
          email: string;
          role: UserRole;
          password_configured: boolean;
          password_changed_at: Date | string | null;
          email_changed_at: Date | string | null;
        }>(
          `select id, email, role,
             password_hash is not null as password_configured,
             password_changed_at, email_changed_at
           from app.users
           where id = $1 and deleted_at is null`,
          [userId],
        );
        const row = account.rows[0];
        if (!row) throw new NotFoundException("Учётная запись не найдена.");
        return {
          userId: row.id,
          email: row.email,
          role: row.role,
          isAppAccount: true as const,
          passwordConfigured: row.password_configured,
          passwordChangedAt: row.password_changed_at,
          emailChangedAt: row.email_changed_at,
        };
      });

      await this.audit.record({
        actor,
        action: `crm.${personType}_access_managed`,
        entityType: personType,
        entityId,
        metadata: {
          emailChanged: requestedEmail !== null,
          passwordChanged: requestedPassword !== null,
        },
      });
      return result;
    } catch (error) {
      rethrowCreatePersonError(error);
    }
  }

  private async lockTarget(
    client: PoolClient,
    personType: PersonAccountType,
    entityId: string,
  ): Promise<PersonAccountTarget> {
    const result =
      personType === "teacher"
        ? await client.query<PersonAccountTarget>(
            `select t.id as entity_id, t.profile_id, p.user_id,
               u.email as current_email, u.password_hash as current_password_hash,
               u.role::text as current_role,
               coalesce(u.is_app_account, false) as is_app_account,
               coalesce(p.first_name, t.custom_data->>'firstName') as first_name,
               coalesce(p.last_name, t.custom_data->>'lastName') as last_name,
               p.phone, coalesce(u.role::text, 'teacher') as account_role,
               coalesce(t.lifecycle_state, 'active') as lifecycle_state
             from app.teachers t
             left join app.profiles p
               on p.id = t.profile_id and p.deleted_at is null
             left join app.users u
               on u.id = p.user_id and u.deleted_at is null
             where t.id = $1 and t.deleted_at is null
             for update of t`,
            [entityId],
          )
        : await client.query<PersonAccountTarget>(
            `select sm.id as entity_id, sm.profile_id, p.user_id,
               u.email as current_email, u.password_hash as current_password_hash,
               u.role::text as current_role,
               coalesce(u.is_app_account, false) as is_app_account,
               p.first_name, p.last_name, p.phone,
               coalesce(u.role::text, sm.role) as account_role,
               coalesce(sm.lifecycle_state, 'active') as lifecycle_state
             from app.staff_members sm
             left join app.profiles p
               on p.id = sm.profile_id and p.deleted_at is null
             left join app.users u
               on u.id = p.user_id and u.deleted_at is null
             where sm.id = $1 and sm.deleted_at is null
             for update of sm`,
            [entityId],
          );
    const target = result.rows[0];
    if (!target) {
      throw new NotFoundException(
        personType === "teacher"
          ? "Преподаватель не найден."
          : "Сотрудник не найден.",
      );
    }
    return target;
  }

  private async ensureIdentity(
    client: PoolClient,
    input: {
      personType: PersonAccountType;
      entityId: string;
      target: PersonAccountTarget;
      role: UserRole;
      email: string | null;
      passwordHash: string | null;
      emailChanged: boolean;
      passwordChanged: boolean;
      actorUserId: string;
    },
  ): Promise<string> {
    if (!input.email || !input.passwordHash) {
      throw new BadRequestException(
        "Для активного доступа необходимы email и пароль.",
      );
    }

    let userId = input.target.user_id;
    let profileId = input.target.profile_id;
    if (userId) {
      const updated = await client.query<{ id: string }>(
        `update app.users
         set email = $2,
             password_hash = $3,
             is_app_account = true,
             email_verified_at = case when $4 then now()
               else coalesce(email_verified_at, now()) end,
             email_changed_at = case when $4 then now() else email_changed_at end,
             password_changed_at = case when $5 then now() else password_changed_at end,
             profile_completed = true,
             updated_at = now()
         where id = $1 and deleted_at is null
         returning id`,
        [
          userId,
          input.email,
          input.passwordHash,
          input.emailChanged,
          input.passwordChanged,
        ],
      );
      if (!updated.rows[0])
        throw new NotFoundException("Учётная запись не найдена.");
    } else {
      const inserted = await client.query<{ id: string }>(
        `insert into app.users (
           email, password_hash, full_name, phone, role, email_verified_at,
           profile_completed, is_app_account, email_changed_at,
           password_changed_at
         ) values (
           $1, $2,
           nullif(btrim(concat_ws(' ', $3::text, $4::text)), ''), $5::text,
           $6::app.user_role, now(), true, true,
           case when $7 then now() else null end,
           case when $8 then now() else null end
         ) returning id`,
        [
          input.email,
          input.passwordHash,
          input.target.first_name,
          input.target.last_name,
          input.target.phone,
          input.role,
          input.emailChanged,
          input.passwordChanged,
        ],
      );
      userId = inserted.rows[0]!.id;
    }

    if (!profileId) {
      const inserted = await client.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name, phone)
         values ($1, $2, $3, $4)
         returning id`,
        [
          userId,
          input.target.first_name,
          input.target.last_name,
          input.target.phone,
        ],
      );
      profileId = inserted.rows[0]!.id;
      const table =
        input.personType === "teacher" ? "teachers" : "staff_members";
      await client.query(
        `update app.${table} set profile_id = $2, updated_at = now() where id = $1`,
        [input.entityId, profileId],
      );
    }

    const conflictingLink = await client.query<{ user_id: string }>(
      `select user_id
       from app.user_crm_links
       where entity_type = $1::app.crm_entity_type
         and entity_id = $2 and deleted_at is null
         and user_id <> $3
       limit 1`,
      [input.personType, input.entityId, userId],
    );
    if (conflictingLink.rows[0]) {
      throw new BadRequestException(
        "Карточка уже связана с другой учётной записью.",
      );
    }
    await client.query(
      `insert into app.user_crm_links (
         user_id, entity_type, entity_id, matched_phone, link_source,
         confirmed_at, created_by
       ) values ($1, $2::app.crm_entity_type, $3, $4, 'manual_email', now(), $5)
       on conflict (user_id, entity_type, entity_id) where deleted_at is null
       do update set matched_phone = excluded.matched_phone,
         confirmed_at = excluded.confirmed_at`,
      [
        userId,
        input.personType,
        input.entityId,
        input.target.phone,
        input.actorUserId,
      ],
    );

    await client.query(
      `update app.refresh_sessions
       set revoked_at = coalesce(revoked_at, now())
       where user_id = $1 and revoked_at is null`,
      [userId],
    );
    return userId;
  }

  private assertCanManage(actor: ActorContext): void {
    if (actor.role === "director" || actor.role === "system_admin") return;
    throw new ForbiddenException(
      "Данные для входа доступны только директору в настройках системы.",
    );
  }
}
