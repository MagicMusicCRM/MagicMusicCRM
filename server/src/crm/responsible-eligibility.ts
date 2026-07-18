import { BadRequestException } from "@nestjs/common";
import { isUUID } from "class-validator";
import type { QueryResult, QueryResultRow } from "pg";

export const RESPONSIBLE_AUTH_ROLES = [
  "admin",
  "manager",
  "director",
] as const;

// Production contains both canonical and localized staff statuses. Keep this
// an allowlist: an unknown/dismissed value must never silently become eligible
// for ownership of client data.
export const ACTIVE_RESPONSIBLE_STAFF_STATUSES = [
  "working",
  "active",
  "работает",
  "активен",
] as const;

export interface ResponsibleEligibilityExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

export interface EligibleResponsible {
  userId: string;
  role: (typeof RESPONSIBLE_AUTH_ROLES)[number];
  staffMemberId: string;
  staffStatus: string;
  displayName: string;
}

export interface ResponsiblePickerQuery {
  search?: string;
  roles?: string;
}

/**
 * Resolve a responsible in the only supported identity space: app.users.id.
 * The user must have a live profile, a live staff_member, an operational auth
 * role, and a normalized active staff status. system_admin is intentionally
 * excluded consistently from both the picker and assignment endpoints.
 */
export async function assertEligibleResponsible(
  executor: ResponsibleEligibilityExecutor,
  userId: string,
  options: { lock?: boolean } = {},
): Promise<EligibleResponsible> {
  const result = await executor.query<{
    user_id: string;
    role: EligibleResponsible["role"];
    staff_member_id: string;
    staff_status: string;
    display_name: string;
  }>(
    `
      select u.id as user_id, u.role::text as role,
        sm.id as staff_member_id, sm.status as staff_status,
        coalesce(
          nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
          u.full_name,
          u.email
        ) as display_name
      from app.users u
      join app.profiles p
        on p.user_id = u.id
       and p.deleted_at is null
      join app.staff_members sm
        on sm.profile_id = p.id
       and sm.deleted_at is null
      where u.id = $1
        and u.deleted_at is null
        and u.role::text = any($2::text[])
        and lower(btrim(sm.status)) = any($3::text[])
      order by sm.created_at desc, sm.id asc
      limit 1
      ${options.lock ? "for share of u, p, sm" : ""}
    `,
    [
      userId,
      [...RESPONSIBLE_AUTH_ROLES],
      [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
    ],
  );
  const row = result.rows[0];
  if (!row) {
    throw new BadRequestException(
      "Ответственный должен быть активным сотрудником с ролью администратора, управляющего или директора.",
    );
  }
  return {
    userId: row.user_id,
    role: row.role,
    staffMemberId: row.staff_member_id,
    staffStatus: row.staff_status,
    displayName: row.display_name,
  };
}

/**
 * Extract the canonical app.users id from the legacy student custom_data
 * assignment surface. Omission preserves the current responsible; clearing is
 * intentionally a separate DTO flag so partial JSON patches stay compatible.
 */
export function responsibleUserIdFromCustomDataPatch(
  patch: Record<string, unknown> | undefined,
): string | undefined {
  if (!patch || !Object.prototype.hasOwnProperty.call(patch, "responsibleUserId")) {
    return undefined;
  }
  const raw = patch.responsibleUserId;
  if (raw == null || raw === "") return undefined;
  if (typeof raw !== "string" || !isUUID(raw)) {
    throw new BadRequestException(
      "responsibleUserId должен быть UUID активного сотрудника.",
    );
  }
  return raw;
}

/** Replace client-supplied display metadata with the authoritative profile. */
export function applyEligibleResponsibleToCustomData(
  patch: Record<string, unknown>,
  responsible: EligibleResponsible,
): Record<string, unknown> {
  const canonical: Record<string, unknown> = {
    ...patch,
    responsible: responsible.displayName,
    responsibleUserId: responsible.userId,
  };
  delete canonical.responsibleName;
  return canonical;
}

/** Authoritative source for GET /api/admin/staff responsible pickers. */
export async function listEligibleResponsibles(
  executor: ResponsibleEligibilityExecutor,
  query: ResponsiblePickerQuery,
): Promise<Array<{ id: string; displayName: string; role: string }>> {
  const requestedTokens = (query.roles ?? "")
    .split(",")
    .map((role) => role.trim())
    .filter(Boolean);
  const roles = requestedTokens.length
    ? requestedTokens.filter((role) =>
        (RESPONSIBLE_AUTH_ROLES as readonly string[]).includes(role),
      )
    : [...RESPONSIBLE_AUTH_ROLES];
  if (roles.length === 0) return [];

  const search = query.search?.trim() || null;
  const result = await executor.query<{
    id: string;
    display_name: string;
    role: string;
  }>(
    `
      select u.id,
        coalesce(
          nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
          u.full_name,
          u.email
        ) as display_name,
        u.role::text as role
      from app.users u
      join app.profiles p
        on p.user_id = u.id
       and p.deleted_at is null
      join lateral (
        select sm.id
        from app.staff_members sm
        where sm.profile_id = p.id
          and sm.deleted_at is null
          and lower(btrim(sm.status)) = any($3::text[])
        order by sm.created_at desc, sm.id asc
        limit 1
      ) live_staff on true
      where u.deleted_at is null
        and u.role::text = any($1::text[])
        and (
          $2::text is null
          or lower(
            coalesce(p.first_name, '') || ' ' ||
            coalesce(p.last_name, '') || ' ' ||
            coalesce(u.full_name, '') || ' ' ||
            coalesce(u.email, '')
          ) like lower('%' || $2 || '%')
        )
      order by display_name asc, u.id asc
      limit 100
    `,
    [roles, search, [...ACTIVE_RESPONSIBLE_STAFF_STATUSES]],
  );
  return result.rows.map((row) => ({
    id: row.id,
    displayName: row.display_name,
    role: row.role,
  }));
}
