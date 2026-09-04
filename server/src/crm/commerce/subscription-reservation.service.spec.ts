import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import type { RealtimeBus } from "../../realtime/realtime-bus";
import { SubscriptionReservationService } from "./subscription-reservation.service";

describe("SubscriptionReservationService post-commit invalidation", () => {
  const lessonId = "11111111-1111-4111-8111-111111111111";
  const subscriptionId = "22222222-2222-4222-8222-222222222222";

  function createService(rows: Array<{
    student_id: string;
    subscription_id: string | null;
  }>) {
    const query = jest.fn(async (sql: string, params?: unknown[]) => {
      if (String(sql).includes("from app.lesson_client_charge_facts")) {
        return { rows };
      }
      const studentId = String(params?.[0]);
      return { rows: [{ user_id: `user-${studentId}` }] };
    });
    const realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    };
    const service = new SubscriptionReservationService(
      { query } as unknown as DatabaseService,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, realtime };
  }

  it("invalidates both lesson recipient and cross-payer subscription owner", async () => {
    const { service, query, realtime } = createService([
      { student_id: "recipient", subscription_id: subscriptionId },
      { student_id: "payer", subscription_id: subscriptionId },
    ]);

    await service.publishLessonSettlementPostCommit(lessonId);

    const projectionSql = String(query.mock.calls[0]?.[0]);
    expect(projectionSql).toContain("join app.subscriptions subscription");
    expect(projectionSql).toContain("subscription.student_id");
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "subscription",
      action: "updated",
      id: subscriptionId,
      affectedUserIds: ["user-recipient", "user-payer"],
    });
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith([
      "user-recipient",
      "user-payer",
    ]);
  });

  it("deduplicates same-payer recipients and their user invalidations", async () => {
    const { service, query, realtime } = createService([
      { student_id: "same", subscription_id: subscriptionId },
      { student_id: "same", subscription_id: subscriptionId },
    ]);

    await service.publishLessonSettlementPostCommit(lessonId);

    const clientLookups = query.mock.calls.filter((call) =>
      String(call[0]).includes("from app.students student"),
    );
    expect(clientLookups).toHaveLength(1);
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "subscription",
      action: "updated",
      id: subscriptionId,
      affectedUserIds: ["user-same"],
    });
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith(["user-same"]);
  });

  it("refreshes both old and new personal-account payers after an append-only correction", async () => {
    const { service, query, realtime } = createService([
      { student_id: "recipient", subscription_id: null },
      { student_id: "old-payer", subscription_id: null },
      { student_id: "new-payer", subscription_id: null },
    ]);
    await service.publishLessonSettlementPostCommit(lessonId);
    const projectionSql = String(query.mock.calls[0]?.[0]);
    expect(projectionSql).toContain("fact.payer_student_id");
    expect(projectionSql).not.toContain("lesson_client_charge_facts_effective");
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith([
      "user-recipient", "user-old-payer", "user-new-payer",
    ]);
    expect(realtime.emitCrmChanged).toHaveBeenCalledTimes(1);
  });

  it("transfers one active reservation to the successor without changing its id", async () => {
    const reservationId = "33333333-3333-4333-8333-333333333333";
    const successorLessonId = "44444444-4444-4444-8444-444444444444";
    const query = jest.fn(async (_sql: string, _params?: unknown[]) => ({
      rows: [{ id: reservationId }],
    }));
    const service = new SubscriptionReservationService(
      {} as DatabaseService,
      {} as RealtimeBus,
    );

    await expect(service.transferActiveReservation(
      { query } as unknown as PoolClient,
      {
        reservationId,
        sourceLessonId: lessonId,
        successorLessonId,
        subscriptionId,
        units: 0.5,
      },
    )).resolves.toBe(reservationId);

    expect(String(query.mock.calls[0]?.[0])).toContain(
      "state = 'reserved' and financial_fact_id is null",
    );
    expect(query.mock.calls[0]?.[1]).toEqual([
      reservationId,
      lessonId,
      successorLessonId,
      subscriptionId,
      0.5,
    ]);
  });

  it("reuses an unpaid cancellation unit while a paid cancellation consumes it once", async () => {
    const nextLessonId = "55555555-5555-4555-8555-555555555555";
    let reservationState: "reserved" | "released" | "consumed" = "reserved";
    let reservationLessonId = lessonId;
    let allocations = 0;
    const query = jest.fn(async (sql: string, params?: unknown[]) => {
      const normalized = sql.trim().replace(/\s+/g, " ").toLowerCase();
      if (normalized.startsWith("update app.lesson_reservations") &&
        normalized.includes("set state = 'consumed'")) {
        if (reservationState !== "reserved") return { rows: [], rowCount: 0 };
        reservationState = "consumed";
        return { rows: [], rowCount: 1 };
      }
      if (normalized.startsWith("update app.lesson_reservations") &&
        normalized.includes("set state = 'released'")) {
        if (reservationState !== "reserved") return { rows: [], rowCount: 0 };
        reservationState = "released";
        return { rows: [], rowCount: 1 };
      }
      if (normalized.includes("from app.subscriptions") &&
        normalized.includes("for update")) {
        return {
          rows: [{
            id: subscriptionId,
            student_id: "student-a",
            status: "active",
            lessons_total: "1",
            lessons_used: "0",
            starts_at: null,
            expires_at: null,
          }],
        };
      }
      if (normalized.startsWith("select exists")) {
        return { rows: [{ covered: true }] };
      }
      if (normalized.includes("as used_units") &&
        normalized.includes("as reserved_units")) {
        return {
          rows: [{
            used_units: "0",
            reserved_units: reservationState === "reserved" ? "1" : "0",
          }],
        };
      }
      if (normalized.startsWith("insert into app.lesson_reservations")) {
        allocations += 1;
        reservationLessonId = String(params?.[0]);
        reservationState = "reserved";
        return { rows: [{ id: "replacement-reservation" }] };
      }
      return { rows: [] };
    });
    const service = new SubscriptionReservationService(
      {} as DatabaseService,
      {} as RealtimeBus,
    );
    const client = { query } as unknown as PoolClient;

    await service.terminalize(client, {
      lessonId,
      clientFacts: [],
      clientFact: undefined as never,
      teacherFact: {} as never,
    });
    await service.allocate(client, {
      lessonId: nextLessonId,
      clientType: "student",
      clientId: "student-a",
      chargeType: "subscription",
      subscriptionId,
      units: 1,
    });

    expect(reservationState).toBe("reserved");
    expect(reservationLessonId).toBe(nextLessonId);

    const paidFact = {
      id: "paid-client-fact",
      chargeType: "subscription",
      subscriptionId,
      units: "1",
    };
    await service.terminalize(client, {
      lessonId: nextLessonId,
      clientFacts: [paidFact],
      clientFact: paidFact,
      teacherFact: {} as never,
    } as never);

    expect(reservationState).toBe("consumed");
    expect(allocations).toBe(1);
  });
});
