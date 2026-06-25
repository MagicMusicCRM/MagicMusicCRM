import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
  isManagerRole,
  isStaffRole,
} from "../common/security/actor-context";
import { CrmService } from "../crm/crm.service";
import { DatabaseService } from "../db/database.service";
import { ChannelPermissionDto, UpsertChannelDto } from "./dto/channel.dto";
import { CreateChannelPostDto } from "./dto/create-channel-post.dto";
import { CreateDirectChatDto } from "./dto/create-direct-chat.dto";
import { CreateGroupChatDto } from "./dto/create-group-chat.dto";
import { DeleteMessageDto } from "./dto/delete-message.dto";
import { MarkReadDto } from "./dto/mark-read.dto";
import { MessengerListQuery } from "./dto/messenger-list.query";
import { SetChatMuteDto } from "./dto/set-chat-mute.dto";
import { SendMessageDto } from "./dto/send-message.dto";
import { UpdateGroupMembersDto } from "./dto/update-group-members.dto";
import { UpdateMessageDto } from "./dto/update-message.dto";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

interface ChatRow {
  id: string;
  type: string;
  title: string | null;
  created_by: string | null;
  last_message_id: string | null;
  last_message_content: string | null;
  last_message_created_at: Date | string | null;
  unread_count: string | null;
  is_muted: boolean | null;
  partner_user_id?: string | null;
  partner_email?: string | null;
  partner_first_name?: string | null;
  partner_last_name?: string | null;
  partner_avatar_file_id?: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  // Staff inbox fields (administration chats only)
  owner_first_name?: string | null;
  owner_last_name?: string | null;
  assigned_to_user_id?: string | null;
  assigned_first_name?: string | null;
  assigned_last_name?: string | null;
  folder?: string | null;
  archived_at?: Date | string | null;
}

interface MessageRow {
  id: string;
  chat_id: string;
  sender_id: string | null;
  content: string | null;
  message_type: string;
  attachment_file_id: string | null;
  reply_to_id: string | null;
  forwarded_from_id: string | null;
  pinned_by: string | null;
  pinned_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
  deleted_at: Date | string | null;
  sender_email: string | null;
  sender_first_name: string | null;
  sender_last_name: string | null;
  sender_role?: string | null;
  attachment_original_name?: string | null;
  attachment_mime_type?: string | null;
  attachment_size_bytes?: string | number | null;
  is_read: boolean | null;
}

interface ChatMemberRow {
  profile_id: string | null;
  user_id: string;
  email: string | null;
  role: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  avatar_file_id: string | null;
  joined_at: Date | string;
}

interface ChannelRow {
  id: string;
  title: string;
  description: string | null;
  created_by: string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

interface ChannelPostRow {
  id: string;
  channel_id: string;
  author_id: string | null;
  content: string;
  attachment_file_id: string | null;
  published_at: Date | string;
  updated_at: Date | string;
}

interface ChannelPermissionRow {
  id: string;
  user_id: string | null;
  role: string | null;
  can_read: boolean;
  can_write: boolean;
  user_email: string | null;
  user_first_name: string | null;
  user_last_name: string | null;
}

interface ReactionRow {
  emoji: string;
  count: string;
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
    private readonly crm: CrmService,
  ) {}

  async onModuleInit(): Promise<void> {
    // Self-heal the durable default channels on boot. Idempotent and best-effort
    // (migration 0042 already seeds them; this covers fresh/partial databases).
    try {
      await this.ensureDefaultChannels();
    } catch (err) {
      this.logger.warn(`ensureDefaultChannels failed: ${String(err)}`);
    }
  }

  /**
   * Idempotently ensure the default system "Объявления" channel exists with the
   * correct role permissions (read: all roles; write: admin/manager/system_admin).
   * Safe to call repeatedly — never creates a duplicate channel.
   */
  async ensureDefaultChannels(): Promise<void> {
    await this.database.transaction(async (client) => {
      // Adopt a pre-existing "Объявления" channel (created before the system-slug
      // contract) instead of creating a duplicate.
      await client.query(
        `
          update app.channels
          set slug = $1, is_system = true, updated_at = now()
          where id = (
            select id from app.channels
            where title = 'Объявления' and slug is null and deleted_at is null
            order by created_at asc
            limit 1
          )
          and not exists (
            select 1 from app.channels where slug = $1 and deleted_at is null
          )
        `,
        [MessengerService.announcementsSlug],
      );

      const existing = await client.query<{ id: string }>(
        `select id from app.channels where slug = $1 and deleted_at is null limit 1`,
        [MessengerService.announcementsSlug],
      );
      let channelId = existing.rows[0]?.id;
      if (!channelId) {
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.channels (title, description, slug, is_system)
            values ('Объявления', 'Школьные объявления', $1, true)
            returning id
          `,
          [MessengerService.announcementsSlug],
        );
        channelId = inserted.rows[0].id;
      }

      const permissions: Array<{
        role: string;
        canRead: boolean;
        canWrite: boolean;
      }> = [
        { role: "client", canRead: true, canWrite: false },
        { role: "teacher", canRead: true, canWrite: false },
        { role: "admin", canRead: true, canWrite: true },
        { role: "manager", canRead: true, canWrite: true },
        { role: "system_admin", canRead: true, canWrite: true },
      ];
      for (const permission of permissions) {
        await client.query(
          `
            insert into app.channel_permissions (channel_id, role, can_read, can_write)
            select $1, $2::app.user_role, $3, $4
            where not exists (
              select 1 from app.channel_permissions cp
              where cp.channel_id = $1 and cp.user_id is null
                and cp.role = $2::app.user_role
            )
          `,
          [channelId, permission.role, permission.canRead, permission.canWrite],
        );
      }
    });
  }

  async listChats(actor: ActorContext, query: MessengerListQuery) {
    const limit = Math.min(query.limit ?? 50, 100);
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
          (me_state.muted_until is not null and me_state.muted_until > now()) as is_muted,
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
          case
            when ist.archived_at is not null then 'archive'
            when exists (
              select 1 from app.students s
              join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
              where s.deleted_at is null
                and (
                  case
                    when length(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g')) = 11
                      and left(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
                      then '+7' || right(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g'), 10)
                    when length(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g')) = 10
                      and left(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
                      then '+7' || regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g')
                    else null
                  end
                ) is not null
                and (
                  case
                    when length(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g')) = 11
                      and left(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
                      then '+7' || right(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g'), 10)
                    when length(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g')) = 10
                      and left(regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
                      then '+7' || regexp_replace(coalesce(sp.phone, ''), '[^0-9]', '', 'g')
                    else null
                  end
                ) = (
                  case
                    when length(regexp_replace(coalesce(owp.phone, ''), '[^0-9]', '', 'g')) = 11
                      and left(regexp_replace(coalesce(owp.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
                      then '+7' || right(regexp_replace(coalesce(owp.phone, ''), '[^0-9]', '', 'g'), 10)
                    when length(regexp_replace(coalesce(owp.phone, ''), '[^0-9]', '', 'g')) = 10
                      and left(regexp_replace(coalesce(owp.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
                      then '+7' || regexp_replace(coalesce(owp.phone, ''), '[^0-9]', '', 'g')
                    else null
                  end
                )
            ) then 'students'
            else 'leads'
          end as folder
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
        where c.deleted_at is null
          and ($3::timestamptz is null or c.updated_at < $3)
          and (
            cm.user_id = $2
            or ($1::text in ('manager', 'admin', 'system_admin') and c.type = 'administration')
          )
        order by c.updated_at desc, c.id desc
        limit $4
      `,
      [actor.role, actor.userId, query.before ?? null, limit],
    );

    return { items: result.rows.map((row) => this.toChatSummaryDto(row)) };
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
          m.attachment_file_id, m.reply_to_id, m.forwarded_from_id,
          m.pinned_by, m.pinned_at, m.created_at, m.updated_at,
          m.deleted_at, u.email as sender_email, p.first_name as sender_first_name,
          p.last_name as sender_last_name,
          u.role as sender_role,
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
          end as is_read
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
          this.toMessageDto(row, {
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
        select p.id as profile_id, cm.user_id, u.email, cm.role, p.first_name, p.last_name,
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
      items: result.rows.map((row) => this.toChatMemberDto(row, actor.userId)),
    };
  }

  async sendMessage(actor: ActorContext, chatId: string, dto: SendMessageDto) {
    const chat = await this.requireChat(actor, chatId);
    this.policy.assertCanWriteChat(actor, chat);
    const content = dto.content?.trim() || null;
    if (!content && !dto.attachmentFileId) {
      throw new BadRequestException("Сообщение не может быть пустым.");
    }
    if (dto.attachmentFileId) {
      await this.assertValidChatAttachment(chatId, dto.attachmentFileId);
    }

    const message = await this.database.transaction(async (client) => {
      const inserted = await client.query<MessageRow>(
        `
          insert into app.messages (
            chat_id, sender_id, content, message_type, attachment_file_id,
            reply_to_id, forwarded_from_id
          )
          values ($1, $2, $3, coalesce($4, 'text'), $5, $6, $7)
          returning id, chat_id, sender_id, content, message_type,
            attachment_file_id, reply_to_id, forwarded_from_id,
            pinned_by, pinned_at, created_at, updated_at, deleted_at,
            null::text as sender_email, null::text as sender_first_name,
            null::text as sender_last_name,
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
          dto.messageType ?? null,
          dto.attachmentFileId ?? null,
          dto.replyToId ?? null,
          dto.forwardedFromId ?? null,
        ],
      );
      const row = inserted.rows[0];
      await client.query(
        "update app.chats set last_message_id = $2, updated_at = now() where id = $1",
        [chatId, row.id],
      );
      return row;
    });

    const payload = this.toMessageDto(message);
    // Privacy: in an administration chat the client (a member of the chat room)
    // must never receive staff identity on the wire. When the author is staff,
    // publish the MASKED DTO to the chat room. Non-staff (the client) is
    // published unmasked so staff see the real client identity in realtime.
    const roomPayload =
      chat.type === "administration" && isStaffRole(actor.role)
        ? this.toMessageDto(message, { maskStaffSender: true })
        : payload;
    this.realtime.publishChatEvent(chatId, "message.created", roomPayload);
    await this.fanoutChatListUpdate(chat, chatId, payload, {
      maskStaffSenderForMembers:
        chat.type === "administration" && isStaffRole(actor.role),
    });
    if (chat.type === "administration") {
      // Resurface: clear archived_at for ALL staff so the thread reappears in inboxes.
      // Best-effort: a failure here must not break the send.
      try {
        await this.database.query(
          "update app.chat_inbox_state set archived_at = null where chat_id = $1",
          [chatId],
        );
      } catch (err) {
        this.logger.warn(`resurface chat_inbox_state failed: ${String(err)}`);
      }
    }
    if (chat.type === "administration" && !isStaffRole(actor.role)) {
      void this.crm.autoCreateLeadFromChat(actor, actor.userId).catch(() => undefined);
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
        [actor.userId],
      );
      const row = inserted.rows[0];
      await this.insertMembers(client, row.id, [
        { userId: actor.userId, role: "member" },
        { userId: dto.targetUserId!, role: "member" },
      ]);
      return row;
    });

    return this.toChatSummaryDto(chat);
  }

  async createGroup(actor: ActorContext, dto: CreateGroupChatDto) {
    this.policy.assertCanCreateGroup(actor);
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
        [dto.name.trim(), actor.userId],
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

    const summary = this.toChatSummaryDto(chat);
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
    await this.assertActiveUsers(dto.addUserIds ?? []);

    await this.database.transaction(async (client) => {
      if (dto.addUserIds?.length) {
        await this.insertMembers(
          client,
          chatId,
          dto.addUserIds.map((userId) => ({ userId, role: "member" })),
        );
      }
      if (dto.removeUserIds?.length) {
        await client.query(
          `
            update app.chat_members
            set left_at = now()
            where chat_id = $1 and user_id = any($2::uuid[])
          `,
          [chatId, dto.removeUserIds],
        );
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
    for (const userId of dto.addUserIds ?? []) {
      this.realtime.publishUserEvent(userId, "chat.created", addedMemberSummary);
    }
    for (const userId of dto.removeUserIds ?? []) {
      this.realtime.publishUserEvent(userId, "chat.removed", { id: chatId });
    }
    return result;
  }

  async leaveGroup(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "group") {
      throw new NotFoundException("Группа не найдена.");
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
    this.realtime.publishUserEvent(actor.userId, "chat.removed", { id: chatId });
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
          c.created_at, c.updated_at
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
    return this.toChatSummaryDto(result.rows[0]);
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

  async markRead(actor: ActorContext, chatId: string, dto: MarkReadDto) {
    const chat = await this.requireChat(actor, chatId);
    this.policy.assertCanReadChat(actor, chat);
    const lastReadMessageId = await this.resolveLastReadMessageId(
      chatId,
      dto.lastReadMessageId,
    );
    const updated = await this.database.query(
      `
        update app.chat_members
        set last_read_message_id = $3
        where chat_id = $1 and user_id = $2 and left_at is null
      `,
      [chatId, actor.userId, lastReadMessageId],
    );
    if (updated.rowCount === 0 && chat.type === "administration") {
      await this.database.query(
        `
          insert into app.chat_members (chat_id, user_id, last_read_message_id)
          values ($1, $2, $3)
          on conflict (chat_id, user_id)
          do update set last_read_message_id = excluded.last_read_message_id
          where app.chat_members.left_at is null
        `,
        [chatId, actor.userId, lastReadMessageId],
      );
    }
    this.realtime.publishChatEvent(chatId, "chat.updated", {
      id: chatId,
      readerId: actor.userId,
      lastReadMessageId,
    });
    const readUpdates = await this.listReadReceiptUpdates(
      chatId,
      actor.userId,
      lastReadMessageId,
    );
    for (const message of readUpdates) {
      // Privacy: in an administration chat the client must never receive a
      // staff author's real identity. Mask when the message author is staff.
      this.realtime.publishChatEvent(
        chatId,
        "message.updated",
        this.toMessageDto(message, {
          maskStaffSender:
            chat.type === "administration" &&
            isStaffRole((message.sender_role ?? "") as never),
        }),
      );
    }
    return { success: true };
  }

  async archiveChat(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут архивировать чаты.");
    }
    await this.database.query(
      `insert into app.chat_inbox_state (chat_id, staff_user_id, archived_at)
       values ($1, $2, now())
       on conflict (chat_id, staff_user_id) do update set archived_at = now()`,
      [chatId, actor.userId],
    );
    this.realtime.publishUserEvent(actor.userId, "chat.updated", {
      id: chatId,
      archived: true,
    });
    return { success: true };
  }

  async unarchiveChat(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут разархивировать чаты.");
    }
    await this.database.query(
      `insert into app.chat_inbox_state (chat_id, staff_user_id, archived_at)
       values ($1, $2, null)
       on conflict (chat_id, staff_user_id) do update set archived_at = null`,
      [chatId, actor.userId],
    );
    this.realtime.publishUserEvent(actor.userId, "chat.updated", {
      id: chatId,
      archived: false,
    });
    return { success: true };
  }

  async assignChat(actor: ActorContext, chatId: string, userId?: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут брать чаты в работу.");
    }

    const targetUserId = userId ?? actor.userId;

    // Verify the target is a staff user
    const targetResult = await this.database.query<{ role: string }>(
      "select role from app.users where id = $1 and deleted_at is null limit 1",
      [targetUserId],
    );
    const targetRow = targetResult.rows[0];
    if (!targetRow) {
      throw new NotFoundException("Пользователь не найден.");
    }
    if (!isStaffRole(targetRow.role as never)) {
      throw new ForbiddenException("Чат можно назначить только сотруднику.");
    }

    this.policy.assertCanAssign(actor, chat);

    await this.database.query(
      "update app.chats set assigned_to_user_id = $2, assigned_at = now() where id = $1",
      [chatId, targetUserId],
    );

    this.realtime.publishAdminInboxEvent("chat.updated", {
      id: chatId,
      assignedTo: { id: targetUserId },
    });

    return { success: true };
  }

  async unassignChat(actor: ActorContext, chatId: string) {
    const chat = await this.requireChat(actor, chatId);
    if (chat.type !== "administration") {
      throw new NotFoundException("Чат не найден.");
    }
    if (!isStaffRole(actor.role)) {
      throw new ForbiddenException("Только сотрудники могут снимать назначение.");
    }

    // Allowed for the current assignee or manager-tier
    const current = chat.assignedToUserId ?? null;
    if (!isManagerRole(actor.role) && current !== actor.userId) {
      throw new ForbiddenException("Недостаточно прав для снятия назначения.");
    }

    await this.database.query(
      "update app.chats set assigned_to_user_id = null, assigned_at = null where id = $1",
      [chatId],
    );

    this.realtime.publishAdminInboxEvent("chat.updated", {
      id: chatId,
      assignedTo: null,
    });

    return { success: true };
  }

  async setReaction(actor: ActorContext, messageId: string, emoji: string) {
    const message = await this.requireMessage(actor, messageId);
    await this.database.query(
      `
        insert into app.message_reactions (message_id, user_id, emoji)
        values ($1, $2, $3)
        on conflict (message_id, user_id, emoji) do nothing
      `,
      [messageId, actor.userId, emoji],
    );
    const reactions = await this.listReactions(messageId);
    this.realtime.publishChatEvent(message.chat_id, "message.updated", {
      id: messageId,
      reactions,
    });
    return { messageId, reactions };
  }

  async removeReaction(actor: ActorContext, messageId: string, emoji: string) {
    const message = await this.requireMessage(actor, messageId);
    await this.database.query(
      "delete from app.message_reactions where message_id = $1 and user_id = $2 and emoji = $3",
      [messageId, actor.userId, emoji],
    );
    const reactions = await this.listReactions(messageId);
    this.realtime.publishChatEvent(message.chat_id, "message.updated", {
      id: messageId,
      reactions,
    });
    return { messageId, reactions };
  }

  async pinMessage(actor: ActorContext, messageId: string) {
    const message = await this.requireMessage(actor, messageId);
    const chat = await this.requireChat(actor, message.chat_id);
    this.policy.assertCanManageGroup(actor, chat);
    const result = await this.database.query<MessageRow>(
      `
        update app.messages
        set pinned_by = $2, pinned_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id, chat_id, sender_id, content, message_type,
          attachment_file_id, reply_to_id, forwarded_from_id,
          pinned_by, pinned_at, created_at, updated_at, deleted_at,
          null::text as sender_email, null::text as sender_first_name,
          null::text as sender_last_name,
          (select role from app.users where id = app.messages.sender_id) as sender_role,
          false as is_read
      `,
      [messageId, actor.userId],
    );
    const row = result.rows[0];
    const payload = this.toMessageDto(row, {
      maskStaffSender:
        chat.type === "administration" &&
        isStaffRole((row?.sender_role ?? "") as never),
    });
    this.realtime.publishChatEvent(message.chat_id, "message.updated", payload);
    return payload;
  }

  async unpinMessage(actor: ActorContext, messageId: string) {
    const message = await this.requireMessage(actor, messageId);
    const chat = await this.requireChat(actor, message.chat_id);
    this.policy.assertCanManageGroup(actor, chat);
    const result = await this.database.query<MessageRow>(
      `
        update app.messages
        set pinned_by = null, pinned_at = null, updated_at = now()
        where id = $1 and deleted_at is null
        returning id, chat_id, sender_id, content, message_type,
          attachment_file_id, reply_to_id, forwarded_from_id,
          pinned_by, pinned_at, created_at, updated_at, deleted_at,
          null::text as sender_email, null::text as sender_first_name,
          null::text as sender_last_name,
          (select role from app.users where id = app.messages.sender_id) as sender_role,
          false as is_read
      `,
      [messageId],
    );
    const row = result.rows[0];
    const payload = this.toMessageDto(row, {
      maskStaffSender:
        chat.type === "administration" &&
        isStaffRole((row?.sender_role ?? "") as never),
    });
    this.realtime.publishChatEvent(message.chat_id, "message.updated", payload);
    return payload;
  }

  async deleteMessage(
    actor: ActorContext,
    messageId: string,
    dto: DeleteMessageDto,
  ) {
    const message = await this.requireMessage(actor, messageId);
    const chat = await this.requireChat(actor, message.chat_id);
    this.policy.assertCanModerateMessage(actor, message.sender_id);
    const mode =
      actor.userId === message.sender_id ? "own" : (dto.mode ?? "moderated");
    const result = await this.database.query<MessageRow>(
      `
        update app.messages
        set content = null, attachment_file_id = null, deleted_at = now(),
          delete_mode = $2, updated_at = now()
        where id = $1
        returning id, chat_id, sender_id, content, message_type,
          attachment_file_id, reply_to_id, forwarded_from_id,
          pinned_by, pinned_at, created_at, updated_at, deleted_at,
          null::text as sender_email, null::text as sender_first_name,
          null::text as sender_last_name,
          (select role from app.users where id = app.messages.sender_id) as sender_role,
          false as is_read
      `,
      [messageId, mode],
    );
    const row = result.rows[0];
    const payload = this.toMessageDto(row, {
      maskStaffSender:
        chat.type === "administration" &&
        isStaffRole((row?.sender_role ?? "") as never),
    });
    await this.audit.record({
      actor,
      action: "messenger.message_deleted",
      entityType: "message",
      entityId: messageId,
      metadata: { mode },
    });
    this.realtime.publishChatEvent(message.chat_id, "message.updated", payload);
    return payload;
  }

  async updateMessage(
    actor: ActorContext,
    messageId: string,
    dto: UpdateMessageDto,
  ) {
    const message = await this.requireMessage(actor, messageId);
    const chat = await this.requireChat(actor, message.chat_id);
    if (message.sender_id !== actor.userId) {
      throw new ForbiddenException(
        "Можно редактировать только свои сообщения.",
      );
    }
    if (message.deleted_at) {
      throw new BadRequestException(
        "Удаленное сообщение нельзя редактировать.",
      );
    }
    if (message.message_type !== "text" || message.attachment_file_id) {
      throw new BadRequestException(
        "Можно редактировать только текстовые сообщения.",
      );
    }

    const content = dto.content.trim();
    if (!content) {
      throw new BadRequestException("Сообщение не может быть пустым.");
    }

    const result = await this.database.query<MessageRow>(
      `
        update app.messages
        set content = $2, updated_at = now()
        where id = $1 and deleted_at is null
        returning id, chat_id, sender_id, content, message_type,
          attachment_file_id, reply_to_id, forwarded_from_id,
          pinned_by, pinned_at, created_at, updated_at, deleted_at,
          null::text as sender_email, null::text as sender_first_name,
          null::text as sender_last_name,
          (select role from app.users where id = app.messages.sender_id) as sender_role,
          false as is_read
      `,
      [messageId, content],
    );
    const row = result.rows[0];
    const payload = this.toMessageDto(row, {
      maskStaffSender:
        chat.type === "administration" &&
        isStaffRole((row?.sender_role ?? "") as never),
    });
    await this.audit.record({
      actor,
      action: "messenger.message_updated",
      entityType: "message",
      entityId: messageId,
    });
    this.realtime.publishChatEvent(message.chat_id, "message.updated", payload);
    return payload;
  }

  async listChannels(actor: ActorContext) {
    const result = await this.database.query<ChannelRow>(
      `
        select distinct c.id, c.title, c.description, c.created_by,
          c.created_at, c.updated_at
        from app.channels c
        left join app.channel_permissions cp on cp.channel_id = c.id
        where c.deleted_at is null
          and (
            $1::text in ('manager', 'admin', 'system_admin')
            or (cp.can_read = true and (cp.user_id = $2 or cp.role = $1::app.user_role))
          )
        order by c.created_at desc, c.id desc
      `,
      [actor.role, actor.userId],
    );
    return { items: result.rows.map((row) => this.toChannelDto(row)) };
  }

  async createChannel(actor: ActorContext, dto: UpsertChannelDto) {
    if (!isManagerOrAdminRole(actor.role)) {
      throw new NotFoundException("Канал не найден.");
    }
    const channel = await this.database.transaction(async (client) => {
      const inserted = await client.query<ChannelRow>(
        `
          insert into app.channels (title, description, created_by)
          values ($1, $2, $3)
          returning id, title, description, created_by, created_at, updated_at
        `,
        [dto.title.trim(), dto.description?.trim() || null, actor.userId],
      );
      const row = inserted.rows[0];
      await this.replaceChannelPermissions(
        client,
        row.id,
        dto.permissions ?? [],
      );
      return row;
    });
    await this.audit.record({
      actor,
      action: "messenger.channel_created",
      entityType: "channel",
      entityId: channel.id,
    });
    return this.toChannelDto(channel);
  }

  async updateChannel(
    actor: ActorContext,
    channelId: string,
    dto: UpsertChannelDto,
  ) {
    const access = await this.policy.getChannelAccess(actor, channelId);
    if (!access) throw new NotFoundException("Канал не найден.");
    this.policy.assertCanWriteChannel(actor, access);

    const channel = await this.database.transaction(async (client) => {
      const result = await client.query<ChannelRow>(
        `
          update app.channels
          set title = $2, description = $3, updated_at = now()
          where id = $1 and deleted_at is null
          returning id, title, description, created_by, created_at, updated_at
        `,
        [channelId, dto.title.trim(), dto.description?.trim() || null],
      );
      await this.replaceChannelPermissions(
        client,
        channelId,
        dto.permissions ?? [],
      );
      return result.rows[0];
    });

    await this.audit.record({
      actor,
      action: "messenger.channel_updated",
      entityType: "channel",
      entityId: channelId,
    });
    return this.toChannelDto(channel);
  }

  async getChannelAccess(actor: ActorContext, channelId: string) {
    const access = await this.policy.getChannelAccess(actor, channelId);
    if (!access) throw new NotFoundException("Канал не найден.");
    this.policy.assertCanReadChannel(access);
    return {
      channelId,
      canRead: access.canRead,
      canWrite: access.canWrite,
    };
  }

  async listChannelPermissions(actor: ActorContext, channelId: string) {
    const access = await this.policy.getChannelAccess(actor, channelId);
    if (!access) throw new NotFoundException("Канал не найден.");
    this.policy.assertCanWriteChannel(actor, access);

    const result = await this.database.query<ChannelPermissionRow>(
      `
        select cp.id, cp.user_id, cp.role, cp.can_read, cp.can_write,
          u.email as user_email, p.first_name as user_first_name,
          p.last_name as user_last_name
        from app.channel_permissions cp
        left join app.users u on u.id = cp.user_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where cp.channel_id = $1
        order by
          cp.role nulls last,
          p.last_name nulls last,
          p.first_name nulls last,
          u.email nulls last,
          cp.id
      `,
      [channelId],
    );

    return {
      items: result.rows.map((row) => this.toChannelPermissionDto(row)),
    };
  }

  async listChannelPosts(
    actor: ActorContext,
    channelId: string,
    query: MessengerListQuery,
  ) {
    const access = await this.policy.getChannelAccess(actor, channelId);
    if (!access) throw new NotFoundException("Канал не найден.");
    this.policy.assertCanReadChannel(access);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<ChannelPostRow>(
      `
        select id, channel_id, author_id, content, attachment_file_id,
          published_at, updated_at
        from app.channel_posts
        where channel_id = $1
          and deleted_at is null
          and ($2::timestamptz is null or published_at < $2)
        order by published_at desc, id desc
        limit $3
      `,
      [channelId, query.before ?? null, limit],
    );
    return {
      items: result.rows.map((row) => this.toChannelPostDto(row)).reverse(),
    };
  }

  async createChannelPost(
    actor: ActorContext,
    channelId: string,
    dto: CreateChannelPostDto,
  ) {
    const access = await this.policy.getChannelAccess(actor, channelId);
    if (!access) throw new NotFoundException("Канал не найден.");
    this.policy.assertCanWriteChannel(actor, access);
    const result = await this.database.query<ChannelPostRow>(
      `
        insert into app.channel_posts (channel_id, author_id, content, attachment_file_id)
        values ($1, $2, $3, $4)
        returning id, channel_id, author_id, content, attachment_file_id,
          published_at, updated_at
      `,
      [
        channelId,
        actor.userId,
        dto.content.trim(),
        dto.attachmentFileId ?? null,
      ],
    );
    const post = this.toChannelPostDto(result.rows[0]);
    await this.audit.record({
      actor,
      action: "messenger.channel_post_created",
      entityType: "channel",
      entityId: channelId,
      metadata: { postId: post.id },
    });
    this.realtime.publishChannelEvent(channelId, "channel.post_created", post);
    return post;
  }

  /**
   * After a chat message is written, push a lightweight `chat.updated` hint to
   * every member's user room (so chat lists/badges refresh even when the member
   * is not inside the chat room) and, for administration chats, to the staff
   * `admin-inbox` surface so brand-new user→staff conversations appear live.
   * Best-effort: realtime failures never break the underlying write.
   */
  private async fanoutChatListUpdate(
    chat: { type: string },
    chatId: string,
    message: {
      id: string;
      content: string | null;
      createdAt: Date | string;
      senderId: string | null;
    },
    opts?: { maskStaffSenderForMembers?: boolean },
  ): Promise<void> {
    try {
      // Carry a lightweight last-message preview so recipients can patch their
      // chat list in place (bump order + last message + unread) without a full
      // refetch. Brand-new conversations (chat not yet in the list) still trigger
      // a scoped reload on the client.
      const preview = {
        id: chatId,
        lastMessageId: message.id,
        lastMessage: message.content,
        lastMessageAt: message.createdAt,
        senderId: message.senderId,
      };
      // Privacy: administration-chat members are non-staff (the owner client).
      // For a staff-authored message, withhold the staff senderId from their
      // user-room preview so identity never reaches the client off the wire.
      // The admin-inbox preview (staff-only surface) keeps the real senderId.
      const memberPreview = opts?.maskStaffSenderForMembers
        ? { ...preview, senderId: null }
        : preview;
      const memberIds = await this.getChatMemberUserIds(chatId);
      for (const userId of memberIds) {
        this.realtime.publishUserEvent(userId, "chat.updated", memberPreview);
      }
      if (chat.type === "administration") {
        this.realtime.publishAdminInboxEvent("chat.updated", preview);
      }
    } catch (err) {
      this.logger.warn(`fanoutChatListUpdate failed: ${String(err)}`);
    }
  }

  private async getChatMemberUserIds(chatId: string): Promise<string[]> {
    const result = await this.database.query<{ user_id: string }>(
      `select user_id from app.chat_members where chat_id = $1 and left_at is null`,
      [chatId],
    );
    return (result?.rows ?? []).map((row) => row.user_id);
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
    return this.toChatSummaryDto(chat);
  }

  private async requireChat(actor: ActorContext, chatId: string) {
    const chat = await this.policy.getChatAccess(actor, chatId);
    if (!chat) throw new NotFoundException("Чат не найден.");
    return chat;
  }

  private async requireMessage(
    actor: ActorContext,
    messageId: string,
  ): Promise<MessageRow> {
    const result = await this.database.query<MessageRow>(
      `
        select m.id, m.chat_id, m.sender_id, m.content, m.message_type,
          m.attachment_file_id, m.reply_to_id, m.forwarded_from_id,
          m.pinned_by, m.pinned_at, m.created_at, m.updated_at, m.deleted_at,
          null::text as sender_email, null::text as sender_first_name,
          null::text as sender_last_name, false as is_read
        from app.messages m
        where m.id = $1
        limit 1
      `,
      [messageId],
    );
    const message = result.rows[0];
    if (!message) throw new NotFoundException("Сообщение не найдено.");
    const chat = await this.requireChat(actor, message.chat_id);
    this.policy.assertCanReadChat(actor, chat);
    return message;
  }

  private async listReactions(messageId: string) {
    const result = await this.database.query<ReactionRow>(
      `
        select emoji, count(*)::text as count
        from app.message_reactions
        where message_id = $1
        group by emoji
        order by emoji
      `,
      [messageId],
    );
    return result.rows.map((row) => ({
      emoji: row.emoji,
      count: Number(row.count),
    }));
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

  private async resolveLastReadMessageId(
    chatId: string,
    requestedMessageId?: string,
  ): Promise<string | null> {
    if (requestedMessageId) {
      const result = await this.database.query<{ id: string }>(
        `
          select id
          from app.messages
          where id = $1
            and chat_id = $2
            and deleted_at is null
          limit 1
        `,
        [requestedMessageId, chatId],
      );
      if (!result.rows[0]) {
        throw new BadRequestException("Сообщение не принадлежит чату.");
      }
      return requestedMessageId;
    }

    const result = await this.database.query<{ id: string }>(
      `
        select id
        from app.messages
        where chat_id = $1
          and deleted_at is null
        order by created_at desc, id desc
        limit 1
      `,
      [chatId],
    );
    return result.rows[0]?.id ?? null;
  }

  private async listReadReceiptUpdates(
    chatId: string,
    readerId: string,
    lastReadMessageId: string | null,
  ): Promise<MessageRow[]> {
    if (!lastReadMessageId) return [];

    const result = await this.database.query<MessageRow>(
      `
        with read_marker as (
          select created_at
          from app.messages
          where id = $3
            and chat_id = $1
          limit 1
        )
        select m.id, m.chat_id, m.sender_id, m.content, m.message_type,
          m.attachment_file_id, m.reply_to_id, m.forwarded_from_id,
          m.pinned_by, m.pinned_at, m.created_at, m.updated_at,
          m.deleted_at, u.email as sender_email, p.first_name as sender_first_name,
          p.last_name as sender_last_name, u.role as sender_role,
          f.original_name as attachment_original_name,
          f.mime_type as attachment_mime_type,
          f.size_bytes as attachment_size_bytes,
          true as is_read
        from app.messages m
        join read_marker on m.created_at <= read_marker.created_at
        left join app.users u on u.id = m.sender_id
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        left join app.file_objects f on f.id = m.attachment_file_id and f.deleted_at is null
        where m.chat_id = $1
          and m.sender_id is not null
          and m.sender_id <> $2
          and m.deleted_at is null
          and not exists (
            select 1
            from app.chat_members unread_member
            left join app.messages member_marker
              on member_marker.id = unread_member.last_read_message_id
            where unread_member.chat_id = m.chat_id
              and unread_member.left_at is null
              and unread_member.user_id <> m.sender_id
              and (
                unread_member.last_read_message_id is null
                or member_marker.created_at < m.created_at
              )
          )
        order by m.created_at desc, m.id desc
        limit 100
      `,
      [chatId, readerId, lastReadMessageId],
    );

    return result.rows;
  }

  private async assertValidChatAttachment(
    chatId: string,
    attachmentFileId: string,
  ): Promise<void> {
    const result = await this.database.query<{ id: string }>(
      `
        select id
        from app.file_objects
        where id = $1
          and owner_type = 'chat'
          and owner_id = $2
          and purpose in ('chat_attachment', 'chat_voice')
          and deleted_at is null
        limit 1
      `,
      [attachmentFileId, chatId],
    );
    if (!result.rows[0]) {
      throw new NotFoundException("Файл не найден.");
    }
  }

  private async replaceChannelPermissions(
    client: PoolClient,
    channelId: string,
    permissions: ChannelPermissionDto[],
  ) {
    await client.query(
      "delete from app.channel_permissions where channel_id = $1",
      [channelId],
    );

    for (const permission of permissions) {
      if (!permission.userId && !permission.role) {
        throw new BadRequestException(
          "Укажите пользователя или роль для доступа к каналу.",
        );
      }
      await client.query(
        `
          insert into app.channel_permissions (
            channel_id, user_id, role, can_read, can_write
          )
          values ($1, $2, $3::app.user_role, coalesce($4, true), coalesce($5, false))
        `,
        [
          channelId,
          permission.userId ?? null,
          permission.role ?? null,
          permission.canRead ?? null,
          permission.canWrite ?? null,
        ],
      );
    }
  }

  private toChatSummaryDto(row: ChatRow) {
    const ownerFullName = [row.owner_first_name, row.owner_last_name]
      .filter(Boolean)
      .join(" ")
      .trim() || null;
    const assignedFullName = [row.assigned_first_name, row.assigned_last_name]
      .filter(Boolean)
      .join(" ")
      .trim() || null;
    return {
      id: row.id,
      type: row.type,
      title: row.title,
      createdBy: row.created_by,
      lastMessageId: row.last_message_id,
      lastMessageContent: row.last_message_content,
      lastMessageCreatedAt: row.last_message_created_at,
      partnerId: row.partner_user_id ?? null,
      partner: row.partner_user_id
        ? {
            id: row.partner_user_id,
            email: row.partner_email ?? null,
            firstName: row.partner_first_name ?? null,
            lastName: row.partner_last_name ?? null,
            avatarFileId: row.partner_avatar_file_id ?? null,
          }
        : null,
      unreadCount: Number(row.unread_count ?? "0"),
      isMuted: row.is_muted == true,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      ownerName: ownerFullName,
      assignedTo: row.assigned_to_user_id
        ? { id: row.assigned_to_user_id, name: assignedFullName }
        : null,
      folder: row.folder ?? null,
      archived: row.archived_at != null,
    };
  }

  private toMessageDto(
    row: MessageRow,
    opts?: { maskStaffSender?: boolean },
  ) {
    // When masking, the staff sender is collapsed into the anonymous
    // "Администрация" identity and the real senderId is withheld.
    const masked = opts?.maskStaffSender === true;
    return {
      id: row.id,
      chatId: row.chat_id,
      senderId: masked ? null : row.sender_id,
      sender: masked
        ? {
            id: null,
            name: "Администрация",
            firstName: null,
            lastName: null,
            email: null,
          }
        : row.sender_id
          ? {
              id: row.sender_id,
              email: row.sender_email,
              firstName: row.sender_first_name,
              lastName: row.sender_last_name,
            }
          : null,
      content: row.deleted_at ? null : row.content,
      messageType: row.message_type,
      attachmentFileId: row.deleted_at ? null : row.attachment_file_id,
      attachmentName: row.deleted_at ? null : (row.attachment_original_name ?? null),
      attachmentMimeType: row.deleted_at ? null : (row.attachment_mime_type ?? null),
      attachmentSize: row.deleted_at
        ? null
        : row.attachment_size_bytes == null
          ? null
          : Number(row.attachment_size_bytes),
      attachment: row.deleted_at || !row.attachment_file_id
        ? null
        : {
            id: row.attachment_file_id,
            originalFileName: row.attachment_original_name ?? null,
            mimeType: row.attachment_mime_type ?? null,
            sizeBytes: row.attachment_size_bytes == null ? null : Number(row.attachment_size_bytes),
          },
      replyToId: row.reply_to_id,
      forwardedFromId: row.forwarded_from_id,
      pinnedBy: row.pinned_by,
      pinnedAt: row.pinned_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      deletedAt: row.deleted_at,
      isRead: row.is_read == true,
    };
  }

  private toChatMemberDto(row: ChatMemberRow, currentUserId: string) {
    return {
      profileId: row.profile_id,
      userId: row.user_id,
      email: row.email,
      role: row.role,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      avatarFileId: row.avatar_file_id,
      joinedAt: row.joined_at,
      isCurrentUser: row.user_id === currentUserId,
    };
  }

  private toChannelDto(row: ChannelRow) {
    return {
      id: row.id,
      title: row.title,
      description: row.description,
      createdBy: row.created_by,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private toChannelPermissionDto(row: ChannelPermissionRow) {
    return {
      id: row.id,
      userId: row.user_id,
      role: row.role,
      canRead: row.can_read,
      canWrite: row.can_write,
      user: row.user_id
        ? {
            id: row.user_id,
            email: row.user_email,
            firstName: row.user_first_name,
            lastName: row.user_last_name,
          }
        : null,
    };
  }

  private toChannelPostDto(row: ChannelPostRow) {
    return {
      id: row.id,
      channelId: row.channel_id,
      authorId: row.author_id,
      content: row.content,
      attachmentFileId: row.attachment_file_id,
      publishedAt: row.published_at,
      updatedAt: row.updated_at,
    };
  }
}
