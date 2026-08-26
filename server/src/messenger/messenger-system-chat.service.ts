import { Injectable, Logger } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { ANNOUNCEMENTS_CHAT_SLUG } from "./messenger.constants";

@Injectable()
export class MessengerSystemChatService {
  private readonly logger = new Logger(MessengerSystemChatService.name);

  constructor(private readonly database: DatabaseService) {}

  async bootstrapAnnouncements(): Promise<void> {
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
        [ANNOUNCEMENTS_CHAT_SLUG],
      );
      let chatId = existing.rows[0]?.id;
      if (!chatId) {
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.chats (type, title, slug, is_system)
            values ('group', 'Объявления', $1, true)
            returning id
          `,
          [ANNOUNCEMENTS_CHAT_SLUG],
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


}
