import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { DuplicatesService } from "./duplicates.service";

describe("DuplicatesService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = { assertCanWriteCrm: jest.fn() };
    const service = new DuplicatesService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
      audit as unknown as AuditService,
    );
    return { service, query, audit, policy };
  };

  it("lists and decides duplicate candidates with safe lead-student attach", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "duplicate-a",
            entity_type_a: "lead",
            entity_id_a: "lead-a",
            entity_type_b: "student",
            entity_id_b: "student-a",
            match_type: "lead_student_phone",
            match_value: "+79990000000",
            confidence: "0.9500",
            source: "computed",
            status: "pending",
            decided_at: null,
            decided_by: null,
            decision_notes: null,
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
            entity_a_name: "Анна Лид",
            entity_b_name: "Анна Иванова",
            entity_a_phone: "+79990000000",
            entity_b_phone: "+79990000000",
            entity_a_email: null,
            entity_b_email: "anna@example.com",
          },
        ],
      },
      {
        rows: [
          {
            id: "duplicate-a",
            entity_type_a: "lead",
            entity_id_a: "lead-a",
            entity_type_b: "student",
            entity_id_b: "student-a",
            match_type: "lead_student_phone",
            match_value: "+79990000000",
            confidence: "0.9500",
            source: "computed",
            status: "pending",
            decided_at: null,
            decided_by: null,
            decision_notes: null,
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
            entity_a_name: null,
            entity_b_name: null,
            entity_a_phone: null,
            entity_b_phone: null,
            entity_a_email: null,
            entity_b_email: null,
          },
        ],
      },
      { rows: [{ id: "student-a" }] },
      {
        rows: [
          {
            id: "duplicate-a",
            entity_type_a: "lead",
            entity_id_a: "lead-a",
            entity_type_b: "student",
            entity_id_b: "student-a",
            match_type: "lead_student_phone",
            match_value: "+79990000000",
            confidence: "0.9500",
            source: "computed",
            status: "attached",
            decided_at: "2026-06-12T01:00:00.000Z",
            decided_by: "manager-a",
            decision_notes: "Та же семья",
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T01:00:00.000Z",
            entity_a_name: null,
            entity_b_name: null,
            entity_a_phone: null,
            entity_b_phone: null,
            entity_a_email: null,
            entity_b_email: null,
          },
        ],
      },
    ]);

    await expect(
      service.listDuplicateCandidates(actor, { leadId: "lead-a", limit: 10 }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "duplicate-a",
          status: "pending",
          matchType: "lead_student_phone",
          entityA: expect.objectContaining({ name: "Анна Лид" }),
        }),
      ],
    });
    await expect(
      service.decideDuplicateCandidate(actor, "duplicate-a", {
        status: "attached",
        notes: "Та же семья",
      }),
    ).resolves.toEqual(
      expect.objectContaining({
        id: "duplicate-a",
        status: "attached",
        decisionNotes: "Та же семья",
      }),
    );

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["pending", "lead-a", 10]);
    expect(query.mock.calls[2][1]).toEqual(["student-a", "lead-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.duplicate_candidate_decided",
        entityId: "duplicate-a",
      }),
    );
  });
});
