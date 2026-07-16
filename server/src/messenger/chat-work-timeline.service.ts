import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";

/**
 * Row shape returned by the chat-work timeline read. Structurally matches the
 * shared `TimelineRow` in crm/crm-mappers, but is declared here so this module
 * owns its contract without depending on the CRM module.
 */
export interface ChatWorkTimelineRow {
  id: string;
  type: string;
  title: string;
  body: string | null;
  status: string | null;
  amount: string | number | null;
  actor_user_id: string | null;
  actor_first_name: string | null;
  actor_last_name: string | null;
  occurred_at: Date | string;
}

/**
 * The SELECT…FROM…WHERE for "taken into / removed from work" events on an
 * administration chat tied to a CRM entity. It reads messenger-owned tables
 * (app.chats, app.chat_work_events); exposing it as one constant means a
 * messenger schema change touches a single place instead of the three CRM
 * queries that used to inline this SQL byte-for-byte.
 *
 * No ORDER BY / LIMIT so callers can either append them (standalone) or splice
 * the fragment into a larger UNION (the unified entity timeline).
 * Bind params: $1 = entity type ('student' | 'lead'), $2 = entity id (uuid).
 */
export const CHAT_WORK_TIMELINE_FRAGMENT = `
  select work.id::text as id, 'chat_work'::text as type,
    case
      when work.action = 'unassigned' then 'Снято с работы'
      else 'Взято в работу'
    end as title,
    nullif(
      trim(coalesce(target_profile.first_name, '') || ' ' || coalesce(target_profile.last_name, '')),
      ''
    ) as body,
    work.action as status, null::numeric as amount,
    work.actor_user_id,
    actor_profile.first_name as actor_first_name,
    actor_profile.last_name as actor_last_name,
    work.created_at as occurred_at
  from app.chat_work_events work
  join app.chats chat on chat.id = work.chat_id and chat.deleted_at is null
  left join app.users actor_user on actor_user.id = work.actor_user_id and actor_user.deleted_at is null
  left join app.profiles actor_profile on actor_profile.user_id = actor_user.id and actor_profile.deleted_at is null
  left join app.users target_user on target_user.id = work.target_user_id and target_user.deleted_at is null
  left join app.profiles target_profile on target_profile.user_id = target_user.id and target_profile.deleted_at is null
  where chat.type = 'administration'
    and (
      ($1 = 'student' and (
        chat.student_id = $2::uuid
        or exists (
          select 1
          from app.user_crm_links link
          where link.entity_type = 'student'
            and link.entity_id = $2::uuid
            and link.user_id = chat.owner_user_id
            and link.deleted_at is null
        )
      ))
      or ($1 = 'lead' and (
        chat.lead_id = $2::uuid
        or exists (
          select 1
          from app.user_crm_links link
          where link.entity_type = 'lead'
            and link.entity_id = $2::uuid
            and link.user_id = chat.owner_user_id
            and link.deleted_at is null
        )
      ))
    )
`;

/**
 * Messenger-owned read API for the "chat taken into work" activity that the CRM
 * entity timelines surface. CRM used to reach straight into app.chats /
 * app.chat_work_events from three different services; it now depends on this
 * port instead, so the messenger schema has a single CRM-facing consumer.
 *
 * Lives under messenger/ (ownership) and depends only on DatabaseModule, so
 * CrmModule can import it without a module cycle (MessengerModule → CrmModule
 * via LEAD_INTAKE_PORT stays the only edge between the big modules).
 */
@Injectable()
export class ChatWorkTimelineService {
  constructor(private readonly database: DatabaseService) {}

  async listForEntity(
    entityType: "student" | "lead",
    entityId: string,
  ): Promise<ChatWorkTimelineRow[]> {
    const result = await this.database.query<ChatWorkTimelineRow>(
      `
        ${CHAT_WORK_TIMELINE_FRAGMENT}
        order by work.created_at desc, work.id desc
        limit 50
      `,
      [entityType, entityId],
    );
    return result?.rows ?? [];
  }
}
