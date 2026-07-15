import { BadRequestException, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { LeadIntakePort } from "../common/lead-intake.port";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
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
    realtimeBus?: Partial<RealtimeBus>;
    crm?: Partial<LeadIntakePort>;
  }) {
    const database = {
      query: jest.fn(),
      transaction: jest.fn(),
      ...overrides?.database,
    } as unknown as DatabaseService;
    if (!overrides?.database?.transaction) {
      (database.transaction as jest.Mock).mockImplementation(
        async (fn: (client: DatabaseService) => unknown) => fn(database),
      );
    }
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
    } as unknown as LeadIntakePort;
    const realtimeBus = {
      emitCrmChanged: jest.fn(),
      ...overrides?.realtimeBus,
    } as unknown as RealtimeBus;

    return {
      service: new MessengerService(
        database,
        audit,
        policy,
        realtime,
        crm,
        realtimeBus,
      ),
      database,
      audit,
      policy,
      realtime,
      crm,
      realtimeBus,
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
      { autoCreateLeadFromChat: jest.fn().mockResolvedValue({ leadId: "l1", created: true }) } as unknown as LeadIntakePort,
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
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

  it("creates the Объявления group chat and backfills membership when missing", async () => {
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [] }) // lookup by slug -> none
        .mockResolvedValueOnce({ rows: [{ id: "chat-announcements" }] }) // insert chat
        .mockResolvedValue({ rows: [] }), // membership backfill
    };
    const { service } = createService({
      database: {
        transaction: jest.fn(
          async (work: (c: MockClient) => Promise<unknown>) => work(client),
        ) as never,
      },
    });

    await service.ensureAnnouncementsChat();

    // 1 slug lookup + 1 chat insert + 1 membership backfill.
    expect(client.query).toHaveBeenCalledTimes(3);
    expect(client.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining("insert into app.chats"),
      ["announcements"],
    );
    expect(client.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining("insert into app.chat_members"),
      ["chat-announcements"],
    );
  });

  it("does not create a duplicate Объявления chat when one already exists (idempotent)", async () => {
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [{ id: "chat-existing" }] }) // slug lookup -> found
        .mockResolvedValue({ rows: [] }), // membership backfill
    };
    const { service } = createService({
      database: {
        transaction: jest.fn(
          async (work: (c: MockClient) => Promise<unknown>) => work(client),
        ) as never,
      },
    });

    await service.ensureAnnouncementsChat();

    const sqls = client.query.mock.calls.map((call) => call[0] as string);
    expect(sqls.some((sql) => sql.includes("insert into app.chats"))).toBe(
      false,
    );
    // 1 lookup + 1 membership backfill, no chat insert.
    expect(client.query).toHaveBeenCalledTimes(2);
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

  it("fanoutChatListUpdate masks senderId for member rooms but keeps real senderId in admin-inbox when staff sends", async () => {
    const adminChatId = "chat-admin-fanout";
    const staffActor = { userId: "staff-user-fanout", role: "manager" as const };
    const memberUserId = "client-member-fanout";
    type MockClient = { query: jest.Mock };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [
            {
              id: "msg-fanout-1",
              chat_id: adminChatId,
              sender_id: staffActor.userId,
              content: "Привет от менеджера",
              message_type: "text",
              attachment_file_id: null,
              reply_to_id: null,
              forwarded_from_id: null,
              pinned_by: null,
              pinned_at: null,
              created_at: new Date("2026-06-25T11:00:00Z"),
              updated_at: new Date("2026-06-25T11:00:00Z"),
              deleted_at: null,
              sender_email: null,
              sender_first_name: null,
              sender_last_name: null,
              sender_role: "manager",
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
        // getChatMemberUserIds query returns the member client
        query: jest.fn().mockResolvedValue({ rows: [{ user_id: memberUserId }] }),
      },
      policy: {
        getChatAccess: jest.fn().mockResolvedValue({
          id: adminChatId,
          type: "administration",
          memberUserId: null,
          memberRole: null,
        }),
        assertCanWriteChat: jest.fn(),
      },
    });

    await service.sendMessage(staffActor, adminChatId, {
      content: "Привет от менеджера",
    } as never);

    // Member's user-room preview must have senderId masked to null
    expect(realtime.publishUserEvent).toHaveBeenCalledWith(
      memberUserId,
      "chat.updated",
      expect.objectContaining({
        id: adminChatId,
        lastMessageId: "msg-fanout-1",
        senderId: null,
      }),
    );
    // Admin-inbox preview must carry the REAL staff senderId
    expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
      "chat.updated",
      expect.objectContaining({
        id: adminChatId,
        lastMessageId: "msg-fanout-1",
        senderId: staffActor.userId,
      }),
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

  it("listChats: soft-deleted assignee yields assignedTo.name=null but preserves assignedTo.id", async () => {
    // Simulates a row where the assignee user/profile join yielded null (deleted_at gated)
    // so assigned_first_name and assigned_last_name are null, but assigned_to_user_id is still
    // populated from the chats table column. Locks in the degraded-state DTO behavior.
    const staffActor = { userId: "manager-x", role: "manager" as const };
    const rowWithDeletedAssignee = {
      id: "chat-admin-2",
      type: "administration",
      title: "Администрация",
      created_by: "client-2",
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
      owner_first_name: "Иван",
      owner_last_name: "Петров",
      // assigned_to_user_id comes from chats column (always present)
      assigned_to_user_id: "asg-1",
      // joined profile columns are null because asg.deleted_at is not null → join excluded
      assigned_first_name: null,
      assigned_last_name: null,
      folder: "leads",
      archived_at: null,
    };

    const { service } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [rowWithDeletedAssignee] }),
      },
    });

    const result = await service.listChats(staffActor, {});

    expect(result.items).toHaveLength(1);
    const item = result.items[0];
    // The assignment id is still present (from chats.assigned_to_user_id)
    expect(item.assignedTo).not.toBeNull();
    expect(item.assignedTo!.id).toBe("asg-1");
    // The name must be null/falsy — the departed staff's real name must NOT surface
    expect(item.assignedTo!.name).toBeNull();
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

  describe("client-side staff-identity masking in administration chats", () => {
    const adminChatId = "chat-admin-mask";
    const staffMessageRow = {
      id: "msg-staff",
      chat_id: adminChatId,
      sender_id: "staff-1",
      content: "Здравствуйте, чем помочь?",
      message_type: "text",
      attachment_file_id: null,
      reply_to_id: null,
      forwarded_from_id: null,
      pinned_by: null,
      pinned_at: null,
      created_at: new Date("2026-06-25T10:00:00Z"),
      updated_at: new Date("2026-06-25T10:00:00Z"),
      deleted_at: null,
      sender_email: "manager@example.com",
      sender_first_name: "Анна",
      sender_last_name: "Иванова",
      sender_role: "manager",
      sender_avatar_file_id: "avatar-staff",
      is_read: true,
    };
    const ownClientMessageRow = {
      id: "msg-client",
      chat_id: adminChatId,
      sender_id: "client-owner",
      content: "Здравствуйте!",
      message_type: "text",
      attachment_file_id: null,
      reply_to_id: null,
      forwarded_from_id: null,
      pinned_by: null,
      pinned_at: null,
      created_at: new Date("2026-06-25T09:00:00Z"),
      updated_at: new Date("2026-06-25T09:00:00Z"),
      deleted_at: null,
      sender_email: "client@example.com",
      sender_first_name: "Пётр",
      sender_last_name: "Сидоров",
      sender_role: "client",
      sender_avatar_file_id: "avatar-client",
      is_read: true,
    };

    function makeAdminChatService(rows: unknown[]) {
      return createService({
        database: {
          query: jest.fn().mockResolvedValueOnce({ rows }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
        },
      });
    }

    it("masks a STAFF-sent message to 'Администрация' when the OWNER client reads", async () => {
      const { service } = makeAdminChatService([staffMessageRow]);

      const result = await service.getMessages(
        { userId: "client-owner", role: "client" },
        adminChatId,
        {},
      );

      const msg = result.items[0];
      expect(msg.senderId).toBeNull();
      expect(msg.sender).toEqual({
        id: null,
        name: "Администрация",
        firstName: null,
        lastName: null,
        email: null,
        role: null,
        avatarFileId: null,
      });
    });

    it("returns the REAL staff sender when a STAFF viewer reads the same chat", async () => {
      const { service } = makeAdminChatService([staffMessageRow]);

      const result = await service.getMessages(
        { userId: "manager-x", role: "manager" },
        adminChatId,
        {},
      );

      const msg = result.items[0];
      expect(msg.senderId).toBe("staff-1");
      expect(msg.sender).toEqual(
        expect.objectContaining({
          id: "staff-1",
          email: "manager@example.com",
          firstName: "Анна",
          lastName: "Иванова",
          role: "manager",
          avatarFileId: "avatar-staff",
        }),
      );
    });

    it("leaves the client's OWN (non-staff) message unchanged for the owner client", async () => {
      const { service } = makeAdminChatService([ownClientMessageRow]);

      const result = await service.getMessages(
        { userId: "client-owner", role: "client" },
        adminChatId,
        {},
      );

      const msg = result.items[0];
      expect(msg.senderId).toBe("client-owner");
      expect(msg.sender).toEqual(
        expect.objectContaining({
          id: "client-owner",
          firstName: "Пётр",
          lastName: "Сидоров",
        }),
      );
    });

    it("publishes audience-specific message.created when STAFF sends in an administration chat", async () => {
      const staffActor = { userId: "staff-1", role: "manager" as const };
      type MockClient = { query: jest.Mock };
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({
            rows: [
              {
                id: "msg-staff-rt",
                chat_id: adminChatId,
                sender_id: staffActor.userId,
                content: "Готов помочь",
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
                sender_role: "manager",
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
          query: jest.fn().mockResolvedValue({ rows: [{ user_id: "client-owner" }] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: null,
            memberRole: null,
          }),
          assertCanWriteChat: jest.fn(),
        },
      });

      await service.sendMessage(staffActor, adminChatId, {
        content: "Готов помочь",
      } as never);

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "client-owner",
        "message.created",
        expect.objectContaining({
          senderId: null,
          sender: expect.objectContaining({ id: null, name: "Администрация" }),
        }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.created",
        expect.objectContaining({ senderId: staffActor.userId }),
      );
      expect(realtime.publishChatEvent).not.toHaveBeenCalledWith(
        adminChatId,
        "message.created",
        expect.anything(),
      );
    });

    it("publishes an UNMASKED message.created to both audiences when a NON-staff client sends in an administration chat", async () => {
      const clientActor = { userId: "client-owner", role: "client" as const };
      type MockClient = { query: jest.Mock };
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({
            rows: [
              {
                id: "msg-client-rt",
                chat_id: adminChatId,
                sender_id: clientActor.userId,
                content: "Здравствуйте",
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
                sender_role: "client",
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
          query: jest.fn().mockResolvedValue({ rows: [{ user_id: clientActor.userId }] }),
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

      await service.sendMessage(clientActor, adminChatId, {
        content: "Здравствуйте",
      } as never);

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        clientActor.userId,
        "message.created",
        expect.objectContaining({ senderId: clientActor.userId }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.created",
        expect.objectContaining({ senderId: clientActor.userId }),
      );
      expect(realtime.publishChatEvent).not.toHaveBeenCalledWith(
        adminChatId,
        "message.created",
        expect.anything(),
      );
    });
  });

  describe("staff-identity masking on message.updated realtime paths", () => {
    const adminChatId = "chat-admin-upd";
    const groupChatId = "chat-group-upd";

    function baseUpdatedRow(overrides: Record<string, unknown> = {}) {
      return {
        id: "msg-upd",
        chat_id: adminChatId,
        sender_id: "staff-1",
        content: "Закреплено",
        message_type: "text",
        attachment_file_id: null,
        reply_to_id: null,
        forwarded_from_id: null,
        pinned_by: "staff-1",
        pinned_at: new Date("2026-06-25T10:00:00Z"),
        created_at: new Date("2026-06-25T10:00:00Z"),
        updated_at: new Date("2026-06-25T10:00:00Z"),
        deleted_at: null,
        sender_email: null,
        sender_first_name: null,
        sender_last_name: null,
        sender_role: "manager",
        is_read: false,
        ...overrides,
      };
    }

    // --- pinMessage ---

    it("pinMessage masks senderId for a STAFF author in an administration chat", async () => {
      // query #1 requireMessage, query #2 UPDATE...returning
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-upd", chat_id: adminChatId, sender_id: "staff-1" }] })
            .mockResolvedValueOnce({ rows: [baseUpdatedRow()] })
            .mockResolvedValueOnce({ rows: [{ user_id: "client-owner" }] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
          assertCanManageGroup: jest.fn(),
        },
      });

      await service.pinMessage({ userId: "staff-1", role: "manager" }, "msg-upd");

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "client-owner",
        "message.updated",
        expect.objectContaining({ senderId: null }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.updated",
        expect.objectContaining({ senderId: "staff-1" }),
      );
    });

    it("pinMessage keeps the real senderId in a NON-administration (group) chat", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-upd", chat_id: groupChatId, sender_id: "staff-1" }] })
            .mockResolvedValueOnce({ rows: [baseUpdatedRow({ chat_id: groupChatId })] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: groupChatId,
            type: "group",
            memberUserId: "staff-1",
            memberRole: "owner",
          }),
          assertCanReadChat: jest.fn(),
          assertCanManageGroup: jest.fn(),
        },
      });

      await service.pinMessage({ userId: "staff-1", role: "manager" }, "msg-upd");

      expect(realtime.publishChatEvent).toHaveBeenCalledWith(
        groupChatId,
        "message.updated",
        expect.objectContaining({ senderId: "staff-1" }),
      );
    });

    it("pinMessage keeps the real senderId for a NON-staff (client) author in an administration chat", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-upd", chat_id: adminChatId, sender_id: "client-owner" }] })
            .mockResolvedValueOnce({
              rows: [baseUpdatedRow({ sender_id: "client-owner", sender_role: "client" })],
            })
            .mockResolvedValueOnce({ rows: [{ user_id: "client-owner" }] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
          assertCanManageGroup: jest.fn(),
        },
      });

      await service.pinMessage({ userId: "manager-x", role: "manager" }, "msg-upd");

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "client-owner",
        "message.updated",
        expect.objectContaining({ senderId: "client-owner" }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.updated",
        expect.objectContaining({ senderId: "client-owner" }),
      );
    });

    // --- deleteMessage ---

    it("deleteMessage masks senderId for a STAFF author in an administration chat", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-upd", chat_id: adminChatId, sender_id: "staff-1" }] })
            .mockResolvedValueOnce({
              rows: [baseUpdatedRow({ content: null, deleted_at: new Date("2026-06-25T10:05:00Z") })],
            })
            .mockResolvedValueOnce({ rows: [{ user_id: "client-owner" }] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
          assertCanModerateMessage: jest.fn(),
        },
      });

      await service.deleteMessage({ userId: "manager-x", role: "manager" }, "msg-upd", {} as never);

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "client-owner",
        "message.updated",
        expect.objectContaining({ senderId: null }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.updated",
        expect.objectContaining({ senderId: "staff-1" }),
      );
    });

    it("deleteMessage keeps the real senderId in a NON-administration (group) chat", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-upd", chat_id: groupChatId, sender_id: "staff-1" }] })
            .mockResolvedValueOnce({
              rows: [baseUpdatedRow({ chat_id: groupChatId, content: null, deleted_at: new Date("2026-06-25T10:05:00Z") })],
            }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: groupChatId,
            type: "group",
            memberUserId: "staff-1",
            memberRole: "owner",
          }),
          assertCanReadChat: jest.fn(),
          assertCanModerateMessage: jest.fn(),
        },
      });

      await service.deleteMessage({ userId: "manager-x", role: "manager" }, "msg-upd", {} as never);

      expect(realtime.publishChatEvent).toHaveBeenCalledWith(
        groupChatId,
        "message.updated",
        expect.objectContaining({ senderId: "staff-1" }),
      );
    });

    // --- unpinMessage ---

    it("unpinMessage masks senderId for a STAFF author in an administration chat", async () => {
      // query #1 requireMessage, query #2 UPDATE...returning
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-upd", chat_id: adminChatId, sender_id: "staff-1" }] })
            .mockResolvedValueOnce({ rows: [baseUpdatedRow({ pinned_by: null, pinned_at: null })] })
            .mockResolvedValueOnce({ rows: [{ user_id: "client-owner" }] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
          assertCanManageGroup: jest.fn(),
        },
      });

      await service.unpinMessage({ userId: "staff-1", role: "manager" }, "msg-upd");

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "client-owner",
        "message.updated",
        expect.objectContaining({ senderId: null }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.updated",
        expect.objectContaining({ senderId: "staff-1" }),
      );
    });

    // --- updateMessage ---

    it("updateMessage masks senderId for a STAFF author editing their own message in an administration chat", async () => {
      // query #1 requireMessage, query #2 UPDATE...returning
      // NOTE: updateMessage enforces message.sender_id === actor.userId, so actor must match the message author
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({
              rows: [{ id: "msg-upd", chat_id: adminChatId, sender_id: "staff-1", deleted_at: null, message_type: "text", attachment_file_id: null }],
            })
            .mockResolvedValueOnce({ rows: [baseUpdatedRow({ content: "Обновлено" })] })
            .mockResolvedValueOnce({ rows: [{ user_id: "client-owner" }] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
        },
      });

      await service.updateMessage(
        { userId: "staff-1", role: "manager" },
        "msg-upd",
        { content: "Обновлено" } as never,
      );

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "client-owner",
        "message.updated",
        expect.objectContaining({ senderId: null }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.updated",
        expect.objectContaining({ senderId: "staff-1" }),
      );
    });

    // --- markRead read-receipt path ---

    it("markRead masks senderId for a STAFF-authored receipt in an administration chat", async () => {
      // query #1 resolveLastReadMessageId, #2 update chat_members, #3 listReadReceiptUpdates
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-read" }] })
            .mockResolvedValueOnce({ rowCount: 1, rows: [] })
            .mockResolvedValueOnce({
              rows: [baseUpdatedRow({ id: "msg-read", is_read: true })],
            })
            .mockResolvedValueOnce({ rows: [{ user_id: "client-owner" }] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: adminChatId,
            type: "administration",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
        },
      });

      await service.markRead({ userId: "client-owner", role: "client" }, adminChatId, {
        lastReadMessageId: "msg-read",
      } as never);

      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "client-owner",
        "message.updated",
        expect.objectContaining({ id: "msg-read", senderId: null }),
      );
      expect(realtime.publishAdminInboxEvent).toHaveBeenCalledWith(
        "message.updated",
        expect.objectContaining({ id: "msg-read", senderId: "staff-1" }),
      );
    });

    it("markRead keeps the real senderId for a STAFF-authored receipt in a NON-administration chat", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({ rows: [{ id: "msg-read" }] })
            .mockResolvedValueOnce({ rowCount: 1, rows: [] })
            .mockResolvedValueOnce({
              rows: [baseUpdatedRow({ id: "msg-read", chat_id: groupChatId, is_read: true })],
            }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: groupChatId,
            type: "group",
            memberUserId: "client-owner",
            memberRole: "member",
          }),
          assertCanReadChat: jest.fn(),
        },
      });

      await service.markRead({ userId: "client-owner", role: "client" }, groupChatId, {
        lastReadMessageId: "msg-read",
      } as never);

      expect(realtime.publishChatEvent).toHaveBeenCalledWith(
        groupChatId,
        "message.updated",
        expect.objectContaining({ id: "msg-read", senderId: "staff-1" }),
      );
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

  // ─── Task 8: leaveGroup ───────────────────────────────────────────────────

  describe("leaveGroup", () => {
    const leaveActor = { userId: "member-a", role: "client" as const };
    const groupChat = {
      id: "chat-group-leave",
      type: "group",
      memberUserId: "member-a",
      memberRole: "member",
    };

    it("updates left_at for the leaving member and emits chat.removed to their user room", async () => {
      const { service, database, realtime } = createService({
        database: {
          query: jest.fn().mockResolvedValueOnce({ rows: [] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(groupChat),
        },
      });

      await service.leaveGroup(leaveActor, "chat-group-leave");

      expect(database.query).toHaveBeenCalledWith(
        expect.stringContaining("set left_at = now()"),
        ["chat-group-leave", "member-a"],
      );
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "member-a",
        "chat.removed",
        { id: "chat-group-leave" },
      );
    });

    it("emits chat.updated to the chat room after leaving", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest.fn().mockResolvedValueOnce({ rows: [] }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(groupChat),
        },
      });

      await service.leaveGroup(leaveActor, "chat-group-leave");

      expect(realtime.publishChatEvent).toHaveBeenCalledWith(
        "chat-group-leave",
        "chat.updated",
        { id: "chat-group-leave" },
      );
    });

    it("rejects leaveGroup when the chat is not a group", async () => {
      const { service } = createService({
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: "chat-direct-1",
            type: "direct",
            memberUserId: "member-a",
            memberRole: "member",
          }),
        },
      });

      await expect(service.leaveGroup(leaveActor, "chat-direct-1")).rejects.toThrow();
    });

    it("rejects leaveGroup when the chat does not exist (getChatAccess returns null)", async () => {
      const { service } = createService({
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(null),
        },
      });

      await expect(service.leaveGroup(leaveActor, "chat-group-leave")).rejects.toThrow();
    });

    it("rejects leaveGroup when actor has no membership row (group exists but memberUserId is null), emits NO events", async () => {
      const { service, realtime } = createService({
        policy: {
          getChatAccess: jest.fn().mockResolvedValue({
            id: "chat-group-leave",
            type: "group",
            memberUserId: null,
            memberRole: null,
          }),
        },
      });

      await expect(
        service.leaveGroup(leaveActor, "chat-group-leave"),
      ).rejects.toBeInstanceOf(NotFoundException);

      expect(realtime.publishUserEvent).not.toHaveBeenCalled();
      expect(realtime.publishChatEvent).not.toHaveBeenCalled();
    });
  });

  // ─── Task 8: createGroup fan-out ─────────────────────────────────────────

  describe("createGroup fan-out", () => {
    it("emits chat.created to each member's user room after group is created", async () => {
      const managerActor = { userId: "manager-a", role: "manager" as const };
      const memberIds = ["manager-a", "user-b", "user-c"];
      type MockClient = { query: jest.Mock };
      const client = {
        query: jest
          .fn()
          // insert chats returning row
          .mockResolvedValueOnce({
            rows: [
              {
                id: "chat-group-new",
                type: "group",
                title: "My Group",
                created_by: "manager-a",
                last_message_id: null,
                last_message_content: null,
                last_message_created_at: null,
                unread_count: "0",
                created_at: new Date("2026-06-25T10:00:00Z"),
                updated_at: new Date("2026-06-25T10:00:00Z"),
              },
            ],
          })
          // insertMembers calls (3 members)
          .mockResolvedValue({ rows: [] }),
      };

      const { service, realtime } = createService({
        database: {
          // assertActiveUsers: return all 3 users
          query: jest.fn().mockResolvedValueOnce({
            rows: memberIds.map((id) => ({ id })),
          }),
          transaction: jest.fn(
            async (work: (c: MockClient) => Promise<unknown>) => work(client),
          ) as never,
        },
        policy: {
          assertCanCreateGroup: jest.fn(),
        },
      });

      await service.createGroup(managerActor, {
        name: "My Group",
        memberUserIds: ["user-b", "user-c"],
      });

      // chat.created must be published to every member's user room
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "manager-a",
        "chat.created",
        expect.objectContaining({ id: "chat-group-new", type: "group" }),
      );
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "user-b",
        "chat.created",
        expect.objectContaining({ id: "chat-group-new", type: "group" }),
      );
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "user-c",
        "chat.created",
        expect.objectContaining({ id: "chat-group-new", type: "group" }),
      );
      expect(realtime.publishUserEvent).toHaveBeenCalledTimes(3);
    });
  });

  // ─── Task 8: updateGroupMembers fan-out ──────────────────────────────────

  describe("updateGroupMembers fan-out", () => {
    const managerActor = { userId: "manager-a", role: "manager" as const };
    const groupChat = {
      id: "chat-group-upd",
      type: "group",
      memberUserId: "manager-a",
      memberRole: "admin",
    };

    it("emits chat.created to added members and chat.removed to removed members", async () => {
      type MockClient = { query: jest.Mock };
      const client = {
        query: jest.fn().mockResolvedValue({ rows: [] }),
      };

      // getChat query result for the return value + fan-out summary
      const chatRow = {
        id: "chat-group-upd",
        type: "group",
        title: "My Group",
        created_by: "manager-a",
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
      };

      const { service, realtime } = createService({
        database: {
          // assertActiveUsers call
          query: jest.fn()
            .mockResolvedValueOnce({ rows: [{ id: "user-new" }] })
            // getChat inner query
            .mockResolvedValueOnce({ rows: [chatRow] }),
          transaction: jest.fn(
            async (work: (c: MockClient) => Promise<unknown>) => work(client),
          ) as never,
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(groupChat),
          assertCanManageGroup: jest.fn(),
          assertCanReadChat: jest.fn(),
        },
      });

      await service.updateGroupMembers(managerActor, "chat-group-upd", {
        addUserIds: ["user-new"],
        removeUserIds: ["user-old"],
      });

      // chat.created to added member's user room — must carry neutral isMuted/unreadCount
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "user-new",
        "chat.created",
        expect.objectContaining({ id: "chat-group-upd", type: "group", isMuted: false, unreadCount: 0 }),
      );
      // chat.removed to removed member's user room
      expect(realtime.publishUserEvent).toHaveBeenCalledWith(
        "user-old",
        "chat.removed",
        { id: "chat-group-upd" },
      );
      // existing chat.updated to the chat room still fires
      expect(realtime.publishChatEvent).toHaveBeenCalledWith(
        "chat-group-upd",
        "chat.updated",
        { id: "chat-group-upd" },
      );
    });
  });
});
