import { BadRequestException, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { PhoneReviewService } from "./phone-review.service";

describe("PhoneReviewService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  function createService() {
    const query = jest.fn();
    const clientQuery = jest.fn();
    const transaction = jest.fn(async (work) =>
      work({ query: clientQuery } as never),
    );
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
    };
    const audit = { record: jest.fn() };
    const service = new PhoneReviewService(
      { query, transaction } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
      audit as unknown as AuditService,
    );
    return { service, query, clientQuery, transaction, policy, audit };
  }

  it("counts open phone-review-queue rows", async () => {
    const { service, query, policy } = createService();
    query.mockResolvedValueOnce({ rows: [{ count: "55" }] });

    await expect(service.countPhoneReviewQueue(actor)).resolves.toEqual({
      count: 55,
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.phone_review_queue");
    expect(query.mock.calls[0][0]).toContain("resolved_at is null");
  });

  it("lists open phone-review-queue rows", async () => {
    const { service, query, policy } = createService();
    query.mockResolvedValueOnce({
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
    });

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
  });

  it("corrects the source entity and resolves the queue row under one lock", async () => {
    const { service, clientQuery, policy, audit } = createService();
    clientQuery
      .mockResolvedValueOnce({
        rows: [{ id: "q1", entity_type: "lead", entity_id: "l1" }],
      })
      .mockResolvedValueOnce({ rows: [{ id: "l1" }], rowCount: 1 })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "q1",
            entity_type: "lead",
            entity_id: "l1",
            resolution_action: "corrected",
            resolution_note: "Исправлено по карточке клиента",
            resolved_phone: "+79991234567",
            resolved_at: "2026-08-12T10:00:00.000Z",
          },
        ],
      });

    await expect(
      service.resolvePhoneReview(actor, "q1", {
        action: "corrected",
        phone: "8 (999) 123-45-67",
        resolutionNote: " Исправлено по карточке клиента ",
      }),
    ).resolves.toEqual({
      id: "q1",
      action: "corrected",
      resolvedPhone: "+79991234567",
      resolvedAt: "2026-08-12T10:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(clientQuery.mock.calls[0][0]).toContain("for update");
    expect(clientQuery.mock.calls[1][0]).toContain("update app.leads");
    expect(clientQuery.mock.calls[1][1]).toEqual(["l1", "+79991234567"]);
    expect(clientQuery.mock.calls[2][1]).toEqual([
      "q1",
      actor.userId,
      "corrected",
      "Исправлено по карточке клиента",
      "+79991234567",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.phone_review_resolved",
        entityId: "q1",
        metadata: expect.objectContaining({ action: "corrected" }),
      }),
    );
  });

  it("accepts an intentional source value without changing the entity", async () => {
    const { service, clientQuery, audit } = createService();
    clientQuery
      .mockResolvedValueOnce({
        rows: [{ id: "q2", entity_type: "profile", entity_id: "p1" }],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "q2",
            entity_type: "profile",
            entity_id: "p1",
            resolution_action: "accepted_as_is",
            resolution_note: "Иностранный номер подтверждён",
            resolved_phone: null,
            resolved_at: "2026-08-12T10:00:00.000Z",
          },
        ],
      });

    await service.resolvePhoneReview(actor, "q2", {
      action: "accepted_as_is",
      resolutionNote: "Иностранный номер подтверждён",
    });

    expect(clientQuery).toHaveBeenCalledTimes(2);
    expect(
      clientQuery.mock.calls.some(([sql]) =>
        String(sql).includes("update app.profiles"),
      ),
    ).toBe(false);
    expect(audit.record).toHaveBeenCalledTimes(1);
  });

  it("rejects an invalid corrected number before opening a transaction", async () => {
    const { service, transaction, audit } = createService();

    await expect(
      service.resolvePhoneReview(actor, "q1", {
        action: "corrected",
        phone: "123",
        resolutionNote: "Попытка исправить",
      }),
    ).rejects.toThrow(BadRequestException);
    expect(transaction).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("does not resolve a missing or concurrently completed queue row", async () => {
    const { service, clientQuery, audit } = createService();
    clientQuery.mockResolvedValueOnce({ rows: [] });

    await expect(
      service.resolvePhoneReview(actor, "q1", {
        action: "accepted_as_is",
        resolutionNote: "Проверено",
      }),
    ).rejects.toThrow(NotFoundException);
    expect(clientQuery).toHaveBeenCalledTimes(1);
    expect(audit.record).not.toHaveBeenCalled();
  });
});
