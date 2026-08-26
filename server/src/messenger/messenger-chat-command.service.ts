import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CreateDirectChatDto } from "./dto/create-direct-chat.dto";
import { CreateGroupChatDto } from "./dto/create-group-chat.dto";
import { SetChatMuteDto } from "./dto/set-chat-mute.dto";
import { UpdateGroupMembersDto } from "./dto/update-group-members.dto";
import { ChatRow, toChatSummaryDto } from "./messenger.mappers";
import {
  MessengerChatAccess,
  MessengerChatAccessService,
} from "./messenger-chat-access.service";
import { MessengerChatQueryService } from "./messenger-chat-query.service";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

@Injectable()
export class MessengerChatCommandService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: MessengerPolicy,
    private readonly access: MessengerChatAccessService,
    private readonly realtime: RealtimeGateway,
    private readonly queries: MessengerChatQueryService,
  ) {}

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
    const chat = await this.access.requireChat(actor, chatId);
    this.policy.assertCanManageGroup(actor, chat);
    const { addUserIds, removeUserIds } = this.prepareGroupMemberChanges(
      actor,
      chat,
      dto,
    );
    await this.assertActiveUsers(addUserIds);
    await this.persistGroupMemberChanges(
      actor,
      chat,
      chatId,
      addUserIds,
      removeUserIds,
    );

    await this.audit.record({
      actor,
      action: "messenger.group_members_updated",
      entityType: "chat",
      entityId: chatId,
    });
    this.realtime.publishChatEvent(chatId, "chat.updated", { id: chatId });
    const result = await this.queries.getChat(actor, chatId);
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
    const chat = await this.access.requireChat(actor, chatId);
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

  async setChatMute(actor: ActorContext, chatId: string, dto: SetChatMuteDto) {
    const chat = await this.access.requireChat(actor, chatId);
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

  private prepareGroupMemberChanges(
    actor: ActorContext,
    chat: MessengerChatAccess,
    dto: UpdateGroupMembersDto,
  ): { addUserIds: string[]; removeUserIds: string[] } {
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
    return { addUserIds, removeUserIds };
  }

  private async persistGroupMemberChanges(
    actor: ActorContext,
    chat: MessengerChatAccess,
    chatId: string,
    addUserIds: string[],
    removeUserIds: string[],
  ): Promise<void> {
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


}
