import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { ChatInboxService } from "./chat-inbox.service";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

describe("ChatInboxService", () => {
  function createService(overrides?: {
    database?: Partial<DatabaseService>;
    audit?: Partial<AuditService>;
    policy?: Partial<MessengerPolicy>;
    realtime?: Partial<RealtimeGateway>;
    realtimeBus?: Partial<RealtimeBus>;
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
      ...overrides?.policy,
    } as unknown as MessengerPolicy;
    const realtime = {
      publishUserEvent: jest.fn(),
      publishAdminInboxEvent: jest.fn(),
      ...overrides?.realtime,
    } as unknown as RealtimeGateway;
    const realtimeBus = {
      emitCrmChanged: jest.fn(),
      ...overrides?.realtimeBus,
    } as unknown as RealtimeBus;

    return {
      service: new ChatInboxService(
        database,
        audit,
        policy,
        realtime,
        realtimeBus,
      ),
      database,
      audit,
      policy,
      realtime,
      realtimeBus,
    };
  }

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
            // conditional claim update (1 row = won the claim)
            .mockResolvedValueOnce({ rows: [], rowCount: 1 })
            // chat_work_events insert
            .mockResolvedValueOnce({ rows: [{ id: "work-1" }] }),
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
            .mockResolvedValueOnce({ rows: [], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ id: "work-1" }] }),
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

    it("assignChat reports a conflict when another staffer claimed the chat first", async () => {
      const { service, realtime } = createService({
        database: {
          query: jest.fn()
            .mockResolvedValueOnce({ rows: [{ role: "admin" }] })
            // conditional claim update: 0 rows — someone else won the race
            .mockResolvedValueOnce({ rows: [], rowCount: 0 }),
        },
        policy: {
          getChatAccess: jest.fn().mockResolvedValue(adminChat),
          assertCanAssign: jest.fn(),
        },
      });

      await expect(
        service.assignChat(staffActor, "chat-admin", undefined),
      ).rejects.toMatchObject({ status: 409 });
      expect(realtime.publishAdminInboxEvent).not.toHaveBeenCalled();
    });

    it("unassignChat clears assignment and publishes chat.updated with assignedTo null", async () => {
      const assignedChat = {
        ...adminChat, assignedToUserId: "manager-a",
      };
      const { service, database, realtime } = createService({
        database: {
          query: jest.fn()
            .mockResolvedValueOnce({ rows: [] })
            .mockResolvedValueOnce({ rows: [{ id: "work-1" }] }),
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
});
