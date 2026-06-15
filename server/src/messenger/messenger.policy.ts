import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import {
  ActorContext,
  isAdminRole,
  isManagerOrAdminRole,
  isStaffRole
} from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';

export interface ChatAccessRecord {
  id: string;
  type: string;
  memberUserId: string | null;
  memberRole: string | null;
}

export interface ChannelAccessRecord {
  id: string;
  canRead: boolean;
  canWrite: boolean;
}

@Injectable()
export class MessengerPolicy {
  constructor(private readonly database: DatabaseService) {}

  assertCanReadChat(actor: ActorContext, chat: ChatAccessRecord): void {
    if (chat.memberUserId === actor.userId) return;
    if (chat.type === 'administration' && this.isStaff(actor)) return;
    throw new NotFoundException('Чат не найден.');
  }

  assertCanWriteChat(actor: ActorContext, chat: ChatAccessRecord): void {
    this.assertCanReadChat(actor, chat);
    if (chat.type === 'administration' && this.isStaff(actor)) return;
    if (chat.memberUserId === actor.userId) return;
    throw new ForbiddenException('Недостаточно прав для отправки сообщения.');
  }

  assertCanManageGroup(actor: ActorContext, chat: ChatAccessRecord): void {
    if (isManagerOrAdminRole(actor.role)) return;
    if (chat.type === 'group' && chat.memberUserId === actor.userId && chat.memberRole === 'admin') return;
    throw new ForbiddenException('Недостаточно прав для управления группой.');
  }

  assertCanModerateMessage(actor: ActorContext, senderId: string | null): void {
    if (senderId === actor.userId) return;
    if (isAdminRole(actor.role)) return;
    throw new ForbiddenException('Недостаточно прав для изменения сообщения.');
  }

  assertCanCreateGroup(actor: ActorContext): void {
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException('Недостаточно прав для создания группы.');
  }

  assertCanWriteChannel(actor: ActorContext, channel: ChannelAccessRecord): void {
    if (isManagerOrAdminRole(actor.role) || channel.canWrite) return;
    throw new ForbiddenException('Недостаточно прав для публикации в канале.');
  }

  assertCanReadChannel(channel: ChannelAccessRecord): void {
    if (channel.canRead) return;
    throw new NotFoundException('Канал не найден.');
  }

  async canCreateDirectChat(actor: ActorContext, targetUserId: string): Promise<void> {
    if (actor.userId === targetUserId) {
      throw new ForbiddenException('Нельзя создать чат с самим собой.');
    }

    if (isManagerOrAdminRole(actor.role)) return;

    const result = await this.database.query<{ allowed: boolean }>(
      `
        select exists (
          select 1
          from app.lessons l
          join app.students s on s.id = l.student_id and s.deleted_at is null
          join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
          join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          where l.deleted_at is null
            and (
              (sp.user_id = $1 and tp.user_id = $2)
              or (tp.user_id = $1 and sp.user_id = $2)
            )
        ) as allowed
      `,
      [actor.userId, targetUserId]
    );

    if (!result.rows[0]?.allowed) {
      throw new ForbiddenException('Недостаточно прав для создания прямого чата.');
    }
  }

  async canJoinRealtimeRoom(actor: ActorContext, roomType: string, roomId: string): Promise<void> {
    if (roomType === 'user') {
      if (roomId === actor.userId) return;
      throw new ForbiddenException('Недостаточно прав для realtime-комнаты.');
    }

    if (roomType !== 'chat') {
      throw new ForbiddenException('Недостаточно прав для realtime-комнаты.');
    }

    const chat = await this.getChatAccess(actor, roomId);
    if (!chat) throw new NotFoundException('Чат не найден.');
    this.assertCanReadChat(actor, chat);
  }

  async getChatAccess(actor: ActorContext, chatId: string): Promise<ChatAccessRecord | undefined> {
    const result = await this.database.query<ChatAccessRecord>(
      `
        select c.id, c.type, cm.user_id as "memberUserId", cm.role as "memberRole"
        from app.chats c
        left join app.chat_members cm
          on cm.chat_id = c.id and cm.user_id = $2 and cm.left_at is null
        where c.id = $1 and c.deleted_at is null
        limit 1
      `,
      [chatId, actor.userId]
    );
    return result.rows[0];
  }

  async getChannelAccess(actor: ActorContext, channelId: string): Promise<ChannelAccessRecord | undefined> {
    const result = await this.database.query<ChannelAccessRecord>(
      `
        select c.id,
          (
            $2::text in ('manager', 'admin', 'system_admin')
            or exists (
              select 1 from app.channel_permissions cp
              where cp.channel_id = c.id
                and cp.can_read = true
                and (cp.user_id = $3 or cp.role = $2::app.user_role)
            )
          ) as "canRead",
          (
            $2::text in ('manager', 'admin', 'system_admin')
            or exists (
              select 1 from app.channel_permissions cp
              where cp.channel_id = c.id
                and cp.can_write = true
                and (cp.user_id = $3 or cp.role = $2::app.user_role)
            )
          ) as "canWrite"
        from app.channels c
        where c.id = $1 and c.deleted_at is null
        limit 1
      `,
      [channelId, actor.role, actor.userId]
    );
    return result.rows[0];
  }

  private isStaff(actor: ActorContext): boolean {
    return isStaffRole(actor.role);
  }
}
