import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { MessageService } from "./message.service";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

describe("MessageService", () => {
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
      assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
      assertCanManageGroup: jest.fn(),
      assertCanModerateMessage: jest.fn(),
      ...overrides?.policy,
    } as unknown as MessengerPolicy;
    const realtime = {
      publishChatEvent: jest.fn(),
      publishUserEvent: jest.fn(),
      publishAdminInboxEvent: jest.fn(),
      ...overrides?.realtime,
    } as unknown as RealtimeGateway;
    const fanout = new MessengerFanoutService(database, realtime);

    return {
      service: new MessageService(database, audit, policy, realtime, fanout),
      database,
      audit,
      policy,
      realtime,
    };
  }

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
          assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
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
          assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
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
          assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
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
          assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
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
          assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
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
          assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
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
          assertNotBlacklisted: jest.fn().mockResolvedValue(undefined),
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
  });
});
