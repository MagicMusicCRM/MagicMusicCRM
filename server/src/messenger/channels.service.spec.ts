import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { ChannelsService } from "./channels.service";
import { MessengerPolicy } from "./messenger.policy";
import { RealtimeGateway } from "./realtime.gateway";

describe("ChannelsService", () => {
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
      ...overrides?.policy,
    } as unknown as MessengerPolicy;
    const realtime = {
      publishChatEvent: jest.fn(),
      publishChannelEvent: jest.fn(),
      publishUserEvent: jest.fn(),
      ...overrides?.realtime,
    } as unknown as RealtimeGateway;

    return {
      service: new ChannelsService(database, audit, policy, realtime),
      database,
      audit,
      policy,
      realtime,
    };
  }

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

  it("lists channel permissions only for channel managers", async () => {
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
        assertCanManageChannel: jest.fn(),
      },
    });

    const result = await service.listChannelPermissions(
      { userId: "manager-a", role: "manager" },
      "channel-a",
    );

    expect(policy.assertCanManageChannel).toHaveBeenCalledWith({
      userId: "manager-a",
      role: "manager",
    });
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

  it("updates channel text without clearing permissions when ACL is omitted", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "channel-a",
            title: "Новое название",
            description: null,
            created_by: "manager-a",
            created_at: new Date("2026-08-12T10:00:00Z"),
            updated_at: new Date("2026-08-12T10:01:00Z"),
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] });
    const { service, database } = createService({
      database: { query },
      policy: {
        getChannelAccess: jest.fn().mockResolvedValue({
          id: "channel-a",
          canRead: true,
          canWrite: true,
        }),
        assertCanManageChannel: jest.fn(),
      },
    });

    await service.updateChannel(
      { userId: "manager-a", role: "manager" },
      "channel-a",
      { title: " Новое название " },
    );

    expect(database.query).toHaveBeenCalledTimes(3);
    expect(
      query.mock.calls.some(([sql]) =>
        sql.includes("delete from app.channel_permissions"),
      ),
    ).toBe(false);
  });

  it("rejects duplicate ACL targets before deleting existing permissions", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "channel-a",
            title: "Канал",
            description: null,
            created_by: "manager-a",
            created_at: new Date("2026-08-12T10:00:00Z"),
            updated_at: new Date("2026-08-12T10:01:00Z"),
          },
        ],
      });
    const { service } = createService({
      database: { query },
      policy: {
        getChannelAccess: jest.fn().mockResolvedValue({
          id: "channel-a",
          canRead: true,
          canWrite: true,
        }),
        assertCanManageChannel: jest.fn(),
      },
    });

    await expect(
      service.updateChannel(
        { userId: "manager-a", role: "manager" },
        "channel-a",
        {
          title: "Канал",
          permissions: [
            { role: "teacher", canRead: true },
            { role: "teacher", canRead: true, canWrite: true },
          ],
        },
      ),
    ).rejects.toThrow(/не должны повторяться/i);

    expect(query).toHaveBeenCalledTimes(2);
    expect(
      query.mock.calls.some(([sql]) =>
        sql.includes("delete from app.channel_permissions"),
      ),
    ).toBe(false);
  });

  it("rejects write-only and ambiguous ACL rules", async () => {
    const make = () =>
      createService({
        database: {
          query: jest
            .fn()
            .mockResolvedValueOnce({
              rows: [],
            })
            .mockResolvedValueOnce({
              rows: [
                {
                  id: "channel-a",
                  title: "Канал",
                  description: null,
                  created_by: "manager-a",
                  created_at: new Date("2026-08-12T10:00:00Z"),
                  updated_at: new Date("2026-08-12T10:01:00Z"),
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
          assertCanManageChannel: jest.fn(),
        },
      }).service;

    await expect(
      make().updateChannel(
        { userId: "manager-a", role: "manager" },
        "channel-a",
        {
          title: "Канал",
          permissions: [{ role: "teacher", canRead: false, canWrite: true }],
        },
      ),
    ).rejects.toThrow(/требует права чтения/i);

    await expect(
      make().updateChannel(
        { userId: "manager-a", role: "manager" },
        "channel-a",
        {
          title: "Канал",
          permissions: [{ userId: "user-a", role: "teacher" }],
        },
      ),
    ).rejects.toThrow(/ровно одного пользователя/i);
  });

  it("fans channel ACL changes out to added, retained and removed readers", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [{ id: "reader-old" }, { id: "reader-shared" }],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "channel-a",
            title: "Канал",
            description: null,
            created_by: "manager-a",
            created_at: new Date("2026-08-12T10:00:00Z"),
            updated_at: new Date("2026-08-12T10:01:00Z"),
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [{ id: "reader-shared" }, { id: "reader-new" }],
      });
    const { service, realtime } = createService({
      database: { query },
      policy: {
        getChannelAccess: jest.fn().mockResolvedValue({
          id: "channel-a",
          canRead: true,
          canWrite: true,
        }),
        assertCanManageChannel: jest.fn(),
      },
    });

    await service.updateChannel(
      { userId: "manager-a", role: "manager" },
      "channel-a",
      { title: "Канал" },
    );

    expect(realtime.publishUserEvent).toHaveBeenCalledWith(
      "reader-shared",
      "channel.updated",
      expect.objectContaining({ id: "channel-a" }),
    );
    expect(realtime.publishUserEvent).toHaveBeenCalledWith(
      "reader-new",
      "channel.created",
      expect.objectContaining({ id: "channel-a" }),
    );
    expect(realtime.publishUserEvent).toHaveBeenCalledWith(
      "reader-old",
      "channel.removed",
      { id: "channel-a" },
    );
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
          .mockResolvedValue({
            id: "channel-a",
            canRead: true,
            canWrite: true,
          }),
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
});
