import { BadRequestException, Injectable } from "@nestjs/common";
import {
  ActorContext,
  isManagerRole,
  isStaffRole,
} from "../common/security/actor-context";
import { branchIdExpr } from "../crm/branch-scope";
import { DatabaseService } from "../db/database.service";
import { MessengerListQuery } from "./dto/messenger-list.query";
import {
  ChatMemberRow,
  ChatRow,
  MessageRow,
  toChatMemberDto,
  toChatSummaryDto,
  toMessageDto,
} from "./messenger.mappers";
import { MessengerChatAccessService } from "./messenger-chat-access.service";
import { ANNOUNCEMENTS_CHAT_SLUG } from "./messenger.constants";
import { MessengerPolicy } from "./messenger.policy";

@Injectable()
export class MessengerChatQueryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: MessengerPolicy,
    private readonly access: MessengerChatAccessService,
  ) {}

  async listChats(actor: ActorContext, query: MessengerListQuery) {
    const limit = Math.min(query.limit ?? 50, 100);
    const cursor = this.decodeChatCursor(query.cursor);
    const staffViewer = isStaffRole(actor.role);
    // Folder classification («Лиды»/«Ученики»/архив) and the owner's branch
    // are STAFF inbox concepts. Clients never see folders, so their query
    // skips the classification work entirely (perf: this list is re-fetched
    // by every online client's fallback poll).
    //
    // Folder rules (conversion-proof, правки №2):
    //  1. owner's profile backs a student row (in-app created students);
    //  2. owner has an explicit user_crm_links('student') row (conversion now
    //     writes one in the createStudent conversion CTE);
    //  3. a student exists whose lead_id is the owner's linked lead (covers
    //     conversions from before the link backfill).
    // The old school-wide phone fallback is gone: it pulled ANY same-phone
    // family member's chat into «Ученики» and misfiled unconverted leads.
    const entityFolderSql = staffViewer
      ? `case
            when exists (
              select 1 from app.students s2
              join app.profiles sp2 on sp2.id = s2.profile_id and sp2.deleted_at is null
              where s2.deleted_at is null and sp2.user_id = c.owner_user_id
            ) then 'students'
            when exists (
              select 1 from app.user_crm_links ucs2
              join app.students s6 on s6.id = ucs2.entity_id and s6.deleted_at is null
              where ucs2.user_id = c.owner_user_id
                and ucs2.entity_type = 'student' and ucs2.deleted_at is null
            ) then 'students'
            when exists (
              select 1 from app.user_crm_links ucl6
              join app.students s7 on s7.lead_id = ucl6.entity_id and s7.deleted_at is null
              where ucl6.user_id = c.owner_user_id
                and ucl6.entity_type = 'lead' and ucl6.deleted_at is null
            ) then 'students'
            else 'leads'
          end`
      : `null::text`;
    const folderSql = staffViewer
      ? `case
            when ist.archived_at is not null then 'archive'
            else inbox_folder.entity_folder
          end`
      : `null::text`;
    // The client's branch. Order matters after conversion: the STUDENT's
    // branch (link or lead_id resolution) wins over the stale lead's, so
    // moving the student to another branch moves the chat too. Every link
    // subquery is deterministic (freshest confirmed link first) — previously
    // an unordered `limit 1` picked a random duplicate lead.
    const branchLateralSql = staffViewer
      ? `left join lateral (
          select b.id::text as branch_id, b.name as branch_name
          from app.branches b
          where b.deleted_at is null
            and b.id::text = coalesce(
              (
                select ${branchIdExpr("s")}
                from app.user_crm_links ucs
                join app.students s on s.id = ucs.entity_id and s.deleted_at is null
                where ucs.user_id = c.owner_user_id
                  and ucs.entity_type = 'student' and ucs.deleted_at is null
                order by ucs.confirmed_at desc nulls last, ucs.created_at desc
                limit 1
              ),
              (
                select ${branchIdExpr("s4")}
                from app.user_crm_links ucl4
                join app.students s4 on s4.lead_id = ucl4.entity_id and s4.deleted_at is null
                where ucl4.user_id = c.owner_user_id
                  and ucl4.entity_type = 'lead' and ucl4.deleted_at is null
                order by ucl4.confirmed_at desc nulls last, ucl4.created_at desc
                limit 1
              ),
              (
                select ${branchIdExpr("s3")}
                from app.students s3
                join app.profiles sp3 on sp3.id = s3.profile_id and sp3.deleted_at is null
                where sp3.user_id = c.owner_user_id and s3.deleted_at is null
                limit 1
              ),
              (
                select ${branchIdExpr("l")}
                from app.user_crm_links ucl
                join app.leads l on l.id = ucl.entity_id and l.deleted_at is null
                where ucl.user_id = c.owner_user_id
                  and ucl.entity_type = 'lead' and ucl.deleted_at is null
                order by ucl.confirmed_at desc nulls last, ucl.created_at desc
                limit 1
              )
            )
          limit 1
        ) owner_branch on true`
      : `left join lateral (
          select null::text as branch_id, null::text as branch_name
        ) owner_branch on true`;
    const result = await this.database.query<ChatRow>(
      `
        select distinct c.id, c.type, c.title, c.created_by, c.last_message_id,
          lm.content as last_message_content, lm.created_at as last_message_created_at,
          partner.user_id as partner_user_id,
          partner_u.email as partner_email,
          partner_p.first_name as partner_first_name,
          partner_p.last_name as partner_last_name,
          partner_p.avatar_file_id as partner_avatar_file_id,
          c.created_at, c.updated_at,
          to_char(
            c.updated_at at time zone 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
          ) as cursor_updated_at,
          (me_state.muted_until is not null and me_state.muted_until > now()) as is_muted,
          c.slug, c.is_system,
          (
            select count(*)
            from app.messages unread
            left join app.chat_members me
              on me.chat_id = c.id and me.user_id = $2 and me.left_at is null
            where unread.chat_id = c.id
              and unread.deleted_at is null
              and (unread.sender_id is null or unread.sender_id <> $2)
              and (me.last_read_message_id is null or unread.created_at > (
                select created_at from app.messages where id = me.last_read_message_id
              ))
          )::text as unread_count,
          owp.first_name as owner_first_name,
          owp.last_name as owner_last_name,
          c.assigned_to_user_id,
          asgp.first_name as assigned_first_name,
          asgp.last_name as assigned_last_name,
          ist.archived_at,
          ${folderSql} as folder,
          owner_branch.branch_id as branch_id,
          owner_branch.branch_name as branch_name
        from app.chats c
        left join app.chat_members cm on cm.chat_id = c.id and cm.left_at is null
        left join app.chat_members me_state
          on me_state.chat_id = c.id and me_state.user_id = $2 and me_state.left_at is null
        left join app.messages lm on lm.id = c.last_message_id
        left join lateral (
          select chat_partner.user_id
          from app.chat_members chat_partner
          where chat_partner.chat_id = c.id
            and chat_partner.left_at is null
            and chat_partner.user_id <> $2
          order by chat_partner.joined_at asc
          limit 1
        ) partner on true
        left join app.users partner_u on partner_u.id = partner.user_id and partner_u.deleted_at is null
        left join app.profiles partner_p on partner_p.user_id = partner_u.id and partner_p.deleted_at is null
        left join app.users ow on ow.id = c.owner_user_id and ow.deleted_at is null
        left join app.profiles owp on owp.user_id = ow.id and owp.deleted_at is null
        left join app.users asg on asg.id = c.assigned_to_user_id and asg.deleted_at is null
        left join app.profiles asgp on asgp.user_id = asg.id and asgp.deleted_at is null
        left join app.chat_inbox_state ist on ist.chat_id = c.id and ist.staff_user_id = $2
        left join lateral (
          select ${entityFolderSql} as entity_folder
        ) inbox_folder on true
        ${branchLateralSql}
        where c.deleted_at is null
          and ($3::timestamptz is null or c.updated_at < $3)
          and (
            $7::timestamptz is null
            or c.updated_at < $7::timestamptz
            or (c.updated_at = $7::timestamptz and c.id < $8::uuid)
          )
          and (
            cm.user_id = $2
            or ($1::text in ('manager', 'director', 'admin', 'system_admin') and c.type = 'administration')
          )
          -- Branch filter is strict: unassigned clients stay out of every
          -- branch-specific inbox until a branch is explicitly known.
          and (
            $5::uuid is null
            or c.type <> 'administration'
            or owner_branch.branch_id = $5::text
          )
          -- Contract 3: archived=true → only the actor's archived chats;
          -- default → archived hidden. Clients have no inbox state, so their
          -- chats are never archived away from them.
          and (case when $6::boolean then ist.archived_at is not null
                    else ist.archived_at is null end)
          -- Folder classification is evaluated on active CRM entities and is
          -- independent of archived state. Archived rows still report
          -- folder='archive', while folder=leads|students can narrow them by
          -- their underlying CRM entity when explicitly requested.
          and (
            $9::text = 'all'
            or (
              c.type = 'administration'
              and inbox_folder.entity_folder = $9::text
            )
          )
        order by c.updated_at desc, c.id desc
        limit $4
      `,
      [
        actor.role,
        actor.userId,
        cursor == null ? (query.before ?? null) : null,
        limit + 1,
        query.branchId ?? null,
        query.archived === true,
        cursor?.updatedAt ?? null,
        cursor?.id ?? null,
        query.folder ?? "all",
      ],
    );

    const pageRows = result.rows.slice(0, limit);
    return {
      items: pageRows.map((row) =>
        toChatSummaryDto(row, {
          canWrite: this.canWriteChatSummary(actor, row),
        }),
      ),
      nextCursor:
        result.rows.length > limit && pageRows.length > 0
          ? this.encodeChatCursor(pageRows[pageRows.length - 1])
          : null,
    };
  }

  private decodeChatCursor(
    cursor: string | undefined,
  ): { updatedAt: string; id: string } | null {
    if (!cursor) return null;
    try {
      const decoded = JSON.parse(
        Buffer.from(cursor, "base64url").toString("utf8"),
      ) as unknown;
      if (!Array.isArray(decoded) || decoded.length !== 2) throw new Error();
      const [updatedAt, id] = decoded;
      if (
        typeof updatedAt !== "string" ||
        !/^[1-9]\d{3}-(0[1-9]|1[0-2])-([0-2]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d\.\d{6}Z$/.test(
          updatedAt,
        ) ||
        !this.isValidChatCursorCalendarDate(updatedAt) ||
        typeof id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          id,
        )
      ) {
        throw new Error();
      }
      // Keep PostgreSQL's six fractional digits verbatim. Normalising through
      // JS Date/toISOString would truncate microseconds and skip keyset rows.
      return { updatedAt, id };
    } catch {
      throw new BadRequestException("Invalid chat cursor");
    }
  }

  private encodeChatCursor(
    row: Pick<ChatRow, "cursor_updated_at" | "id">,
  ): string {
    const updatedAt = row.cursor_updated_at;
    if (!updatedAt) {
      throw new Error("Missing exact chat cursor timestamp");
    }
    return Buffer.from(JSON.stringify([updatedAt, row.id]), "utf8").toString(
      "base64url",
    );
  }

  private isValidChatCursorCalendarDate(value: string): boolean {
    const wholeSeconds = `${value.slice(0, 19)}Z`;
    const parsed = new Date(wholeSeconds);
    return (
      Number.isFinite(parsed.getTime()) &&
      parsed.toISOString().slice(0, 19) === value.slice(0, 19)
    );
  }

  /**
   * Server-declared composer visibility (правки №2, «Объявления»): the client
   * must not guess read-only-ness from a slug string. Mirrors
   * MessengerPolicy.assertCanWriteChat for the announcements chat; every other
   * chat in the actor's list is writable by construction.
   */
  private canWriteChatSummary(
    actor: ActorContext,
    row: Pick<ChatRow, "slug">,
  ): boolean {
    if (row.slug === ANNOUNCEMENTS_CHAT_SLUG) {
      return isManagerRole(actor.role);
    }
    return true;
  }

  async getMessages(
    actor: ActorContext,
    chatId: string,
    query: MessengerListQuery,
  ) {
    const chat = await this.access.requireChat(actor, chatId);
    this.policy.assertCanReadChat(actor, chat);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<MessageRow>(
      `
        select m.id, m.chat_id, m.sender_id, m.content, m.message_type,
          m.attachment_file_id, m.voice_duration_ms, m.reply_to_id,
          m.forwarded_from_id,
          m.pinned_by, m.pinned_at, m.created_at, m.updated_at,
          m.deleted_at, u.email as sender_email, p.first_name as sender_first_name,
          p.last_name as sender_last_name,
          u.role as sender_role,
          p.avatar_file_id as sender_avatar_file_id,
          f.original_name as attachment_original_name,
          f.mime_type as attachment_mime_type,
          f.size_bytes as attachment_size_bytes,
          case
            when m.sender_id = $4 then not exists (
              select 1
              from app.chat_members unread_member
              left join app.messages read_marker
                on read_marker.id = unread_member.last_read_message_id
              where unread_member.chat_id = m.chat_id
                and unread_member.left_at is null
                and unread_member.user_id <> m.sender_id
                and (
                  unread_member.last_read_message_id is null
                  or read_marker.created_at < m.created_at
                )
            )
            else true
          end as is_read,
          coalesce((
            select json_agg(
              json_build_object('emoji', r.emoji, 'count', r.cnt, 'reactedByMe', r.me)
              order by r.first_at
            )
            from (
              select emoji, count(*)::int as cnt,
                     bool_or(user_id = $4) as me,
                     min(created_at) as first_at
              from app.message_reactions
              where message_id = m.id
              group by emoji
            ) r
          ), '[]'::json) as reactions
        from app.messages m
        left join app.users u on u.id = m.sender_id
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        left join app.file_objects f on f.id = m.attachment_file_id and f.deleted_at is null
        where m.chat_id = $1
          and ($2::timestamptz is null or m.created_at < $2)
        order by m.created_at desc, m.id desc
        limit $3
      `,
      [chatId, query.before ?? null, limit, actor.userId],
    );

    // Privacy: the single non-staff member of an administration chat is its
    // owner (the client). They must never receive a staff member's real
    // identity. Staff viewers always see real identities.
    const viewerMasksStaff =
      chat.type === "administration" && !isStaffRole(actor.role as never);

    return {
      items: result.rows
        .map((row) =>
          toMessageDto(row, {
            maskStaffSender:
              viewerMasksStaff && isStaffRole((row.sender_role ?? "") as never),
          }),
        )
        .reverse(),
    };
  }

  async listChatMembers(actor: ActorContext, chatId: string) {
    const chat = await this.access.requireChat(actor, chatId);
    this.policy.assertCanReadChat(actor, chat);

    const result = await this.database.query<ChatMemberRow>(
      `
        select p.id as profile_id, cm.user_id, u.email, cm.role, u.role as user_role,
          p.first_name, p.last_name,
          p.phone, p.avatar_file_id, cm.joined_at
        from app.chat_members cm
        join app.users u on u.id = cm.user_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where cm.chat_id = $1
          and cm.left_at is null
        order by
          case when cm.role = 'admin' then 0 else 1 end,
          p.last_name nulls last,
          p.first_name nulls last,
          u.email nulls last,
          cm.user_id
      `,
      [chatId],
    );

    return {
      items: result.rows.map((row) => toChatMemberDto(row, actor.userId)),
    };
  }


  async getChat(actor: ActorContext, chatId: string) {
    const chat = await this.access.requireChat(actor, chatId);
    this.policy.assertCanReadChat(actor, chat);
    const result = await this.database.query<ChatRow>(
      `
        select c.id, c.type, c.title, c.created_by, c.last_message_id,
          lm.content as last_message_content, lm.created_at as last_message_created_at,
          partner.user_id as partner_user_id,
          partner_u.email as partner_email,
          partner_p.first_name as partner_first_name,
          partner_p.last_name as partner_last_name,
          partner_p.avatar_file_id as partner_avatar_file_id,
          '0'::text as unread_count,
          (cm.muted_until is not null and cm.muted_until > now()) as is_muted,
          c.created_at, c.updated_at, c.slug, c.is_system
        from app.chats c
        left join app.chat_members cm on cm.chat_id = c.id and cm.user_id = $2 and cm.left_at is null
        left join app.messages lm on lm.id = c.last_message_id
        left join lateral (
          select chat_partner.user_id
          from app.chat_members chat_partner
          where chat_partner.chat_id = c.id
            and chat_partner.left_at is null
            and chat_partner.user_id <> $2
          order by chat_partner.joined_at asc
          limit 1
        ) partner on true
        left join app.users partner_u on partner_u.id = partner.user_id and partner_u.deleted_at is null
        left join app.profiles partner_p on partner_p.user_id = partner_u.id and partner_p.deleted_at is null
        where c.id = $1 and c.deleted_at is null
        limit 1
      `,
      [chatId, actor.userId],
    );
    return toChatSummaryDto(result.rows[0], {
      canWrite: this.canWriteChatSummary(actor, result.rows[0]),
    });
  }

}
