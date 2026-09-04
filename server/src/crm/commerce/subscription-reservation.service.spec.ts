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
});
