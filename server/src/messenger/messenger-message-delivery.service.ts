import { BadRequestException, Inject, Injectable, Logger, NotFoundException } from "@nestjs/common";
import { LEAD_INTAKE_PORT, LeadIntakePort } from "../common/lead-intake.port";
import { ActorContext, isStaffRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { SendMessageDto } from "./dto/send-message.dto";
import { MessageRow, toMessageDto } from "./messenger.mappers";
import { MessengerChatAccessService } from "./messenger-chat-access.service";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

interface ChatAttachmentRow { id: string; purpose: "chat_attachment" | "chat_voice"; mime_type: string }

@Injectable()
export class MessengerMessageDeliveryService {
  private readonly logger = new Logger(MessengerMessageDeliveryService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly policy: MessengerPolicy,
    private readonly access: MessengerChatAccessService,
    @Inject(LEAD_INTAKE_PORT) private readonly leadIntake: LeadIntakePort,
    private readonly realtime: RealtimeGateway,
    private readonly fanout: MessengerFanoutService,
  ) {}

  async sendMessage(actor: ActorContext, chatId: string, dto: SendMessageDto) {
    const chat = await this.access.requireChat(actor, chatId);
    this.policy.assertCanWriteChat(actor, chat);
    await this.policy.assertNotBlacklisted(actor);
    const { content, messageType } = await this.prepareMessagePayload(actor, chatId, dto);
    // Resurface ONLY on a client message: a new client note should pull the
    // thread back into every staff inbox. A STAFF reply must not — otherwise
    // the moment you answer a chat you just archived, it un-archives itself.
    const shouldResurface =
      chat.type === "administration" && actor.role === "client";
    const message = await this.persistMessage(actor, chatId, dto, {
      content,
      messageType,
      shouldResurface,
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
    return payload;
  }

  private async prepareMessagePayload(actor: ActorContext, chatId: string, dto: SendMessageDto): Promise<{ content: string | null; messageType: string }> {
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
      actor, chatId, dto.replyToId, dto.forwardedFromId,
    );
    return { content, messageType };
  }

  private async persistMessage(
    actor: ActorContext,
    chatId: string,
    dto: SendMessageDto,
    prepared: {
      content: string | null;
      messageType: string;
      shouldResurface: boolean;
    },
  ): Promise<MessageRow> {
    const { content, messageType, shouldResurface } = prepared;
    return this.database.transaction(async (client) => {
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
      this.assertTextMessagePayload(attachment, voiceDurationMs);
      return;
    }

    if (!attachment) {
      throw new BadRequestException("Для медиа-сообщения требуется файл.");
    }
    if (messageType === "voice") {
      this.assertVoiceMessagePayload(attachment, voiceDurationMs);
      return;
    }

    this.assertMediaMessagePayload(messageType, attachment, voiceDurationMs);
  }

  private assertTextMessagePayload(
    attachment: ChatAttachmentRow | null,
    voiceDurationMs?: number,
  ): void {
    if (attachment || voiceDurationMs != null) {
      throw new BadRequestException(
        "Текстовое сообщение не может содержать медиа-вложение.",
      );
    }
  }

  private assertVoiceMessagePayload(
    attachment: ChatAttachmentRow,
    voiceDurationMs?: number,
  ): void {
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
  }

  private assertMediaMessagePayload(
    messageType: string,
    attachment: ChatAttachmentRow,
    voiceDurationMs?: number,
  ): void {
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
      const sourceChat = await this.access.requireChat(actor, sourceChatId);
      this.policy.assertCanReadChat(actor, sourceChat);
    }
  }
}
