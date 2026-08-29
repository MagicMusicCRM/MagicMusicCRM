import { Logger } from "@nestjs/common";
import type { QueryResult, QueryResultRow } from "pg";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import {
  ACTIVE_RESPONSIBLE_STAFF_STATUSES,
  RESPONSIBLE_AUTH_ROLES,
} from "./responsible-eligibility";

const logger = new Logger("EnsureResponsible");

export type ResponsibleEntityType = "lead" | "student";

export interface ResponsibleQueryExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

/**
 * Auto-claim an empty responsible slot.
 *
 * Leads use leads.assigned_to as the canonical relation. The two custom-data
 * keys are only a compatibility mirror for older card builds and are always
 * derived from assigned_to when that relation exists. An imported display-only
 * responsible is preserved until a user explicitly chooses a canonical owner.
 *
 * Students do not have assigned_to, so their existing custom-data contract is
 * retained.
 */
export async function ensureResponsible(
  database: ResponsibleQueryExecutor,
  actor: ActorContext,
  entityType: ResponsibleEntityType,
  entityId: string,
): Promise<number | null> {
  if (!(RESPONSIBLE_AUTH_ROLES as readonly string[]).includes(actor.role)) {
    return null;
  }

  if (entityType === "lead") {
    const claimed = await database.query<{ version: string | number }>(
      `
        with eligible_actor as (
          select u.id as user_id,
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
          where u.id = $2
            and u.deleted_at is null
            and u.role::text = any($3::text[])
            and lower(btrim(sm.status)) = any($4::text[])
          order by sm.created_at desc, sm.id asc
          limit 1
          for update of l
        ),
        target as (
          select l.id
          from app.leads l
          cross join eligible_actor
          where l.id = $1
            and l.deleted_at is null
              and l.assigned_to is null
              and nullif(btrim(coalesce(l.custom_data->>'responsible', '')), '') is null
            returning l.version
          limit 1
        )
        update app.leads l
        set assigned_to = eligible_actor.user_id,
              custom_data = coalesce(l.custom_data, '{}'::jsonb)
            || jsonb_build_object(
                 'responsible', eligible_actor.display_name,
                 'responsibleUserId', eligible_actor.user_id::text
                   ),
              version = l.version + 1,
              updated_at = now()
        from target, eligible_actor
        where l.id = target.id
          and l.assigned_to is null
          and nullif(btrim(coalesce(l.custom_data->>'responsible', '')), '') is null
      `,
      [
        entityId,
        actor.userId,
        [...RESPONSIBLE_AUTH_ROLES],
        [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
      ],
    );
    return claimed.rows[0] ? Number(claimed.rows[0].version) : null;
  }

  const claimed = await database.query<{ version: string | number }>(
    `
      with eligible_actor as (
        select u.id as user_id,
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
        where u.id = $2
          and u.deleted_at is null
          and u.role::text = any($3::text[])
          and lower(btrim(sm.status)) = any($4::text[])
        order by sm.created_at desc, sm.id asc
        limit 1
      )
      update app.students s
          set custom_data = coalesce(s.custom_data, '{}'::jsonb)
        || jsonb_build_object(
             'responsible', eligible_actor.display_name,
             'responsibleUserId', eligible_actor.user_id::text
               ),
            version = s.version + 1,
            updated_at = now()
      from eligible_actor
      where s.id = $1
        and s.deleted_at is null
        and coalesce(s.custom_data->>'responsible', '') = ''
      returning s.version
    `,
    [
      entityId,
      actor.userId,
      [...RESPONSIBLE_AUTH_ROLES],
      [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
    ],
  );
  return claimed.rows[0] ? Number(claimed.rows[0].version) : null;
}

/**
 * Awaitable best-effort wrapper. Responsibility is settled before audit and
 * realtime publication, while a secondary metadata failure still cannot turn
 * the primary card mutation into an HTTP 500.
 */
export async function ensureResponsibleSafe(
  database: DatabaseService,
  actor: ActorContext,
  entityType: ResponsibleEntityType,
  entityId: string,
): Promise<number | null> {
  try {
    return await ensureResponsible(database, actor, entityType, entityId);
  } catch (error: unknown) {
    logger.warn(
      `ensureResponsible failed for ${entityType} ${entityId}: ${String(error)}`,
    );
    return null;
  }
}

/**
 * Resolve the CRM contact behind an administration chat and claim both
 * canonical lead ownership and the student's compatibility metadata. Designed
 * to run on the same transaction client as chats.assigned_to_user_id.
 */
export async function ensureChatContactResponsible(
  database: ResponsibleQueryExecutor,
  responsibleActor: ActorContext,
  chatId: string,
): Promise<void> {
  const contact = await database.query<{
    lead_id: string | null;
    student_id: string | null;
  }>(
    `
      select
        (
          select ucl.entity_id
          from app.user_crm_links ucl
          where ucl.user_id = c.owner_user_id
            and ucl.entity_type = 'lead'
            and ucl.deleted_at is null
          order by ucl.confirmed_at desc nulls last, ucl.created_at desc
          limit 1
        ) as lead_id,
        coalesce(
          (
            select ucs.entity_id
            from app.user_crm_links ucs
            join app.students linked_student
              on linked_student.id = ucs.entity_id
             and linked_student.deleted_at is null
            where ucs.user_id = c.owner_user_id
              and ucs.entity_type = 'student'
              and ucs.deleted_at is null
            order by ucs.confirmed_at desc nulls last, ucs.created_at desc
            limit 1
          ),
          (
            select owned_student.id
            from app.students owned_student
            join app.profiles owned_profile
              on owned_profile.id = owned_student.profile_id
             and owned_profile.deleted_at is null
            where owned_profile.user_id = c.owner_user_id
              and owned_student.deleted_at is null
            order by owned_student.created_at desc
            limit 1
          ),
          (
            select converted_student.id
            from app.user_crm_links lead_link
            join app.students converted_student
              on converted_student.lead_id = lead_link.entity_id
             and converted_student.deleted_at is null
            where lead_link.user_id = c.owner_user_id
              and lead_link.entity_type = 'lead'
              and lead_link.deleted_at is null
            order by lead_link.confirmed_at desc nulls last,
              lead_link.created_at desc,
              converted_student.created_at desc
            limit 1
          )
        ) as student_id
      from app.chats c
      where c.id = $1 and c.deleted_at is null
      limit 1
    `,
    [chatId],
  );
  const row = contact.rows[0];
  if (!row) return;
  if (row.lead_id) {
    await ensureResponsible(
      database,
      responsibleActor,
      "lead",
      row.lead_id,
    );
  }
  if (row.student_id) {
    await ensureResponsible(
      database,
      responsibleActor,
      "student",
      row.student_id,
    );
  }
}
