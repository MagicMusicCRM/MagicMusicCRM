import { Injectable, Logger } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { RealtimeGateway } from "./realtime.gateway";

/**
 * Realtime audience fan-out for the messenger aggregate. Encapsulates the
 * administration-chat rule where clients and staff receive different views of
 * the same event (sender masking) — kept in one place so every writer
 * (message send/edit/pin/delete, read receipts) fans out identically.
 */
@Injectable()
export class MessengerFanoutService {
  private readonly logger = new Logger(MessengerFanoutService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly realtime: RealtimeGateway,
  ) {}

  /**
   * After a chat message is written, push a lightweight `chat.updated` hint to
   * every member's user room (so chat lists/badges refresh even when the member
   * is not inside the chat room) and, for administration chats, to the staff
   * `admin-inbox` surface so brand-new user→staff conversations appear live.
   * Best-effort: realtime failures never break the underlying write.
   */
  async fanoutChatListUpdate(
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
      const memberIds =
        chat.type === "administration"
          ? await this.getAdministrationNonStaffMemberUserIds(chatId)
          : await this.getChatMemberUserIds(chatId);
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

  /**
   * Administration chats intentionally have two realtime views over the same
   * message: clients see staff as "Администрация", staff see the real author.
   * Do not publish sender-sensitive payloads to the shared chat room for this
   * chat type, or both audiences will receive conflicting versions.
   */
  async publishMessageEventForAudience(
    chat: { type: string },
    chatId: string,
    event: "message.created" | "message.updated",
    staffPayload: unknown,
    memberPayload: unknown = staffPayload,
  ): Promise<void> {
    if (chat.type !== "administration") {
      this.realtime.publishChatEvent(chatId, event, staffPayload);
      return;
    }

    try {
      const memberIds = await this.getAdministrationNonStaffMemberUserIds(chatId);
      for (const userId of memberIds) {
        this.realtime.publishUserEvent(userId, event, memberPayload);
      }
      this.realtime.publishAdminInboxEvent(event, staffPayload);
    } catch (err) {
      this.logger.warn(`publishMessageEventForAudience failed: ${String(err)}`);
    }
  }

  private async getChatMemberUserIds(chatId: string): Promise<string[]> {
    const result = await this.database.query<{ user_id: string }>(
      `select user_id from app.chat_members where chat_id = $1 and left_at is null`,
      [chatId],
    );
    return (result?.rows ?? []).map((row) => row.user_id);
  }

  private async getAdministrationNonStaffMemberUserIds(
    chatId: string,
  ): Promise<string[]> {
    const result = await this.database.query<{ user_id: string }>(
      `
        select cm.user_id
        from app.chat_members cm
        join app.users u on u.id = cm.user_id and u.deleted_at is null
        where cm.chat_id = $1
          and cm.left_at is null
          and u.role not in ('admin', 'manager', 'director', 'system_admin')
      `,
      [chatId],
    );
    return (result?.rows ?? []).map((row) => row.user_id);
  }
}
