import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext, isStaffRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MarkReadDto } from "./dto/mark-read.dto";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessageRow, toMessageDto } from "./messenger.mappers";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

/**
 * Read tracking: advances a member's last-read marker and fans out the
 * resulting read receipts. Kept separate from message writes — it only reads
 * app.messages and updates app.chat_members, and reuses the shared
 * MessengerFanoutService for the administration-chat masking rule.
 */
@Injectable()
export class ReadReceiptService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: MessengerPolicy,
    private readonly realtime: RealtimeGateway,
    private readonly fanout: MessengerFanoutService,
  ) {}

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
      const payload = toMessageDto(message);
      const maskedPayload = toMessageDto(message, {
        maskStaffSender:
          chat.type === "administration" &&
          isStaffRole((message.sender_role ?? "") as never),
      });
      await this.fanout.publishMessageEventForAudience(
        chat,
        chatId,
        "message.updated",
        payload,
        maskedPayload,
      );
    }
    return { success: true };
  }

  // ponytail: 4-line policy wrapper copied from MessengerService.
  private async requireChat(actor: ActorContext, chatId: string) {
    const chat = await this.policy.getChatAccess(actor, chatId);
    if (!chat) throw new NotFoundException("Чат не найден.");
    return chat;
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
          p.avatar_file_id as sender_avatar_file_id,
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
}
