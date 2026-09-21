import { PlatformOutboxWorker } from "./platform-outbox.worker";

describe("PlatformOutboxWorker", () => {
  const emptyDatabase = () => ({
    query: jest.fn().mockResolvedValue({ rows: [] }),
  });

  it("resolves a committed Lead create to the persisted Lead before publishing", async () => {
    const event = {
      eventId: "event-lead-create",
      type: "crm.lead.create.committed",
      occurredAt: new Date(),
      aggregateType: "client_create_command",
      aggregateId: "create-lead-0001",
      aggregateVersion: 1,
      requestId: "request-lead-0001",
      payload: {},
      attempts: 1,
    };
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue([event]),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn().mockResolvedValue("retry"),
    };
    const realtime = {
      isReady: () => true,
      emitCrmChanged: jest.fn(),
    };
    const database = {
      query: jest.fn().mockResolvedValue({ rows: [{ lead_id: "lead-a" }] }),
    };
    const worker = new PlatformOutboxWorker(
      integrity as never,
      realtime as never,
      { notifyInboundLead: jest.fn() } as never,
      database as never,
    );

    await expect(worker.runOnce("worker-lead")).resolves.toEqual({
      claimed: 1,
      published: 1,
      retry: 0,
      deadLetter: 0,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("app.idempotency_records"),
      [event.eventId],
    );
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "lead",
      action: "created",
      id: "lead-a",
      branchId: null,
      affectedUserIds: [],
    });
    expect(integrity.markOutboxPublished).toHaveBeenCalledWith(
      event.eventId,
      "worker-lead",
    );
    expect(integrity.markOutboxFailed).not.toHaveBeenCalled();
  });

  it("delivers bulk teacher-rate changes as global lesson invalidations without financial writes", async () => {
    const event = {
      eventId: "event-rate", type: "crm.lesson_teacher_rate.changed",
      occurredAt: new Date(), aggregateType: "schedule:teacher-rate-bulk",
      aggregateId: "global", aggregateVersion: 4, requestId: "request-rate",
      payload: { action: "bulk_set" }, attempts: 1,
    };
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue([event]),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn().mockResolvedValue("retry"),
    };
    const realtime = {
      isReady: () => true, emitCrmChanged: jest.fn(), emitFinanceChanged: jest.fn(),
    };
    const notifications = { notifyLessonChanged: jest.fn(), notifyInboundLead: jest.fn() };
    const database = emptyDatabase();
    const worker = new PlatformOutboxWorker(integrity as never, realtime as never,
      notifications as never, database as never);
    await expect(worker.runOnce("worker-rate")).resolves.toEqual({
      claimed: 1, published: 1, retry: 0, deadLetter: 0,
    });
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "lesson", action: "updated", id: null, branchId: null, affectedUserIds: [],
    });
    expect(realtime.emitFinanceChanged).not.toHaveBeenCalled();
    expect(notifications.notifyLessonChanged).not.toHaveBeenCalled();
    expect(notifications.notifyInboundLead).not.toHaveBeenCalled();
    expect(database.query).not.toHaveBeenCalled();
    expect(integrity.markOutboxFailed).not.toHaveBeenCalled();
    expect(integrity.markOutboxPublished).toHaveBeenCalledWith("event-rate", "worker-rate");
  });

  it("publishes known invalidations and retries unknown events", async () => {
    const events = [
      {
        eventId: "event-subscription",
        type: "commerce.subscription.changed",
        occurredAt: new Date(),
        aggregateType: "commerce:issued-subscription",
        aggregateId: "subscription-a",
        aggregateVersion: 2,
        requestId: "request-a",
        payload: { entityId: "subscription-a" },
        attempts: 1,
      },
      {
        eventId: "event-access",
        type: "access.invalidated",
        occurredAt: new Date(),
        aggregateType: "access:user",
        aggregateId: "user-a",
        aggregateVersion: 7,
        requestId: "request-b",
        payload: { entityId: "user-a" },
        attempts: 1,
      },
      {
        eventId: "event-unknown",
        type: "unknown.changed",
        occurredAt: new Date(),
        aggregateType: "unknown",
        aggregateId: "unknown-a",
        aggregateVersion: 1,
        requestId: "request-c",
        payload: {},
        attempts: 1,
      },
    ];
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue(events),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn().mockResolvedValue("retry"),
    };
    const realtime = {
      isReady: jest.fn().mockReturnValue(true),
      emitFinanceChanged: jest.fn(),
      emitCrmChanged: jest.fn(),
      emitUserAccessInvalidated: jest.fn(),
      emitRoleAccessInvalidated: jest.fn(),
    };
    const notifications = { notifyInboundLead: jest.fn() };
    const worker = new PlatformOutboxWorker(
      integrity as never,
      realtime as never,
      notifications as never,
      emptyDatabase() as never,
    );

    await expect(worker.runOnce("worker-a")).resolves.toEqual({
      claimed: 3,
      published: 2,
      retry: 1,
      deadLetter: 0,
    });
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith([]);
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith(
      expect.objectContaining({
        entity: "subscription",
        action: "updated",
        id: "subscription-a",
      }),
    );
    expect(realtime.emitUserAccessInvalidated).toHaveBeenCalledWith(
      "user-a",
      7,
    );
    expect(integrity.markOutboxPublished).toHaveBeenCalledTimes(2);
    expect(integrity.markOutboxFailed).toHaveBeenCalledWith(
      events[2],
      "worker-a",
      expect.any(Error),
    );
  });

  it("materializes an inbound Lead notification before publishing its event", async () => {
    const event = {
      eventId: "event-inbound",
      type: "inbound.lead.created",
      occurredAt: new Date(),
      aggregateType: "inbound_lead_ingestion",
      aggregateId: "ingestion-a",
      aggregateVersion: 1,
      requestId: "request-a",
      payload: {},
      attempts: 1,
    };
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue([event]),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn(),
    };
    const realtime = {
      isReady: jest.fn().mockReturnValue(true),
      emitCrmChanged: jest.fn(),
    };
    const notifications = {
      notifyInboundLead: jest.fn().mockResolvedValue(undefined),
    };
    const worker = new PlatformOutboxWorker(
      integrity as never,
      realtime as never,
      notifications as never,
      emptyDatabase() as never,
    );

    await expect(worker.runOnce("worker-a")).resolves.toMatchObject({
      published: 1,
    });

    expect(notifications.notifyInboundLead).toHaveBeenCalledWith(
      "ingestion-a",
      "event-inbound",
    );
    expect(
      notifications.notifyInboundLead.mock.invocationCallOrder[0],
    ).toBeLessThan(integrity.markOutboxPublished.mock.invocationCallOrder[0]);
  });

  it("publishes organization lifecycle invalidations", async () => {
    const events = [
      [
        "organization.branch.changed",
        "organization:branch",
        "branch",
        "branch-a",
      ],
      ["organization.room.changed", "organization:room", "room", "room-a"],
      ["organization.group.changed", "organization:group", "group", "group-a"],
      [
        "organization.person.changed",
        "organization:teacher",
        "user",
        "teacher-a",
      ],
    ].map(([type, aggregateType, _entity, aggregateId], index) => ({
      eventId: `event-organization-${index}`,
      type,
      occurredAt: new Date(),
      aggregateType,
      aggregateId,
      aggregateVersion: 2,
      requestId: `request-organization-${index}`,
      payload: { entityId: aggregateId, action: "archived" },
      attempts: 1,
    }));
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue(events),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn(),
    };
    const realtime = {
      isReady: jest.fn().mockReturnValue(true),
      emitCrmChanged: jest.fn(),
    };
    const worker = new PlatformOutboxWorker(
      integrity as never,
      realtime as never,
      { notifyInboundLead: jest.fn() } as never,
      emptyDatabase() as never,
    );

    await expect(worker.runOnce("worker-a")).resolves.toEqual({
      claimed: 4,
      published: 4,
      retry: 0,
      deadLetter: 0,
    });
    expect(
      realtime.emitCrmChanged.mock.calls.map(([payload]) => payload),
    ).toEqual([
      expect.objectContaining({ entity: "branch", id: "branch-a" }),
      expect.objectContaining({ entity: "room", id: "room-a" }),
      expect.objectContaining({ entity: "group", id: "group-a" }),
      expect.objectContaining({ entity: "user", id: "teacher-a" }),
    ]);
    expect(integrity.markOutboxFailed).not.toHaveBeenCalled();
  });

  it("materializes a durable lesson reschedule before publishing its event", async () => {
    const event = {
      eventId: "11111111-1111-4111-8111-111111111111",
      type: "schedule.lesson.changed",
      occurredAt: new Date(),
      aggregateType: "schedule:lesson",
      aggregateId: "lesson-source",
      aggregateVersion: 2,
      requestId: "request-a",
      payload: {
        entityId: "lesson-source",
        action: "rescheduled",
        state: "rescheduled",
        successorId: "lesson-successor",
      },
      attempts: 1,
    };
    const technicalRefresh = {
      ...event,
      eventId: "22222222-2222-4222-8222-222222222222",
      payload: {
        entityId: "lesson-source",
        state: "rescheduled",
      },
    };
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue([event, technicalRefresh]),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn(),
    };
    const realtime = {
      isReady: jest.fn().mockReturnValue(true),
      emitCrmChanged: jest.fn(),
    };
    const notifications = {
      notifyLessonChanged: jest.fn().mockResolvedValue(undefined),
    };
    const worker = new PlatformOutboxWorker(
      integrity as never,
      realtime as never,
      notifications as never,
      emptyDatabase() as never,
    );

    await expect(worker.runOnce("worker-a")).resolves.toMatchObject({
      published: 2,
    });

    expect(notifications.notifyLessonChanged).toHaveBeenCalledWith({
      eventId: event.eventId,
      lessonId: "lesson-source",
      action: "rescheduled",
      successorId: "lesson-successor",
    });
    expect(notifications.notifyLessonChanged).toHaveBeenCalledTimes(1);
    expect(
      notifications.notifyLessonChanged.mock.invocationCallOrder[0],
    ).toBeLessThan(integrity.markOutboxPublished.mock.invocationCallOrder[0]);
  });

  it("keeps an event pending until realtime is ready", async () => {
    const event = {
      eventId: "event-task",
      type: "workflow.task.changed",
      occurredAt: new Date(),
      aggregateType: "workflow:task",
      aggregateId: "task-a",
      aggregateVersion: 1,
      requestId: "request-a",
      payload: {},
      attempts: 1,
    };
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue([event]),
      markOutboxPublished: jest.fn(),
      markOutboxFailed: jest.fn().mockResolvedValue("retry"),
    };
    const worker = new PlatformOutboxWorker(
      integrity as never,
      { isReady: () => false } as never,
      { notifyInboundLead: jest.fn() } as never,
      emptyDatabase() as never,
    );

    await expect(worker.runOnce("worker-a")).resolves.toMatchObject({
      published: 0,
      retry: 1,
    });
    expect(integrity.markOutboxPublished).not.toHaveBeenCalled();
  });

  it("targets recipient and payer Client accounts for commerce events", async () => {
    const event = {
      eventId: "event-payment",
      type: "commerce.payment-record.changed",
      occurredAt: new Date(),
      aggregateType: "commerce:client-payment",
      aggregateId: "payment-a",
      aggregateVersion: 1,
      requestId: "request-a",
      payload: { entityId: "payment-a" },
      attempts: 1,
    };
    const integrity = {
      claimOutbox: jest.fn().mockResolvedValue([event]),
      markOutboxPublished: jest.fn().mockResolvedValue(true),
      markOutboxFailed: jest.fn(),
    };
    const realtime = {
      isReady: jest.fn().mockReturnValue(true),
      emitFinanceChanged: jest.fn(),
      emitCrmChanged: jest.fn(),
    };
    const database = {
      query: jest.fn((sql: string, params: unknown[]) => {
        if (sql.includes("app.client_payment_records")) {
          expect(params).toEqual(["payment-a"]);
          return Promise.resolve({
            rows: [
              { student_id: "student-recipient" },
              { student_id: "student-payer" },
            ],
          });
        }
        if (sql.includes("recipient.role")) {
          return Promise.resolve({
            rows: [
              {
                user_id:
                  params[0] === "student-recipient"
                    ? "client-recipient"
                    : "client-payer",
              },
            ],
          });
        }
        throw new Error("Unexpected finance audience query");
      }),
    };
    const worker = new PlatformOutboxWorker(
      integrity as never,
      realtime as never,
      { notifyInboundLead: jest.fn() } as never,
      database as never,
    );

    await expect(worker.runOnce("worker-a")).resolves.toMatchObject({
      published: 1,
    });
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith([
      "client-recipient",
      "client-payer",
    ]);
  });
});
