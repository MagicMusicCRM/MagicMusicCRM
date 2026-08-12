import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { ChannelPermissionDto, UpsertChannelDto } from "./dto/channel.dto";
import { CreateChannelPostDto } from "./dto/create-channel-post.dto";
import { MessengerListQuery } from "./dto/messenger-list.query";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

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

@Injectable()
export class ChannelsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: MessengerPolicy,
    private readonly realtime: RealtimeGateway,
  ) {}

  async listChannels(actor: ActorContext) {
    const result = await this.database.query<ChannelRow>(
      `
        select distinct c.id, c.title, c.description, c.created_by,
          c.created_at, c.updated_at
        from app.channels c
        left join app.channel_permissions cp on cp.channel_id = c.id
        where c.deleted_at is null
          and (
            $1::text in ('manager', 'director', 'admin', 'system_admin')
            or (cp.can_read = true and (cp.user_id = $2 or cp.role = $1::app.user_role))
          )
        order by c.created_at desc, c.id desc
      `,
      [actor.role, actor.userId],
    );
    return { items: result.rows.map((row) => this.toChannelDto(row)) };
  }

  async createChannel(actor: ActorContext, dto: UpsertChannelDto) {
    this.policy.assertCanManageChannel(actor);
    const title = dto.title.trim();
    if (!title) throw new BadRequestException("Укажите название канала.");
    const channel = await this.database.transaction(async (client) => {
      const inserted = await client.query<ChannelRow>(
        `
          insert into app.channels (title, description, created_by)
          values ($1, $2, $3)
          returning id, title, description, created_by, created_at, updated_at
        `,
        [title, dto.description?.trim() || null, actor.userId],
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
    const channelDto = this.toChannelDto(channel);
    const recipients = await this.listChannelRecipientUserIds(channel.id);
    for (const userId of recipients) {
      this.realtime.publishUserEvent(userId, "channel.created", channelDto);
    }
    return channelDto;
  }

  async updateChannel(
    actor: ActorContext,
    channelId: string,
    dto: UpsertChannelDto,
  ) {
    const access = await this.policy.getChannelAccess(actor, channelId);
    if (!access) throw new NotFoundException("Канал не найден.");
    this.policy.assertCanManageChannel(actor);
    const title = dto.title.trim();
    if (!title) throw new BadRequestException("Укажите название канала.");
    const previousRecipients = new Set(
      await this.listChannelRecipientUserIds(channelId),
    );

    const channel = await this.database.transaction(async (client) => {
      const result = await client.query<ChannelRow>(
        `
          update app.channels
          set title = $2, description = $3, updated_at = now()
          where id = $1 and deleted_at is null
          returning id, title, description, created_by, created_at, updated_at
        `,
        [channelId, title, dto.description?.trim() || null],
      );
      const row = result.rows[0];
      if (!row) throw new NotFoundException("Канал не найден.");
      if (dto.permissions != null) {
        await this.replaceChannelPermissions(
          client,
          channelId,
          dto.permissions,
        );
      }
      return row;
    });

    await this.audit.record({
      actor,
      action: "messenger.channel_updated",
      entityType: "channel",
      entityId: channelId,
    });
    const channelDto = this.toChannelDto(channel);
    const nextRecipients = new Set(
      await this.listChannelRecipientUserIds(channelId),
    );
    for (const userId of nextRecipients) {
      this.realtime.publishUserEvent(
        userId,
        previousRecipients.has(userId) ? "channel.updated" : "channel.created",
        channelDto,
      );
    }
    for (const userId of previousRecipients) {
      if (!nextRecipients.has(userId)) {
        this.realtime.publishUserEvent(userId, "channel.removed", {
          id: channelId,
        });
      }
    }
    return channelDto;
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
    this.policy.assertCanManageChannel(actor);

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

  private async replaceChannelPermissions(
    client: PoolClient,
    channelId: string,
    permissions: ChannelPermissionDto[],
  ) {
    const seenTargets = new Set<string>();
    const userIds: string[] = [];
    for (const permission of permissions) {
      const hasUser = Boolean(permission.userId);
      const hasRole = Boolean(permission.role);
      if (hasUser === hasRole) {
        throw new BadRequestException(
          "Для правила доступа укажите ровно одного пользователя или одну роль.",
        );
      }
      const canRead = permission.canRead ?? true;
      const canWrite = permission.canWrite ?? false;
      if (canWrite && !canRead) {
        throw new BadRequestException(
          "Право публикации требует права чтения канала.",
        );
      }
      const target = hasUser
        ? `user:${permission.userId}`
        : `role:${permission.role}`;
      if (seenTargets.has(target)) {
        throw new BadRequestException(
          "Правила доступа к каналу не должны повторяться.",
        );
      }
      seenTargets.add(target);
      if (permission.userId) userIds.push(permission.userId);
    }

    if (userIds.length > 0) {
      const activeUsers = await client.query<{ id: string }>(
        `
          select id
          from app.users
          where id = any($1::uuid[]) and deleted_at is null
        `,
        [userIds],
      );
      const activeIds = new Set(activeUsers.rows.map((row) => row.id));
      if (userIds.some((userId) => !activeIds.has(userId))) {
        throw new BadRequestException(
          "Один или несколько пользователей канала не найдены или отключены.",
        );
      }
    }

    await client.query(
      "delete from app.channel_permissions where channel_id = $1",
      [channelId],
    );

    for (const permission of permissions) {
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

  private async listChannelRecipientUserIds(channelId: string) {
    const result = await this.database.query<{ id: string }>(
      `
        select distinct u.id
        from app.users u
        left join app.channel_permissions cp
          on cp.channel_id = $1
          and cp.can_read = true
          and (cp.user_id = u.id or cp.role = u.role)
        where u.deleted_at is null
          and (
            u.role in ('manager', 'director', 'admin', 'system_admin')
            or cp.id is not null
          )
      `,
      [channelId],
    );
    return result.rows.map((row) => row.id);
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
