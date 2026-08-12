import { PlatformOutboxWorker } from "./platform-outbox.worker";

describe("PlatformOutboxWorker", () => {
  const emptyDatabase = () => ({
    query: jest.fn().mockResolvedValue({ rows: [] }),
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
