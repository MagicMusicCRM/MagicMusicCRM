import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { PhoneReviewService } from "./phone-review.service";

describe("PhoneReviewService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const policy = { assertCanReadOperationalData: jest.fn() };
    const service = new PhoneReviewService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, policy };
  };

  it("counts open phone-review-queue rows", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ count: "55" }] },
    ]);
    const result = await service.countPhoneReviewQueue(actor);
    expect(result).toEqual({ count: 55 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.phone_review_queue");
    expect(query.mock.calls[0][0]).toContain("resolved_at is null");
  });

  it("lists open phone-review-queue rows", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "q1",
            entity_type: "lead",
            entity_id: "l1",
            raw_phone: "123",
            reason: "too_short",
            created_at: "2026-06-19T00:00:00.000Z",
          },
        ],
      },
    ]);
    const result = await service.listPhoneReviewQueue(actor, 25);
    expect(result.items[0]).toEqual({
      id: "q1",
      entityType: "lead",
      entityId: "l1",
      rawPhone: "123",
      reason: "too_short",
      createdAt: "2026-06-19T00:00:00.000Z",
    });
    expect(query.mock.calls[0][1]).toEqual([25]);
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.phone_review_queue");
    expect(query.mock.calls[0][0]).toContain("resolved_at is null");
  });
});
