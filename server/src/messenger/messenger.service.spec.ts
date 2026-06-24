import { BadRequestException, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { CrmService } from "../crm/crm.service";
import { DatabaseService } from "../db/database.service";
import { MessengerPolicy } from "./messenger.policy";
import { MessengerService } from "./messenger.service";
import { RealtimeGateway } from "./realtime.gateway";

describe("MessengerService", () => {
  const actor = { userId: "user-a", role: "client" as const };

  function createService(overrides?: {
    database?: Partial<DatabaseService>;
    audit?: Partial<AuditService>;
    policy?: Partial<MessengerPolicy>;
    realtime?: Partial<RealtimeGateway>;
    crm?: Partial<CrmService>;
  }) {
    const database = {
      query: jest.fn(),
      transaction: jest.fn(),
      ...overrides?.database,
    } as unknown as DatabaseService;
    const audit = {
      record: jest.fn(),
      ...overrides?.audit,
    } as unknown as AuditService;
    const policy = {
      getChatAccess: jest.fn().mockResolvedValue({
        id: "chat-a",
        type: "direct",
        memberUserId: "user-a",
        memberRole: "member",
      }),
      assertCanReadChat: jest.fn(),
      assertCanWriteChat: jest.fn(),
      assertCanCreateGroup: jest.fn(),
      assertCanManageGroup: jest.fn(),
      ...overrides?.policy,
    } as unknown as MessengerPolicy;
    const realtime = {
      publishChatEvent: jest.fn(),
      publishChannelEvent: jest.fn(),
      publishUserEvent: jest.fn(),
      publishAdminInboxEvent: jest.fn(),
      ...overrides?.realtime,
    } as unknown as RealtimeGateway;
    const crm = {
      autoCreateLeadFromChat: jest
        .fn()
        .mockResolvedValue({ leadId: "l1", created: true }),
      ...overrides?.crm,
    } as unknown as CrmService;

    return {
      service: new MessengerService(database, audit, policy, realtime, crm),
      database,
      audit,
      policy,
      realtime,
      crm,
    };
  }

  it("publishes message.created only after the transaction completes", async () => {
    const order: string[] = [];
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [
            {
              id: "message-a",
              chat_id: "chat-a",
              sender_id: "user-a",
              content: "hello",
              message_type: "text",
              attachment_file_id: null,
              reply_to_id: null,
              forwarded_from_id: null,
              pinned_by: null,
              pinned_at: null,
              created_at: new Date("2026-06-11T18:00:00Z"),
              updated_at: new Date("2026-06-11T18:00:00Z"),
              deleted_at: null,
              sender_email: null,
              sender_first_name: null,
              sender_last_name: null,
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] }),
    };
    const database = {
      transaction: jest.fn(
        async (work: (client: MockClient) => Promise<unknown>) => {
          order.push("transaction:start");
          const result = await work(client);
          order.push("transaction:done");
          return result;
        },
      ),
      query: jest.fn().mockResolvedValue({ rows: [] }),
    } as unknown as DatabaseService;
    const policy = {
      getChatAccess: jest.fn().mockResolvedValue({
        id: "chat-a",
        type: "direct",
        memberUserId: "user-a",
        memberRole: "member",
      }),
      assertCanWriteChat: jest.fn(),
    } as unknown as MessengerPolicy;
    const realtime = {
      publishChatEvent: jest.fn(() => order.push("publish")),
      publishUserEvent: jest.fn(),
      publishAdminInboxEvent: jest.fn(),
    } as unknown as RealtimeGateway;

    const service = new MessengerService(
      database,
      { record: jest.fn() } as unknown as AuditService,
      policy,
      realtime,
      { autoCreateLeadFromChat: jest.fn().mockResolvedValue({ leadId: "l1", created: true }) } as unknown as CrmService,
    );

    const result = await service.sendMessage(
      { userId: "user-a", role: "client" },
      "chat-a",
      { content: "hello" },
    );

    expect(result.id).toBe("message-a");
    expect(realtime.publishChatEvent).toHaveBeenCalledWith(
      "chat-a",
      "message.created",
      expect.objectContaining({ id: "message-a", content: "hello" }),
    );
    expect(order).toEqual(["transaction:start", "transaction:done", "publish"]);
  });

  it("rejects markRead when lastReadMessageId belongs to another chat", async () => {
    const { service, database } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [] }),
      },
    });

    await expect(
      service.markRead(actor, "chat-a", { lastReadMessageId: "message-other" }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("from app.messages"),
      ["message-other", "chat-a"],
    );
    expect(database.query).toHaveBeenCalledTimes(1);
  });

  it("derives markRead lastReadMessageId from the latest chat message when omitted", async () => {
    const { service, database, realtime } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [{ id: "message-latest" }] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [] }),
      },
    });

    await expect(service.markRead(actor, "chat-a", {})).resolves.toEqual({
      success: true,
    });

    expect(database.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining("order by created_at desc"),
      ["chat-a"],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining("update app.chat_members"),
      ["chat-a", "user-a", "message-latest"],
    );
    expect(realtime.publishChatEvent).toHaveBeenCalledWith(
      "chat-a",
      "chat.updated",
      {
        id: "chat-a",
        readerId: "user-a",
        lastReadMessageId: "message-latest",
      },
    );
  });

  it("publishes message.updated read receipts after markRead", async () => {
    const readMessage = {
      id: "message-read",
      chat_id: "chat-a",
      sender_id: "sender-a",
      content: "hello",
      message_type: "text",
      attachment_file_id: null,
      reply_to_id: null,
      forwarded_from_id: null,
      pinned_by: null,
      pinned_at: null,
      created_at: new Date("2026-06-13T10:00:00Z"),
      updated_at: new Date("2026-06-13T10:00:00Z"),
      deleted_at: null,
      sender_email: "sender@example.com",
      sender_first_name: "Анна",
      sender_last_name: "Иванова",
      is_read: true,
    };
    const { service, realtime } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [{ id: "message-read" }] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [readMessage] }),
      },
    });

    await service.markRead(actor, "chat-a", {
      lastReadMessageId: "message-read",
    });

    expect(realtime.publishChatEvent).toHaveBeenCalledWith(
      "chat-a",
      "message.updated",
      expect.objectContaining({
        id: "message-read",
        isRead: true,
      }),
    );
  });

  it("persists chat mute state for the current member", async () => {
    const { service, database, audit, realtime, policy } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [] }),
      },
    });

    await expect(
      service.setChatMute(actor, "chat-a", { isMuted: true }),
    ).resolves.toEqual({
      success: true,
      isMuted: true,
    });

    expect(policy.assertCanReadChat).toHaveBeenCalled();
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("set muted_until"),
      ["chat-a", "user-a", true],
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "messenger.chat_muted",
        entityType: "chat",
        entityId: "chat-a",
      }),
    );
    expect(realtime.publishChatEvent).toHaveBeenCalledWith(
      "chat-a",
      "chat.updated",
      { id: "chat-a", userId: "user-a", isMuted: true },
    );
  });

  it("prevalidates createGroup members against active users before inserting members", async () => {
    const { service, database } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [{ id: "user-a" }] }),
        transaction: jest.fn(),
      },
    });

    await expect(
      service.createGroup(
        { userId: "user-a", role: "manager" },
        {
          name: "Group",
          memberUserIds: ["user-missing"],
        },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("from app.users"),
      [["user-a", "user-missing"]],
    );
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it("prevalidates updateGroupMembers addUserIds against active users before transaction", async () => {
    const { service, database } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [] }),
        transaction: jest.fn(),
      },
      policy: {
        getChatAccess: jest.fn().mockResolvedValue({
          id: "chat-a",
          type: "group",
          memberUserId: "manager-a",
          memberRole: "admin",
        }),
      },
    });

    await expect(
      service.updateGroupMembers(
        { userId: "manager-a", role: "manager" },
        "chat-a",
        { addUserIds: ["user-missing"] },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("from app.users"),
      [["user-missing"]],
    );
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it("lists active chat members for a readable chat", async () => {
    const { service, database, policy } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({
          rows: [
            {
              profile_id: "profile-manager-a",
              user_id: "manager-a",
              email: "manager@example.com",
              role: "admin",
              first_name: "Мария",
              last_name: "Петрова",
              avatar_file_id: "avatar-a",
              joined_at: new Date("2026-06-13T10:00:00Z"),
            },
          ],
        }),
      },
      policy: {
        getChatAccess: jest.fn().mockResolvedValue({
          id: "chat-a",
          type: "group",
          memberUserId: "user-a",
          memberRole: "member",
        }),
      },
    });

    const result = await service.listChatMembers(actor, "chat-a");

    expect(policy.assertCanReadChat).toHaveBeenCalledWith(
      actor,
      expect.objectContaining({ id: "chat-a", type: "group" }),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("from app.chat_members cm"),
      ["chat-a"],
    );
    expect(result.items).toEqual([
      expect.objectContaining({
        profileId: "profile-manager-a",
        userId: "manager-a",
        email: "manager@example.com",
        role: "admin",
        firstName: "Мария",
        lastName: "Петрова",
        avatarFileId: "avatar-a",
        isCurrentUser: false,
      }),
    ]);
  });

  it("returns current channel access for readable channels", async () => {
    const { service, policy } = createService({
      policy: {
        getChannelAccess: jest.fn().mockResolvedValue({
          id: "channel-a",
          canRead: true,
          canWrite: false,
        }),
        assertCanReadChannel: jest.fn(),
      },
    });

    await expect(service.getChannelAccess(actor, "channel-a")).resolves.toEqual(
      {
        channelId: "channel-a",
        canRead: true,
        canWrite: false,
      },
    );

    expect(policy.assertCanReadChannel).toHaveBeenCalledWith(
      expect.objectContaining({ id: "channel-a", canRead: true }),
    );
  });

  it("lists channel permissions for users who can write the channel", async () => {
    const { service, database, policy } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({
          rows: [
            {
              id: "permission-a",
              user_id: "teacher-a",
              role: null,
              can_read: true,
              can_write: true,
              user_email: "teacher@example.com",
              user_first_name: "Анна",
              user_last_name: "Иванова",
            },
          ],
        }),
      },
      policy: {
        getChannelAccess: jest.fn().mockResolvedValue({
          id: "channel-a",
          canRead: true,
          canWrite: true,
        }),
        assertCanWriteChannel: jest.fn(),
      },
    });

    const result = await service.listChannelPermissions(
      { userId: "manager-a", role: "manager" },
      "channel-a",
    );

    expect(policy.assertCanWriteChannel).toHaveBeenCalledWith(
      { userId: "manager-a", role: "manager" },
      expect.objectContaining({ id: "channel-a", canWrite: true }),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("from app.channel_permissions cp"),
      ["channel-a"],
    );
    expect(result.items).toEqual([
      expect.objectContaining({
        id: "permission-a",
        userId: "teacher-a",
        role: null,
        canRead: true,
        canWrite: true,
        user: expect.objectContaining({
          email: "teacher@example.com",
          firstName: "Анна",
          lastName: "Иванова",
        }),
      }),
    ]);
  });

  it("rejects message attachmentFileId that is not an active chat attachment for the chat", async () => {
    const { service, database } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [] }),
        transaction: jest.fn(),
      },
    });

    await expect(
      service.sendMessage(actor, "chat-a", {
        content: "file",
        attachmentFileId: "file-other",
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("from app.file_objects"),
      ["file-other", "chat-a"],
    );
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it("updates own text message and publishes message.updated", async () => {
    const { service, database, audit, realtime } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({
            rows: [
              {
                id: "message-a",
                chat_id: "chat-a",
                sender_id: "user-a",
                content: "old",
                message_type: "text",
                attachment_file_id: null,
                reply_to_id: null,
                forwarded_from_id: null,
                pinned_by: null,
                pinned_at: null,
                created_at: new Date("2026-06-13T10:00:00Z"),
                updated_at: new Date("2026-06-13T10:00:00Z"),
                deleted_at: null,
                sender_email: null,
                sender_first_name: null,
                sender_last_name: null,
              },
            ],
          })
          .mockResolvedValueOnce({
            rows: [
              {
                id: "message-a",
                chat_id: "chat-a",
                sender_id: "user-a",
                content: "new text",
                message_type: "text",
                attachment_file_id: null,
                reply_to_id: null,
                forwarded_from_id: null,
                pinned_by: null,
                pinned_at: null,
                created_at: new Date("2026-06-13T10:00:00Z"),
                updated_at: new Date("2026-06-13T10:01:00Z"),
                deleted_at: null,
                sender_email: null,
                sender_first_name: null,
                sender_last_name: null,
              },
            ],
          }),
      },
    });

    const result = await service.updateMessage(actor, "message-a", {
      content: "  new text  ",
    });

    expect(result.content).toBe("new text");
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining("update app.messages"),
      ["message-a", "new text"],
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "messenger.message_updated",
        entityType: "message",
        entityId: "message-a",
      }),
    );
    expect(realtime.publishChatEvent).toHaveBeenCalledWith(
      "chat-a",
      "message.updated",
      expect.objectContaining({ id: "message-a", content: "new text" }),
    );
  });

  it("audits message deletion (moderation log)", async () => {
    const baseRow = {
      id: "message-a",
      chat_id: "chat-a",
      sender_id: "user-a",
      content: "hi",
      message_type: "text",
      attachment_file_id: null,
      reply_to_id: null,
      forwarded_from_id: null,
      pinned_by: null,
      pinned_at: null,
      created_at: new Date("2026-06-13T10:00:00Z"),
      updated_at: new Date("2026-06-13T10:00:00Z"),
      deleted_at: null,
      sender_email: null,
      sender_first_name: null,
      sender_last_name: null,
    };
    const { service, audit } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [baseRow] })
          .mockResolvedValueOnce({
            rows: [
              { ...baseRow, content: null, deleted_at: new Date("2026-06-13T10:05:00Z") },
            ],
          }),
      },
      policy: { assertCanModerateMessage: jest.fn() },
    });

    await service.deleteMessage(actor, "message-a", {});

    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "messenger.message_deleted",
        entityType: "message",
        entityId: "message-a",
      }),
    );
  });

  it("creates administration chats with Russian title", async () => {
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({
          rows: [
            {
              id: "chat-admin",
              type: "administration",
              title: "Администрация",
              created_by: "user-a",
              last_message_id: null,
              last_message_content: null,
              last_message_created_at: null,
              unread_count: "0",
              created_at: new Date("2026-06-13T10:00:00Z"),
              updated_at: new Date("2026-06-13T10:00:00Z"),
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] }),
    };
    const { service, database } = createService({
      database: {
        transaction: jest.fn(
          async (work: (client: MockClient) => Promise<unknown>) =>
            work(client),
        ) as never,
      },
    });

    const chat = await service.createDirectChat(actor, {
      type: "administration",
    });

    expect(chat.title).toBe("Администрация");
    expect(client.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining("values ('administration', 'Администрация', $1, $1)"),
      ["user-a"],
    );
    expect(database.transaction).toHaveBeenCalledTimes(1);
  });

  it("auto-creates a lead when a non-staff user posts to the administration chat", async () => {
    const clientActor = { userId: "client-user-a", role: "client" as const };
    const adminChatId = "chat-admin-a";
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [
            {
              id: "msg-1",
              chat_id: adminChatId,
              sender_id: clientActor.userId,
              content: "Здравствуйте",
              message_type: "text",
              attachment_file_id: null,
              reply_to_id: null,
              forwarded_from_id: null,
              pinned_by: null,
              pinned_at: null,
              created_at: new Date("2026-06-20T10:00:00Z"),
              updated_at: new Date("2026-06-20T10:00:00Z"),
              deleted_at: null,
              sender_email: null,
              sender_first_name: null,
              sender_last_name: null,
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] }),
    };
    const { service, crm } = createService({
      database: {
        transaction: jest.fn(
          async (work: (client: MockClient) => Promise<unknown>) => work(client),
        ) as never,
      },
      policy: {
        getChatAccess: jest.fn().mockResolvedValue({
          id: adminChatId,
          type: "administration",
          memberUserId: clientActor.userId,
          memberRole: "member",
        }),
        assertCanWriteChat: jest.fn(),
      },
    });

    await service.sendMessage(clientActor, adminChatId, { content: "Здравствуйте" } as never);

    expect(crm.autoCreateLeadFromChat).toHaveBeenCalledWith(clientActor, clientActor.userId);
  });

  it("does NOT auto-create a lead for a staff sender or a non-administration chat", async () => {
    const staffActor = { userId: "manager-user-a", role: "manager" as const };
    const adminChatId = "chat-admin-a";
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [
            {
              id: "msg-2",
              chat_id: adminChatId,
              sender_id: staffActor.userId,
              content: "ok",
              message_type: "text",
              attachment_file_id: null,
              reply_to_id: null,
              forwarded_from_id: null,
              pinned_by: null,
              pinned_at: null,
              created_at: new Date("2026-06-20T10:00:00Z"),
              updated_at: new Date("2026-06-20T10:00:00Z"),
              deleted_at: null,
              sender_email: null,
              sender_first_name: null,
              sender_last_name: null,
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] }),
    };
    const { service, crm } = createService({
      database: {
        transaction: jest.fn(
          async (work: (client: MockClient) => Promise<unknown>) => work(client),
        ) as never,
      },
      policy: {
        getChatAccess: jest.fn().mockResolvedValue({
          id: adminChatId,
          type: "administration",
          memberUserId: staffActor.userId,
          memberRole: "member",
        }),
        assertCanWriteChat: jest.fn(),
      },
    });

    await service.sendMessage(staffActor, adminChatId, { content: "ok" } as never);

    expect(crm.autoCreateLeadFromChat).not.toHaveBeenCalled();
  });

  it("does NOT auto-create a lead for a non-administration chat (even from a client)", async () => {
    const clientActor = { userId: "client-user-b", role: "client" as const };
    const directChatId = "chat-direct-b";
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [
            {
              id: "msg-3",
              chat_id: directChatId,
              sender_id: clientActor.userId,
              content: "hi",
              message_type: "text",
              attachment_file_id: null,
              reply_to_id: null,
              forwarded_from_id: null,
              pinned_by: null,
              pinned_at: null,
              created_at: new Date("2026-06-20T10:00:00Z"),
              updated_at: new Date("2026-06-20T10:00:00Z"),
              deleted_at: null,
              sender_email: null,
              sender_first_name: null,
              sender_last_name: null,
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] }),
    };
    const { service, crm } = createService({
      database: {
        transaction: jest.fn(
          async (work: (client: MockClient) => Promise<unknown>) => work(client),
        ) as never,
      },
      policy: {
        getChatAccess: jest.fn().mockResolvedValue({
          id: directChatId,
          type: "direct",
          memberUserId: clientActor.userId,
          memberRole: "member",
        }),
        assertCanWriteChat: jest.fn(),
      },
    });

    await service.sendMessage(clientActor, directChatId, { content: "hi" } as never);

    expect(crm.autoCreateLeadFromChat).not.toHaveBeenCalled();
  });

  it("seeds the default Объявления channel and role permissions when missing", async () => {
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [] }) // adopt-by-title update -> none
        .mockResolvedValueOnce({ rows: [] }) // lookup by slug -> none
        .mockResolvedValueOnce({ rows: [{ id: "channel-announcements" }] }) // insert channel
        .mockResolvedValue({ rows: [] }), // 5 permission guards
    };
    const { service } = createService({
      database: {
        transaction: jest.fn(
          async (work: (c: MockClient) => Promise<unknown>) => work(client),
        ) as never,
      },
    });

    await service.ensureDefaultChannels();

    // 1 adopt update + 1 slug lookup + 1 channel insert + 5 permission inserts.
    expect(client.query).toHaveBeenCalledTimes(8);
    expect(client.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining("insert into app.channels"),
      ["announcements"],
    );
    const roles = client.query.mock.calls.slice(3).map((call) => call[1][1]);
    expect(roles).toEqual([
      "client",
      "teacher",
      "admin",
      "manager",
      "system_admin",
    ]);
  });

  it("does not create a duplicate Объявления channel when one already exists (idempotent)", async () => {
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [] }) // adopt-by-title update -> none
        .mockResolvedValueOnce({ rows: [{ id: "channel-existing" }] }) // slug lookup -> found
        .mockResolvedValue({ rows: [] }),
    };
    const { service } = createService({
      database: {
        transaction: jest.fn(
          async (work: (c: MockClient) => Promise<unknown>) => work(client),
        ) as never,
      },
    });

    await service.ensureDefaultChannels();

    const sqls = client.query.mock.calls.map((call) => call[0] as string);
    expect(sqls.some((sql) => sql.includes("insert into app.channels"))).toBe(
      false,
    );
    // 1 adopt update + 1 lookup + 5 permission guards, no channel insert.
    expect(client.query).toHaveBeenCalledTimes(7);
  });

  it("publishes channel.post_created to the channel room, never a chat room", async () => {
    const { service, realtime } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({
          rows: [
            {
              id: "post-a",
              channel_id: "channel-a",
              author_id: "manager-a",
              content: "Объявление",
              attachment_file_id: null,
              published_at: new Date("2026-06-20T10:00:00Z"),
              updated_at: new Date("2026-06-20T10:00:00Z"),
            },
          ],
        }),
      },
      policy: {
        getChannelAccess: jest
          .fn()
          .mockResolvedValue({ id: "channel-a", canRead: true, canWrite: true }),
        assertCanWriteChannel: jest.fn(),
      },
    });

    const post = await service.createChannelPost(
      { userId: "manager-a", role: "manager" },
      "channel-a",
      { content: "Объявление" } as never,
    );

    expect(post.id).toBe("post-a");
    expect(realtime.publishChannelEvent).toHaveBeenCalledWith(
      "channel-a",
      "channel.post_created",
      expect.objectContaining({ id: "post-a" }),
    );
    expect(realtime.publishChatEvent).not.toHaveBeenCalled();
  });

  it("fans out chat.updated to the admin inbox and member rooms for administration messages", async () => {
    const adminChatId = "chat-admin-a";
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [
            {
              id: "msg-1",
              chat_id: adminChatId,
              sender_id: "client-a",
              content: "Здравствуйте",
              message_type: "text",
              attachment_file_id: null,
              reply_to_id: null,
              forwarded_from_id: null,
              pinned_by: null,
              pinned_at: null,
              created_at: new Date("2026-06-20T10:00:00Z"),
              updated_at: new Date("2026-06-20T10:00:00Z"),
              deleted_at: null,
              sender_email: null,
              sender_first_name: null,
              sender_last_name: null,
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] }),
    };
    const { service, realtime } = createService({
      database: {
        transaction: jest.fn(
          async (work: (c: MockClient) => Promise<unknown>) => work(client),
        ) as never,
        query: jest.fn().mockResolvedValue({ rows: [{ user_id: "client-a" }] }),
      },
      policy: {
        getChatAccess: jest.fn().mockResolvedValue({
          id: adminChatId,
          type: "administration",
          memberUserId: "client-a",
          memberRole: "member",
        }),
        assertCanWriteChat: jest.fn(),
      },
    });

    await service.sendMessage(
      { userId: "client-a", role: "client" },
      adminChatId,
      { content: "Здравствуйте" } as never,
    );

    expect(realtime.publishUserEvent).toHaveBeenCalledWith(
      "client-a",
      "chat.updated",
      expect.objectContaining({ id: adminChatId, lastMessageId: "msg-1" }),
    );
    expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
      "chat.updated",
      expect.objectContaining({ id: adminChatId, lastMessageId: "msg-1" }),
    );
  });

  it("staff listChats maps owner, assignedTo, folder, archived from administration row", async () => {
    const staffActor = { userId: "manager-x", role: "manager" as const };
    const adminRow = {
      id: "chat-admin-1",
      type: "administration",
      title: "Администрация",
      created_by: "client-1",
      last_message_id: null,
      last_message_content: null,
      last_message_created_at: null,
      unread_count: "0",
      is_muted: false,
      partner_user_id: null,
      partner_email: null,
      partner_first_name: null,
      partner_last_name: null,
      partner_avatar_file_id: null,
      created_at: new Date("2026-06-25T10:00:00Z"),
      updated_at: new Date("2026-06-25T10:00:00Z"),
      // new columns from Task 4 joins
      owner_first_name: "Иван",
      owner_last_name: "Петров",
      assigned_to_user_id: "staff-user-1",
      assigned_first_name: "Анна",
      assigned_last_name: "Иванова",
      folder: "students",
      archived_at: null,
    };

    const { service } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [adminRow] }),
      },
    });

    const result = await service.listChats(staffActor, {});

    expect(result.items).toHaveLength(1);
    const item = result.items[0];
    expect(item.ownerName).toBe("Иван Петров");
    expect(item.assignedTo).toEqual({ id: "staff-user-1", name: "Анна Иванова" });
    expect(item.folder).toBe("students");
    expect(item.archived).toBe(false);
  });

  describe("assignChat / unassignChat", () => {
    const staffActor = { userId: "staff-a", role: "admin" as const };
    const managerActor = { userId: "manager-a", role: "manager" as const };
    const adminChat = {
      id: "chat-admin", type: "administration",
      memberUserId: null, memberRole: null, assignedToUserId: null,
    };

    it("assignChat sets assigned_to_user_id/assigned_at and publishes chat.updated to admin inbox", async () => {
      const { service, database, realtime } = createService({
        database: {
          query: jest.fn()
            // requireStaffTarget: user role lookup
            .mockResolvedValueOnce({ rows: [{ role: "admin" }] })
            // update query
            .mockResolvedValueOnce({ rows: [] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(adminChat),
          assertCanAssign: jest.fn(),
        },
      });

      await service.assignChat(staffActor, "chat-admin", undefined);

      expect(database.query).toHaveBeenCalledWith(
        expect.stringContaining("assigned_to_user_id"),
        expect.arrayContaining(["chat-admin", "staff-a"]),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "chat.updated",
        expect.objectContaining({ id: "chat-admin" }),
      );
    });

    it("assignChat self-claim works for any staff actor (admin role)", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest.fn()
            .mockResolvedValueOnce({ rows: [{ role: "admin" }] })
            .mockResolvedValueOnce({ rows: [] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(adminChat),
          assertCanAssign: jest.fn(),
        },
      });

      const adminActor = { userId: "admin-b", role: "admin" as const };
      await service.assignChat(adminActor, "chat-admin", undefined);

      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "chat.updated",
        expect.objectContaining({ id: "chat-admin" }),
      );
    });

    it("unassignChat clears assignment and publishes chat.updated with assignedTo null", async () => {
      const assignedChat = {
        ...adminChat, assignedToUserId: "manager-a",
      };
      const { service, database, realtime } = createService({
        database: {
          query: jest.fn().mockResolvedValueOnce({ rows: [] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(assignedChat),
          assertCanAssign: jest.fn(),
        },
      });

      await service.unassignChat(managerActor, "chat-admin");

      expect(database.query).toHaveBeenCalledWith(
        expect.stringContaining("assigned_to_user_id = null"),
        ["chat-admin"],
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "chat.updated",
        expect.objectContaining({ id: "chat-admin", assignedTo: null }),
      );
    });
  });

  it("creates an administration chat with the actor as owner", async () => {
    type MockClient = { query: jest.Mock };
    const client = { query: jest.fn()
      .mockResolvedValueOnce({ rows: [] }) // existing lookup
      .mockResolvedValueOnce({ rows: [{ id: 'chat-admin', type: 'administration', title: 'Администрация',
        created_by: 'user-a', last_message_id: null, last_message_content: null,
        last_message_created_at: null, unread_count: '0',
        created_at: new Date(), updated_at: new Date() }] }) // insert
      .mockResolvedValueOnce({ rows: [] }) }; // insertMembers
    const { service } = createService({ database: { transaction: jest.fn(
      async (w: (c: MockClient) => Promise<unknown>) => w(client)) as never } });
    await service.createDirectChat({ userId: 'user-a', role: 'client' }, { type: 'administration' });
    const insert = client.query.mock.calls.find(c => String(c[0]).includes("values ('administration'"));
    expect(insert![0]).toContain('owner_user_id');
    expect(insert![1]).toContain('user-a');
  });

  describe("archiveChat / unarchiveChat", () => {
    const staffActor = { userId: "staff-user-1", role: "manager" as const };
    const adminChat = {
      id: "chat-admin-1",
      type: "administration",
      memberUserId: null,
      memberRole: null,
      assignedToUserId: null,
    };

    it("archiveChat upserts chat_inbox_state with archived_at=now() and emits chat.updated to staff user room", async () => {
      const { service, database, realtime } = createService({
        database: {
          query: jest.fn().mockResolvedValueOnce({ rows: [] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(adminChat),
        },
      });

      await service.archiveChat(staffActor, "chat-admin-1");

      expect(database.query).toHaveBeenCalledWith(
        expect.stringContaining("chat_inbox_state"),
        expect.arrayContaining(["chat-admin-1", "staff-user-1"]),
      );
      expect(database.query).toHaveBeenCalledWith(
        expect.stringContaining("on conflict"),
        expect.anything(),
      );
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "staff-user-1",
        "chat.updated",
        expect.objectContaining({ id: "chat-admin-1", archived: true }),
      );
    });

    it("unarchiveChat upserts chat_inbox_state with archived_at=null and emits chat.updated { archived: false }", async () => {
      const { service, database, realtime } = createService({
        database: {
          query: jest.fn().mockResolvedValueOnce({ rows: [] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(adminChat),
        },
      });

      await service.unarchiveChat(staffActor, "chat-admin-1");

      expect(database.query).toHaveBeenCalledWith(
        expect.stringContaining("chat_inbox_state"),
        expect.arrayContaining(["chat-admin-1", "staff-user-1"]),
      );
      expect(database.query).toHaveBeenCalledWith(
        expect.stringContaining("on conflict"),
        expect.anything(),
      );
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "staff-user-1",
        "chat.updated",
        expect.objectContaining({ id: "chat-admin-1", archived: false }),
      );
    });

    it("archiveChat rejects non-staff actors", async () => {
      const clientActor = { userId: "client-1", role: "client" as const };
      const { service } = createService({
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(adminChat),
        },
      });

      await expect(service.archiveChat(clientActor, "chat-admin-1")).rejects.toThrow();
    });

    it("archiveChat rejects non-administration chats", async () => {
      const { service } = createService({
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: "chat-direct-1",
            type: "direct",
            memberUserId: "staff-user-1",
            memberRole: "member",
          }),
        },
      });

      await expect(service.archiveChat(staffActor, "chat-direct-1")).rejects.toThrow();
    });
  });

  describe("sendMessage resurface on administration chat", () => {
    it("clears archived_at for all staff when a message is sent in an administration chat", async () => {
      const adminChatId = "chat-admin-resurface";
      type MockClient = { query: jest.Mock };
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({
            rows: [
              {
                id: "msg-r1",
                chat_id: adminChatId,
                sender_id: "client-r",
                content: "Resurface me",
                message_type: "text",
                attachment_file_id: null,
                reply_to_id: null,
                forwarded_from_id: null,
                pinned_by: null,
                pinned_at: null,
                created_at: new Date("2026-06-25T10:00:00Z"),
                updated_at: new Date("2026-06-25T10:00:00Z"),
                deleted_at: null,
                sender_email: null,
                sender_first_name: null,
                sender_last_name: null,
              },
            ],
          })
          .mockResolvedValueOnce({ rows: [] }), // update chats last_message_id
      };
      const dbQuery = jest.fn().mockResolvedValue({ rows: [] });
      const { service, database } = createService({
        database: {
          transaction: jest.fn(
            async (work: (c: MockClient) => Promise<unknown>) => work(client),
          ) as never,
          query: dbQuery,
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-r",
            memberRole: "member",
          }),
          assertCanWriteChat: jest.fn(),
        },
      });

      await service.sendMessage(
        { userId: "client-r", role: "client" },
        adminChatId,
        { content: "Resurface me" } as never,
      );

      // The resurface update must have been issued
      const calls = dbQuery.mock.calls as Array<[string, unknown[]]>;
      const resurface = calls.find(
        ([sql]) =>
          sql.includes("chat_inbox_state") &&
          sql.includes("archived_at = null") &&
          sql.includes("chat_id = $1"),
      );
      expect(resurface).toBeDefined();
      expect(resurface![1]).toEqual([adminChatId]);
    });

    it("does NOT issue the resurface update for a non-administration chat", async () => {
      const directChatId = "chat-direct-resurface";
      type MockClient = { query: jest.Mock };
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({
            rows: [
              {
                id: "msg-d1",
                chat_id: directChatId,
                sender_id: "user-d",
                content: "hi",
                message_type: "text",
                attachment_file_id: null,
                reply_to_id: null,
                forwarded_from_id: null,
                pinned_by: null,
                pinned_at: null,
                created_at: new Date("2026-06-25T10:00:00Z"),
                updated_at: new Date("2026-06-25T10:00:00Z"),
                deleted_at: null,
                sender_email: null,
                sender_first_name: null,
                sender_last_name: null,
              },
            ],
          })
          .mockResolvedValueOnce({ rows: [] }),
      };
      const dbQuery = jest.fn().mockResolvedValue({ rows: [] });
      const { service } = createService({
        database: {
          transaction: jest.fn(
            async (work: (c: MockClient) => Promise<unknown>) => work(client),
          ) as never,
          query: dbQuery,
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: directChatId,
            type: "direct",
            memberUserId: "user-d",
            memberRole: "member",
          }),
          assertCanWriteChat: jest.fn(),
        },
      });

      await service.sendMessage(
        { userId: "user-d", role: "client" },
        directChatId,
        { content: "hi" } as never,
      );

      const calls = dbQuery.mock.calls as Array<[string, unknown[]]>;
      const resurface = calls.find(
        ([sql]) => sql.includes("chat_inbox_state") && sql.includes("archived_at = null"),
      );
      expect(resurface).toBeUndefined();
    });
  });
});
