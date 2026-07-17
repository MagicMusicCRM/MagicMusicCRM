import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext, isStaffRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { DeleteMessageDto } from "./dto/delete-message.dto";
import { UpdateMessageDto } from "./dto/update-message.dto";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessageRow, toMessageDto } from "./messenger.mappers";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

interface ReactionRow {
  emoji: string;
  count: string;
}

/**
 * Per-message operations: reactions, pins, edit, delete. Distinct from chat
 * lifecycle — reads/writes individual app.messages rows and fans out via the
 * shared MessengerFanoutService so administration-chat masking stays uniform.
 */
@Injectable()
export class MessageService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: MessengerPolicy,
    private readonly realtime: RealtimeGateway,
    private readonly fanout: MessengerFanoutService,
  ) {}

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
          false as is_read
      `,
      [messageId, actor.userId],
    );
    const row = result.rows[0];
    const payload = toMessageDto(row);
    const maskedPayload = toMessageDto(row, {
      maskStaffSender:
        chat.type === "administration" &&
        isStaffRole((row?.sender_role ?? "") as never),
    });
    await this.fanout.publishMessageEventForAudience(
      chat,
      message.chat_id,
      "message.updated",
      payload,
      maskedPayload,
    );
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
          false as is_read
      `,
      [messageId],
    );
    const row = result.rows[0];
    const payload = toMessageDto(row);
    const maskedPayload = toMessageDto(row, {
      maskStaffSender:
        chat.type === "administration" &&
        isStaffRole((row?.sender_role ?? "") as never),
    });
    await this.fanout.publishMessageEventForAudience(
      chat,
      message.chat_id,
      "message.updated",
      payload,
      maskedPayload,
    );
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
          false as is_read
      `,
      [messageId, mode],
    );
    const row = result.rows[0];
    const payload = toMessageDto(row);
    const maskedPayload = toMessageDto(row, {
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
    await this.fanout.publishMessageEventForAudience(
      chat,
      message.chat_id,
      "message.updated",
      payload,
      maskedPayload,
    );
    return payload;
  }

  async updateMessage(
    actor: ActorContext,
    messageId: string,
    dto: UpdateMessageDto,
  ) {
    const message = await this.requireMessage(actor, messageId);
    const chat = await this.requireChat(actor, message.chat_id);
    // Правка — тоже отправка: иначе забаненный переписал бы старое сообщение и
    // сказал через него что угодно.
    await this.policy.assertNotBlacklisted(actor);
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
          false as is_read
      `,
      [messageId, content],
    );
    const row = result.rows[0];
    const payload = toMessageDto(row);
    const maskedPayload = toMessageDto(row, {
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
    await this.fanout.publishMessageEventForAudience(
      chat,
      message.chat_id,
      "message.updated",
      payload,
      maskedPayload,
    );
    return payload;
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

  // ponytail: 4-line policy wrapper copied from MessengerService; trivial,
  // not worth a shared util.
  private async requireChat(actor: ActorContext, chatId: string) {
    const chat = await this.policy.getChatAccess(actor, chatId);
    if (!chat) throw new NotFoundException("Чат не найден.");
    return chat;
  }
}
