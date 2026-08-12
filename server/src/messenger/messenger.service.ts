import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerRole,
  isStaffRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { branchIdExpr } from "../crm/branch-scope";
import { RealtimeBus } from "../realtime/realtime-bus";
import { LEAD_INTAKE_PORT, LeadIntakePort } from "../common/lead-intake.port";
import { CreateDirectChatDto } from "./dto/create-direct-chat.dto";
import { CreateGroupChatDto } from "./dto/create-group-chat.dto";
import { MessengerListQuery } from "./dto/messenger-list.query";
import { SetChatMuteDto } from "./dto/set-chat-mute.dto";
import { SendMessageDto } from "./dto/send-message.dto";
import { UpdateGroupMembersDto } from "./dto/update-group-members.dto";
import {
  ChatMemberRow,
  ChatRow,
  MessageRow,
  toChatMemberDto,
  toChatSummaryDto,
  toMessageDto,
} from "./messenger.mappers";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

interface ChatAttachmentRow {
  id: string;
  purpose: "chat_attachment" | "chat_voice";
  mime_type: string;
}

@Injectable()
export class MessengerService implements OnModuleInit {
  private readonly logger = new Logger(MessengerService.name);

  /** Stable identity of the default system "Объявления" channel. */
  static readonly announcementsSlug = "announcements";

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: MessengerPolicy,
    private readonly realtime: RealtimeGateway,
    @Inject(LEAD_INTAKE_PORT) private readonly leadIntake: LeadIntakePort,
    private readonly realtimeBus: RealtimeBus,
    private readonly fanout: MessengerFanoutService,
  ) {}

  async onModuleInit(): Promise<void> {
    // Self-heal the durable default channels on boot. Idempotent and best-effort
    // (migration 0042 already seeds them; this covers fresh/partial databases).
    try {
      await this.ensureAnnouncementsChat();
    } catch (err) {
      this.logger.warn(`ensureAnnouncementsChat failed: ${String(err)}`);
    }
  }

  /**
   * Idempotently ensure the system "Объявления" GROUP CHAT exists and that every
   * active user is a member (only управляющий/директор may post — enforced in the
   * policy). Migration 0058 converts the legacy channel into this chat; this
   * self-heals fresh databases and backfills membership for imported/new users on
   * every boot. Safe to call repeatedly.
   */
  async ensureAnnouncementsChat(): Promise<void> {
    await this.database.transaction(async (client) => {
      const existing = await client.query<{ id: string }>(
        `select id from app.chats where slug = $1 and deleted_at is null limit 1`,
        [MessengerService.announcementsSlug],
      );
      let chatId = existing.rows[0]?.id;
      if (!chatId) {
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.chats (type, title, slug, is_system)
            values ('group', 'Объявления', $1, true)
            returning id
          `,
          [MessengerService.announcementsSlug],
        );
        chatId = inserted.rows[0].id;
      }

      // Backfill membership for every active user (covers imported/new users).
      await client.query(
        `
          insert into app.chat_members (chat_id, user_id, role)
          select $1, u.id,
            case when u.role in ('manager', 'director') then 'admin' else 'member' end
          from app.users u
          where u.deleted_at is null
          on conflict (chat_id, user_id) do nothing
        `,
        [chatId],
      );
    });
  }

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
    if (row.slug === MessengerService.announcementsSlug) {
      return isManagerRole(actor.role);
    }
    return true;
  }

  async getMessages(
    actor: ActorContext,
    chatId: string,
    query: MessengerListQuery,
  ) {
    const chat = await this.requireChat(actor, chatId);
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
    const chat = await this.requireChat(actor, chatId);
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

  async sendMessage(actor: ActorContext, chatId: string, dto: SendMessageDto) {
    const chat = await this.requireChat(actor, chatId);
    this.policy.assertCanWriteChat(actor, chat);
    await this.policy.assertNotBlacklisted(actor);
    const content = dto.content?.trim() || null;
    if (!content && !dto.attachmentFileId) {
      throw new BadRequestException("Сообщение не может быть пустым.");
    }
    let attachment: ChatAttachmentRow | null = null;
    if (dto.attachmentFileId) {
      attachment = await this.assertValidChatAttachment(
        actor.userId,
        chatId,
        dto.attachmentFileId,
      );
    }
    const messageType =
      dto.messageType ?? (dto.attachmentFileId ? "file" : "text");
    this.assertMessagePayload(messageType, attachment, dto.voiceDurationMs);
    await this.assertValidMessageReferences(
      actor,
      chatId,
      dto.replyToId,
      dto.forwardedFromId,
    );
    const shouldResurface =
      chat.type === "administration" && actor.role === "client";

    const message = await this.database.transaction(async (client) => {
      const inserted = await client.query<MessageRow>(
        `
          insert into app.messages (
            chat_id, sender_id, content, message_type, attachment_file_id,
            voice_duration_ms, reply_to_id, forwarded_from_id
          )
          values ($1, $2, $3, $4, $5, $6, $7, $8)
          returning id, chat_id, sender_id, content, message_type,
            attachment_file_id, voice_duration_ms, reply_to_id,
            forwarded_from_id,
            pinned_by, pinned_at, created_at, updated_at, deleted_at,
            (select email from app.users where id = app.messages.sender_id) as sender_email,
            (
              select first_name from app.profiles
              where user_id = app.messages.sender_id and deleted_at is null
              limit 1
            ) as sender_first_name,
            (
              select last_name from app.profiles
              where user_id = app.messages.sender_id and deleted_at is null
              limit 1
            ) as sender_last_name,
            (select role from app.users where id = app.messages.sender_id) as sender_role,
            (
              select avatar_file_id from app.profiles
              where user_id = app.messages.sender_id and deleted_at is null
              limit 1
            ) as sender_avatar_file_id,
            (
              select original_name from app.file_objects where id = $5
            ) as attachment_original_name,
            (
              select mime_type from app.file_objects where id = $5
            ) as attachment_mime_type,
            (
              select size_bytes from app.file_objects where id = $5
            ) as attachment_size_bytes,
            false as is_read
        `,
        [
          chatId,
          actor.userId,
          content,
          messageType,
          dto.attachmentFileId ?? null,
          dto.voiceDurationMs ?? null,
          dto.replyToId ?? null,
          dto.forwardedFromId ?? null,
        ],
      );
      const row = inserted.rows[0];
      await client.query(
        "update app.chats set last_message_id = $2, updated_at = now() where id = $1",
        [chatId, row.id],
      );
      if (shouldResurface) {
        // Inbox state and the inbound message are one commit. Realtime must
        // never advertise a message while staff list reads still see Archive.
        await client.query(
          "update app.chat_inbox_state set archived_at = null where chat_id = $1",
          [chatId],
        );
      }
      return row;
    });

    const payload = toMessageDto(message);
    if (shouldResurface) {
      // Complete first-contact intake before advertising the message/list
      // update. Any staff refresh triggered by this event must observe the
      // newly committed CRM link and therefore the authoritative bucket.
      try {
        await this.leadIntake.autoCreateLeadFromChat(actor, actor.userId);
      } catch (error) {
        // The message has already committed. Intake is idempotent and the next
        // client message can retry it; never force a resend of stored content.
        this.logger.error(
          `First-contact lead intake failed for ${actor.userId}: ${String(error)}`,
        );
      }
    }
    if (shouldResurface) {
      // State-only patch first: the regular list fanout below carries the one
      // last-message/unread update, avoiding duplicate unread increments.
      this.realtime.publishAdminInboxEvent("chat.updated", {
        id: chatId,
        archived: false,
      });
    }
    // Privacy: administration chat audiences need different sender views.
    // Clients receive masked staff authors; staff receive the real author.
    const maskedPayload =
      chat.type === "administration" && isStaffRole(actor.role)
        ? toMessageDto(message, { maskStaffSender: true })
        : payload;
    await this.fanout.publishMessageEventForAudience(
      chat,
      chatId,
      "message.created",
      payload,
      maskedPayload,
    );
    await this.fanout.fanoutChatListUpdate(chat, chatId, payload, {
      maskStaffSenderForMembers:
        chat.type === "administration" && isStaffRole(actor.role),
    });
    if (shouldResurface) {
      // Resurface ONLY on a client message: a new client note should pull the
      // thread back into every staff inbox. A STAFF reply must not — otherwise
      // the moment you answer a chat you just archived, it un-archives itself
      // (and for every other staff member too), so «архивировать» never stuck.
    }
    return payload;
  }

  async createDirectChat(actor: ActorContext, dto: CreateDirectChatDto) {
    if (dto.type === "administration")
      return this.createAdministrationChat(actor);
    if (!dto.targetUserId)
      throw new BadRequestException("Целевой пользователь обязателен.");
    await this.policy.canCreateDirectChat(actor, dto.targetUserId);

    const chat = await this.database.transaction(async (client) => {
      const existing = await client.query<ChatRow>(
        `
          select c.id, c.type, c.title, c.created_by, c.last_message_id,
            null::text as last_message_content, null::timestamptz as last_message_created_at,
            $2::uuid as partner_user_id,
            '0'::text as unread_count, c.created_at, c.updated_at
          from app.chats c
          join app.chat_members a on a.chat_id = c.id and a.user_id = $1 and a.left_at is null
          join app.chat_members b on b.chat_id = c.id and b.user_id = $2 and b.left_at is null
          where c.type = 'direct' and c.deleted_at is null
          limit 1
        `,
        [actor.userId, dto.targetUserId],
      );
      if (existing.rows[0]) return existing.rows[0];

      const inserted = await client.query<ChatRow>(
        `
          insert into app.chats (type, created_by)
          values ('direct', $1)
          returning id, type, title, created_by, last_message_id,
            null::text as last_message_content, null::timestamptz as last_message_created_at,
            $2::uuid as partner_user_id,
            '0'::text as unread_count, created_at, updated_at
        `,
        [actor.userId, dto.targetUserId],
      );
      const row = inserted.rows[0];
      await this.insertMembers(client, row.id, [
        { userId: actor.userId, role: "member" },
        { userId: dto.targetUserId!, role: "member" },
      ]);
      return row;
    });

    return toChatSummaryDto(chat);
  }

  async createGroup(actor: ActorContext, dto: CreateGroupChatDto) {
    this.policy.assertCanCreateGroup(actor);
    const name = dto.name.trim();
    if (!name) throw new BadRequestException("Укажите название группы.");
    if (dto.memberUserIds.length === 0) {
      throw new BadRequestException(
        "Добавьте хотя бы одного участника группы.",
      );
    }
    const uniqueMembers = Array.from(
      new Set([actor.userId, ...dto.memberUserIds]),
    );
    await this.assertActiveUsers(uniqueMembers);
    const chat = await this.database.transaction(async (client) => {
      const inserted = await client.query<ChatRow>(
        `
          insert into app.chats (type, title, created_by)
          values ('group', $1, $2)
          returning id, type, title, created_by, last_message_id,
            null::text as last_message_content, null::timestamptz as last_message_created_at,
            '0'::text as unread_count, created_at, updated_at
        `,
        [name, actor.userId],
      );
      const row = inserted.rows[0];
      await this.insertMembers(
        client,
        row.id,
        uniqueMembers.map((userId) => ({
          userId,
          role: userId === actor.userId ? "admin" : "member",
        })),
      );
      return row;
    });

    await this.audit.record({
      actor,
      action: "messenger.group_created",
      entityType: "chat",
      entityId: chat.id,
    });

    const summary = toChatSummaryDto(chat);
    // Fan-out: every member receives chat.created so the group appears live.
    for (const userId of uniqueMembers) {
      this.realtime.publishUserEvent(userId, "chat.created", summary);
    }
    return summary;
  }

  async updateGroupMembers(
    actor: ActorContext,
    chatId: string,
    dto: UpdateGroupMembersDto,
  ) {
    const chat = await this.requireChat(actor, chatId);
    this.policy.assertCanManageGroup(actor, chat);
    if (chat.type !== "group")
      throw new NotFoundException("Группа не найдена.");
    if (chat.isSystem) {
      throw new ForbiddenException(
        "Состав участников системного чата «Объявления» изменять нельзя.",
      );
    }
    const addUserIds = Array.from(new Set(dto.addUserIds ?? []));
    const removeUserIds = Array.from(new Set(dto.removeUserIds ?? []));
    if (addUserIds.length === 0 && removeUserIds.length === 0) {
      throw new BadRequestException("Не указаны изменения состава группы.");
    }
    if (
      chat.memberUserId === actor.userId &&
      removeUserIds.includes(actor.userId)
    ) {
      throw new BadRequestException(
        "Для выхода из группы используйте действие «Выйти из группы».",
      );
    }
    if (addUserIds.some((userId) => removeUserIds.includes(userId))) {
      throw new BadRequestException(
        "Нельзя одновременно добавить и удалить одного участника.",
      );
    }
    await this.assertActiveUsers(addUserIds);

    await this.database.transaction(async (client) => {
      if (addUserIds.length) {
        await this.insertMembers(
          client,
          chatId,
          addUserIds.map((userId) => ({ userId, role: "member" })),
        );
      }
      if (removeUserIds.length) {
        const removed = await client.query<{ user_id: string }>(
          `
            update app.chat_members
            set left_at = now()
            where chat_id = $1 and user_id = any($2::uuid[])
              and left_at is null
            returning user_id
          `,
          [chatId, removeUserIds],
        );
        if (removed.rows.length !== removeUserIds.length) {
          throw new BadRequestException(
            "Один или несколько пользователей уже не состоят в группе.",
          );
        }
      }
      if (chat.memberUserId !== actor.userId) {
        const remaining = await client.query<{ count: string }>(
          `
            select count(*)::text as count
            from app.chat_members
            where chat_id = $1 and left_at is null
          `,
          [chatId],
        );
        if (Number(remaining.rows[0]?.count ?? 0) === 0) {
          throw new BadRequestException(
            "В группе должен остаться хотя бы один участник.",
          );
        }
      }
      await client.query(
        "update app.chats set updated_at = now() where id = $1",
        [chatId],
      );
    });

    await this.audit.record({
      actor,
      action: "messenger.group_members_updated",
      entityType: "chat",
      entityId: chatId,
    });
    this.realtime.publishChatEvent(chatId, "chat.updated", { id: chatId });
    const result = await this.getChat(actor, chatId);
    // Fan-out: added members receive chat.created; removed members receive chat.removed.
    // The summary from getChat carries the manager's actor-scoped fields (isMuted,
    // unreadCount). Freshly-added members have no prior membership state, so send
    // a neutral copy with isMuted: false and unreadCount: 0.
    const addedMemberSummary = { ...result, isMuted: false, unreadCount: 0 };
    for (const userId of addUserIds) {
      this.realtime.publishUserEvent(
        userId,
        "chat.created",
        addedMemberSummary,
      );
    }
    for (const userId of removeUserIds) {
      this.realtime.publishUserEvent(userId, "chat.removed", { id: chatId });
    }
    return result;
  }

  async leaveGroup(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "group") {
      throw new NotFoundException("Группа не найдена.");
    }
    if (chat.isSystem) {
      throw new ForbiddenException(
        "Нельзя выйти из системного чата «Объявления».",
      );
    }
    if (chat.memberUserId !== actor.userId) {
      throw new NotFoundException("Группа не найдена.");
    }
    await this.database.query(
      `
        update app.chat_members
        set left_at = now()
        where chat_id = $1 and user_id = $2 and left_at is null
      `,
      [chatId, actor.userId],
    );
    this.realtime.publishUserEvent(actor.userId, "chat.removed", {
      id: chatId,
    });
    this.realtime.publishChatEvent(chatId, "chat.updated", { id: chatId });
    return { success: true };
  }

  async getChat(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
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

  async setChatMute(actor: ActorContext, chatId: string, dto: SetChatMuteDto) {
    const chat = await this.requireChat(actor, chatId);
    this.policy.assertCanReadChat(actor, chat);
    await this.database.query(
      `
        update app.chat_members
        set muted_until = case when $3::boolean then 'infinity'::timestamptz else null end
        where chat_id = $1 and user_id = $2 and left_at is null
      `,
      [chatId, actor.userId, dto.isMuted],
    );
    await this.audit.record({
      actor,
      action: dto.isMuted ? "messenger.chat_muted" : "messenger.chat_unmuted",
      entityType: "chat",
      entityId: chatId,
    });
    this.realtime.publishChatEvent(chatId, "chat.updated", {
      id: chatId,
      userId: actor.userId,
      isMuted: dto.isMuted,
    });
    return { success: true, isMuted: dto.isMuted };
  }

  private async createAdministrationChat(actor: ActorContext) {
    const chat = await this.database.transaction(async (client) => {
      const existing = await client.query<ChatRow>(
        `
          select c.id, c.type, c.title, c.created_by, c.last_message_id,
            null::text as last_message_content, null::timestamptz as last_message_created_at,
            '0'::text as unread_count, c.created_at, c.updated_at
          from app.chats c
          join app.chat_members cm on cm.chat_id = c.id and cm.user_id = $1 and cm.left_at is null
          where c.type = 'administration' and c.deleted_at is null
          limit 1
        `,
        [actor.userId],
      );
      if (existing.rows[0]) return existing.rows[0];

      const inserted = await client.query<ChatRow>(
        `
          insert into app.chats (type, title, created_by, owner_user_id)
          values ('administration', 'Администрация', $1, $1)
          returning id, type, title, created_by, last_message_id,
            null::text as last_message_content, null::timestamptz as last_message_created_at,
            '0'::text as unread_count, created_at, updated_at
        `,
        [actor.userId],
      );
      const row = inserted.rows[0];
      await this.insertMembers(client, row.id, [
        { userId: actor.userId, role: "member" },
      ]);
      return row;
    });
    return toChatSummaryDto(chat);
  }

  private async requireChat(actor: ActorContext, chatId: string) {
    const chat = await this.policy.getChatAccess(actor, chatId);
    if (!chat) throw new NotFoundException("Чат не найден.");
    return chat;
  }

  private async insertMembers(
    client: PoolClient,
    chatId: string,
    members: Array<{ userId: string; role: string }>,
  ) {
    for (const member of members) {
      await client.query(
        `
          insert into app.chat_members (chat_id, user_id, role, left_at)
          values ($1, $2, $3, null)
          on conflict (chat_id, user_id)
          do update set role = excluded.role, left_at = null
        `,
        [chatId, member.userId, member.role],
      );
    }
  }

  private async assertActiveUsers(userIds: string[]): Promise<void> {
    const uniqueUserIds = Array.from(new Set(userIds));
    if (!uniqueUserIds.length) return;

    const result = await this.database.query<{ id: string }>(
      `
        select id
        from app.users
        where id = any($1::uuid[])
          and deleted_at is null
      `,
      [uniqueUserIds],
    );
    if (result.rows.length !== uniqueUserIds.length) {
      throw new NotFoundException("Пользователь не найден.");
    }
  }

  private async assertValidChatAttachment(
    actorUserId: string,
    chatId: string,
    attachmentFileId: string,
  ): Promise<ChatAttachmentRow> {
    const result = await this.database.query<ChatAttachmentRow>(
      `
        select id, purpose, mime_type
        from app.file_objects
        where id = $1
          and owner_type = 'chat'
          and owner_id = $2
          and owner_user_id = $3
          and purpose in ('chat_attachment', 'chat_voice')
          and deleted_at is null
        limit 1
      `,
      [attachmentFileId, chatId, actorUserId],
    );
    const attachment = result.rows[0];
    if (!attachment) {
      throw new NotFoundException("Файл не найден.");
    }
    return attachment;
  }

  private assertMessagePayload(
    messageType: string,
    attachment: ChatAttachmentRow | null,
    voiceDurationMs?: number,
  ): void {
    if (messageType === "text") {
      if (attachment || voiceDurationMs != null) {
        throw new BadRequestException(
          "Текстовое сообщение не может содержать медиа-вложение.",
        );
      }
      return;
    }

    if (!attachment) {
      throw new BadRequestException("Для медиа-сообщения требуется файл.");
    }
    if (messageType === "voice") {
      if (
        attachment.purpose !== "chat_voice" ||
        !attachment.mime_type.toLowerCase().startsWith("audio/")
      ) {
        throw new BadRequestException(
          "Для голосового сообщения требуется аудиозапись.",
        );
      }
      if (
        voiceDurationMs == null ||
        !Number.isInteger(voiceDurationMs) ||
        voiceDurationMs < 1 ||
        voiceDurationMs > 3_600_000
      ) {
        throw new BadRequestException(
          "Для голосового сообщения требуется корректная длительность.",
        );
      }
      return;
    }

    if (voiceDurationMs != null || attachment.purpose !== "chat_attachment") {
      throw new BadRequestException("Тип сообщения не соответствует вложению.");
    }
    if (
      messageType === "image" &&
      !attachment.mime_type.toLowerCase().startsWith("image/")
    ) {
      throw new BadRequestException(
        "Для изображения требуется файл изображения.",
      );
    }
  }

  private async assertValidMessageReferences(
    actor: ActorContext,
    chatId: string,
    replyToId?: string,
    forwardedFromId?: string,
  ): Promise<void> {
    if (replyToId) {
      const reply = await this.database.query<{ id: string }>(
        `
          select id
          from app.messages
          where id = $1 and chat_id = $2 and deleted_at is null
          limit 1
        `,
        [replyToId, chatId],
      );
      if (!reply.rows[0]) {
        throw new NotFoundException(
          "Исходное сообщение для ответа не найдено.",
        );
      }
    }

    if (forwardedFromId) {
      const source = await this.database.query<{ chat_id: string }>(
        `
          select chat_id
          from app.messages
          where id = $1 and deleted_at is null
          limit 1
        `,
        [forwardedFromId],
      );
      const sourceChatId = source.rows[0]?.chat_id;
      if (!sourceChatId) {
        throw new NotFoundException(
          "Исходное сообщение для пересылки не найдено.",
        );
      }
      const sourceChat = await this.requireChat(actor, sourceChatId);
      this.policy.assertCanReadChat(actor, sourceChat);
    }
  }
}
