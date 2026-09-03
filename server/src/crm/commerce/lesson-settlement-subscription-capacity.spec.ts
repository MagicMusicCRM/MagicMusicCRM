import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import type { CalculatedLessonClientFact } from "./lesson-settlement-facts.persistence";
import { assertCorrectionSubscriptionCapacity, reserveLessonSettlementSubscriptions } from "./lesson-settlement-subscription-capacity";

function queryResult<T extends QueryResultRow>(rows: T[]): QueryResult<T> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows,
  };
}

function fact(
  subscriptionId: string,
  clientId: string,
  units: string,
  payerStudentId: string | null = null,
): CalculatedLessonClientFact {
  return {
    charge: {
      client_type: "student",
      client_id: clientId,
      charge_type: "subscription",
      charge_value: "1",
      subscription_id: subscriptionId,
    },
    chargeType: "subscription",
    subscriptionId,
    payerStudentId,
    settlement: {
      stableKey: "completed",
      label: "Проведено",
      colorToken: "success",
      hourShareBasisPoints: 10_000,
      clientDurationMode: "full",
      teacherDurationMode: "full",
      defaultTeacherCompensationRuleKey: "standard",
      allowedContexts: ["settle"],
      active: true,
      order: 0,
    },
    calculation: { units, amountMinor: "0" },
  };
}

function errorResponse(error: unknown): unknown {
  if (error && typeof error === "object" && "getResponse" in error) {
    return (error as { getResponse(): unknown }).getResponse();
  }
  return error;
}

describe("lesson settlement subscription capacity", () => {
  it("checks the payer owner even when a correction consumes zero subscription units", async () => {
    const client = { query: async () => queryResult([{ student_id: "owner" }]) } as unknown as PoolClient;
    await expect(assertCorrectionSubscriptionCapacity(client, "lesson", [fact("subscription", "recipient", "0.00", "wrong-payer")])).rejects.toMatchObject({ response: { code: "SUBSCRIPTION_CAPACITY" } });
    await expect(assertCorrectionSubscriptionCapacity(client, "lesson", [fact("subscription", "recipient", "0.00", "owner")])).resolves.toBeUndefined();
  });

  it("rejects duplicate subscription selection before taking a row lock", async () => {
    let queryCount = 0;
    const client = {
      query: async () => {
        queryCount += 1;
        return queryResult([]);
      },
    } as unknown as PoolClient;

    let caught: unknown;
    try {
      await reserveLessonSettlementSubscriptions(client, "lesson-a", [
        fact("subscription-a", "student-a", "1.00"),
        fact("subscription-a", "student-b", "1.00"),
      ]);
    } catch (error) {
      caught = error;
    }
    expect(errorResponse(caught)).toEqual({
      code: "DUPLICATE_SUBSCRIPTION_SELECTION",
      field: "clientDecisions",
    });
    expect(queryCount).toBe(0);
  });

  it("locks subscriptions in ID order and skips reservation for zero units", async () => {
    const calls: Array<{ text: string; values?: unknown[] }> = [];
    const client = {
      query: async (text: string, values?: unknown[]) => {
        calls.push({ text, values });
        if (text.includes("from app.subscriptions")) {
          const subscriptionId = String(values?.[0]);
          return queryResult([
            {
              student_id:
                subscriptionId === "subscription-a"
                  ? "student-a"
                  : "student-b",
              is_usable: true,
              has_capacity: true,
              available_units: "10.00",
            },
          ]);
        }
        return queryResult([{ id: "reservation-a" }]);
      },
    } as unknown as PoolClient;

    await reserveLessonSettlementSubscriptions(client, "lesson-a", [
      fact("subscription-b", "student-b", "1.00"),
      fact("subscription-a", "student-a", "0.00"),
    ]);

    const lockIds = calls
      .filter((call) => call.text.includes("from app.subscriptions"))
      .map((call) => call.values?.[0]);
    expect(lockIds).toEqual(["subscription-a", "subscription-b"]);
    const reservations = calls.filter((call) =>
      call.text.includes("insert into app.lesson_reservations"),
    );
    expect(reservations).toHaveLength(1);
    expect(reservations[0]!.values?.[1]).toBe("subscription-b");
  });

  it("allows the explicitly selected payer to own the subscription", async () => {
    const client = {
      query: async (text: string) => {
        if (text.includes("from app.subscriptions")) {
          return queryResult([
            {
              student_id: "payer-a",
              is_usable: true,
              has_capacity: true,
              available_units: "3.00",
            },
          ]);
        }
        return queryResult([{ id: "reservation-a" }]);
      },
    } as unknown as PoolClient;

    await expect(
      reserveLessonSettlementSubscriptions(client, "lesson-a", [
        fact("subscription-a", "recipient-b", "1.00", "payer-a"),
      ]),
    ).resolves.toBeUndefined();
  });
});
