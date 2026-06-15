import { BadRequestException, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
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
      ...overrides?.realtime,
    } as unknown as RealtimeGateway;

    return {
      service: new MessengerService(database, audit, policy, realtime),
      database,
      audit,
      policy,
      realtime,
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
    } as unknown as RealtimeGateway;

    const service = new MessengerService(
      database,
      { record: jest.fn() } as unknown as AuditService,
      policy,
      realtime,
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
      expect.stringContaining("values ('administration', 'Администрация', $1)"),
      ["user-a"],
    );
    expect(database.transaction).toHaveBeenCalledTimes(1);
  });
});
