import { BadRequestException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { MessengerFanoutService } from "./messenger-fanout.service";
import { MessengerPolicy } from "./messenger.policy";
import { ReadReceiptService } from "./read-receipt.service";
import { RealtimeGateway } from "./realtime.gateway";

describe("ReadReceiptService", () => {
  const actor = { userId: "user-a", role: "client" as const };

  function createService(overrides?: {
    database?: Partial<DatabaseService>;
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
    const policy = {
      getChatAccess: jest.fn().mockResolvedValue({
        id: "chat-a",
        type: "direct",
        memberUserId: "user-a",
        memberRole: "member",
      }),
      assertCanReadChat: jest.fn(),
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
      service: new ReadReceiptService(database, policy, realtime, fanout),
      database,
      policy,
      realtime,
    };
  }

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
});
