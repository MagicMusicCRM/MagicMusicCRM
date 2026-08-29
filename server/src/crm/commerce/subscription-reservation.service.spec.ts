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
      if (String(sql).includes("lesson_client_charge_facts_effective")) {
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
});
