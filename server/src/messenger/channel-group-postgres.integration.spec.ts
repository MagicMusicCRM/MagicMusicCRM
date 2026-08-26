import { NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { LeadIntakePort } from "../common/lead-intake.port";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { RealtimeBus } from "../realtime/realtime-bus";
import { ChannelsService } from "./channels.service";
import { ChatInboxService } from "./chat-inbox.service";
import { MessengerChatAccessService } from "./messenger-chat-access.service";
import { MessengerChatCommandService } from "./messenger-chat-command.service";
import { MessengerChatQueryService } from "./messenger-chat-query.service";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessengerMessageDeliveryService } from "./messenger-message-delivery.service";
import { MessengerPolicy } from "./messenger.policy";
import { MessengerService } from "./messenger.service";
import { MessengerSystemChatService } from "./messenger-system-chat.service";
import { RealtimeGateway } from "./realtime.gateway";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)
) {
  throw new Error("Channel/group integration tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("channel and group lifecycle (PostgreSQL)", () => {
  let database: DatabaseService;
  let channels: ChannelsService;
  let inbox: ChatInboxService;
  let messenger: MessengerService;
  let manager: ActorContext;
  let teacher: ActorContext;
  let client: ActorContext;
  const userIds: string[] = [];
  const channelIds: string[] = [];
  const chatIds: string[] = [];
  const staffIds: string[] = [];

  const audit = {
    record: jest.fn().mockResolvedValue(undefined),
  } as unknown as AuditService;
  const realtime = {
    publishChatEvent: jest.fn(),
    publishChannelEvent: jest.fn(),
    publishUserEvent: jest.fn(),
    publishAdminInboxEvent: jest.fn(),
  } as unknown as RealtimeGateway;

  async function createUser(
    role: ActorContext["role"],
    name: string,
  ): Promise<ActorContext> {
    const result = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, $2::app.user_role, now())
        returning id
      `,
      [`uat-111-${randomUUID()}@example.test`, role],
    );
    const userId = result.rows[0]!.id;
    userIds.push(userId);
    await database.query(
      "insert into app.profiles (user_id, first_name) values ($1, $2)",
      [userId, name],
    );
    return { userId, role };
  }

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const policy = new MessengerPolicy(database);
    const fanout = new MessengerFanoutService(database, realtime);
    channels = new ChannelsService(database, audit, policy, realtime);
    inbox = new ChatInboxService(database, audit, policy, realtime, {
      emitCrmChanged: jest.fn(),
    } as unknown as RealtimeBus);
    const access = new MessengerChatAccessService(policy);
    const queries = new MessengerChatQueryService(database, policy, access);
    messenger = new MessengerService(
      new MessengerSystemChatService(database),
      queries,
      new MessengerMessageDeliveryService(
        database,
        policy,
        access,
        { autoCreateLeadFromChat: jest.fn() } as unknown as LeadIntakePort,
        realtime,
        fanout,
      ),
      new MessengerChatCommandService(
        database,
        audit,
        policy,
        access,
        realtime,
        queries,
      ),
    );
    manager = await createUser("manager", "Управляющий");
    teacher = await createUser("teacher", "Преподаватель");
    client = await createUser("client", "Клиент");
  });

  afterAll(async () => {
    if (!database) return;
    if (chatIds.length > 0) {
      await database.query("delete from app.chats where id = any($1::uuid[])", [
        chatIds,
      ]);
    }
    if (channelIds.length > 0) {
      await database.query(
        "delete from app.channels where id = any($1::uuid[])",
        [channelIds],
      );
    }
    if (userIds.length > 0) {
      await database.query(
        "delete from app.audit_events where actor_user_id = any($1::uuid[])",
        [userIds],
      );
      if (staffIds.length > 0) {
        await database.query(
          "delete from app.staff_members where id = any($1::uuid[])",
          [staffIds],
        );
      }
      await database.query("delete from app.users where id = any($1::uuid[])", [
        userIds,
      ]);
    }
    await database.onModuleDestroy();
  });

  it("keeps publishing separate from channel management and persists exact ACL", async () => {
    const channel = await channels.createChannel(manager, {
      title: "Новости школы",
      permissions: [
        { role: "teacher", canRead: true, canWrite: true },
        { userId: client.userId, canRead: true, canWrite: false },
      ],
    });
    channelIds.push(channel.id);

    await expect(
      channels.createChannelPost(teacher, channel.id, {
        content: "Новость преподавателя",
      }),
    ).resolves.toEqual(expect.objectContaining({ channelId: channel.id }));
    await expect(
      channels.updateChannel(teacher, channel.id, { title: "Захваченный" }),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      channels.listChannelPermissions(teacher, channel.id),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect((await channels.listChannels(teacher)).items).toEqual([
      expect.objectContaining({ id: channel.id }),
    ]);
    expect((await channels.listChannels(client)).items).toEqual([
      expect.objectContaining({ id: channel.id }),
    ]);

    await channels.updateChannel(manager, channel.id, {
      title: "Только клиенту",
      permissions: [{ userId: client.userId, canRead: true, canWrite: false }],
    });
    expect((await channels.listChannels(teacher)).items).toHaveLength(0);
    expect((await channels.listChannels(client)).items[0]).toEqual(
      expect.objectContaining({ title: "Только клиенту" }),
    );

    await expect(
      database.query(
        `
          insert into app.channel_permissions
            (channel_id, user_id, role, can_read, can_write)
          values ($1, $2, 'teacher', true, false)
        `,
        [channel.id, teacher.userId],
      ),
    ).rejects.toThrow();
    await expect(
      database.query(
        `
          insert into app.channel_permissions
            (channel_id, role, can_read, can_write)
          values ($1, 'teacher', false, true)
        `,
        [channel.id],
      ),
    ).rejects.toThrow();
  });

  it("creates, lists, removes and leaves group membership with app roles intact", async () => {
    const group = await messenger.createGroup(manager, {
      name: "Ансамбль",
      memberUserIds: [teacher.userId, client.userId],
    });
    chatIds.push(group.id);

    const initialMembers = (await messenger.listChatMembers(manager, group.id))
      .items;
    expect(initialMembers).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          userId: teacher.userId,
          role: "member",
          userRole: "teacher",
        }),
        expect.objectContaining({
          userId: client.userId,
          role: "member",
          userRole: "client",
        }),
      ]),
    );

    await messenger.updateGroupMembers(manager, group.id, {
      removeUserIds: [teacher.userId],
    });
    const afterRemoval = (await messenger.listChatMembers(manager, group.id))
      .items;
    expect(afterRemoval.some((item) => item.userId === teacher.userId)).toBe(
      false,
    );
    await expect(messenger.getChat(teacher, group.id)).rejects.toBeInstanceOf(
      NotFoundException,
    );

    await messenger.leaveGroup(client, group.id);
    const afterLeave = (await messenger.listChatMembers(manager, group.id))
      .items;
    expect(afterLeave.map((item) => item.userId)).toEqual([manager.userId]);
  });

  it("assigns, unassigns, archives and restores an administration chat", async () => {
    const staff = await database.query<{ id: string }>(
      `
        insert into app.staff_members (profile_id, role, status)
        select p.id, 'manager', 'working'
        from app.profiles p
        where p.user_id = $1 and p.deleted_at is null
        returning id
      `,
      [manager.userId],
    );
    staffIds.push(staff.rows[0]!.id);
    const chat = await database.query<{ id: string }>(
      `
        insert into app.chats (type, created_by)
        values ('administration', $1)
        returning id
      `,
      [client.userId],
    );
    const chatId = chat.rows[0]!.id;
    chatIds.push(chatId);
    await database.query(
      "insert into app.chat_members (chat_id, user_id) values ($1, $2)",
      [chatId, client.userId],
    );

    await inbox.assignChat(manager, chatId);
    expect(
      (
        await database.query<{ assigned_to_user_id: string | null }>(
          "select assigned_to_user_id from app.chats where id = $1",
          [chatId],
        )
      ).rows[0]!.assigned_to_user_id,
    ).toBe(manager.userId);

    await inbox.archiveChat(manager, chatId);
    expect(
      (
        await database.query<{ archived: boolean }>(
          `
            select archived_at is not null as archived
            from app.chat_inbox_state
            where chat_id = $1 and staff_user_id = $2
          `,
          [chatId, manager.userId],
        )
      ).rows[0]!.archived,
    ).toBe(true);
    await inbox.unarchiveChat(manager, chatId);
    expect(
      (
        await database.query<{ archived: boolean }>(
          `
            select archived_at is not null as archived
            from app.chat_inbox_state
            where chat_id = $1 and staff_user_id = $2
          `,
          [chatId, manager.userId],
        )
      ).rows[0]!.archived,
    ).toBe(false);

    await inbox.unassignChat(manager, chatId);
    expect(
      (
        await database.query<{ assigned_to_user_id: string | null }>(
          "select assigned_to_user_id from app.chats where id = $1",
          [chatId],
        )
      ).rows[0]!.assigned_to_user_id,
    ).toBeNull();
  });
});
