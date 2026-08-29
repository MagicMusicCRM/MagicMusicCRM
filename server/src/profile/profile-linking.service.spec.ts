import { BadRequestException, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { ProfilePolicy } from "./profile.policy";
import { ProfileLinkingService } from "./profile-linking.service";

describe("ProfileLinkingService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = { assertCanListProfiles: jest.fn() };
    const service = new ProfileLinkingService(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as ProfilePolicy,
    );
    return { service, query, audit, policy };
  };

  const profileRow = {
    id: "profile-a",
    user_id: "user-a",
    phone: "+7 999 111-22-33",
  };

  const clientProfileRow = {
    ...profileRow,
    role: "client" as const,
  };

  it("404s when the profile does not exist", async () => {
    const { service } = createServiceWithQueryResults([{ rows: [] }]);
    await expect(
      service.listLinkCandidates(actor, "missing"),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it("lists candidates across all four entity types, phone-matched", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [profileRow] }, // findById
      { rows: [{ id: "s1", entity_type: "student", first_name: "Аня", last_name: null, phone: null, email: null, status: "active", created_at: "2026-06-01" }] },
      { rows: [] }, // leads
      { rows: [] }, // teachers
      { rows: [] }, // staff
    ]);
    const result = await service.listLinkCandidates(actor, "profile-a");
    expect(policy.assertCanListProfiles).toHaveBeenCalledWith(actor);
    expect(result.students[0]).toMatchObject({ id: "s1", entityType: "student", firstName: "Аня" });
    expect(result.leads).toEqual([]);
    // candidate queries bind the normalized +7 phone.
    expect(query.mock.calls[1][1]).toContain("+79991112233");
  });

  it("linkCrmEntity dispatches student → updates students.profile_id + inserts link + audits", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [profileRow] }, // findById
      { rows: [{ id: "student-1" }] }, // candidate check
      { rows: [{ id: "student-1" }] }, // merge + assign Student profile
      { rows: [] }, // insertCrmLink
      { rows: [{}] }, // linkSummary
    ]);
    await service.linkCrmEntity(actor, "profile-a", {
      entityType: "student",
      entityId: "student-1",
    } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("update app.students");
    expect(sql).toContain("version = student.version + 1");
    expect(sql).toContain("insert into app.user_crm_links");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "profile.crm_student_linked", entityId: "profile-a" }),
    );
  });

  it("linkCrmEntity rejects a student whose phone does not match", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [profileRow] }, // findById
      { rows: [] }, // candidate check → none
    ]);
    await expect(
      service.linkCrmEntity(actor, "profile-a", {
        entityType: "student",
        entityId: "student-x",
      } as never),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("autoLinkByPhone returns the summary without linking when the profile has no phone", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ id: "profile-a", user_id: "user-a", phone: null }] }, // findById
      { rows: [{}] }, // linkSummary
    ]);
    const result = await service.autoLinkByPhone(actor, "profile-a");
    expect(result).toBeDefined();
    // Only findById + linkSummary ran — no candidate/link queries.
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("autoLinkByPhone does not guess between multiple matching students for a client", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [clientProfileRow] },
      {
        rows: [
          { id: "student-a", entity_type: "student", created_at: "2026-06-02" },
          { id: "student-b", entity_type: "student", created_at: "2026-06-01" },
        ],
      },
      { rows: [{}] }, // link summary
    ]);

    await service.autoLinkByPhone(actor, "profile-a");

    const decisionSql = query.mock.calls
      .slice(0, -1)
      .map((call: unknown[]) => String(call[0]))
      .join("\n");
    expect(decisionSql).not.toContain("update app.students");
    expect(decisionSql).not.toContain("insert into app.user_crm_links");
    expect(decisionSql).not.toContain("from app.leads l");
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("autoLinkByPhone links the one matching student and stops before Lead/Staff lookup", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [clientProfileRow] },
      {
        rows: [
          { id: "student-a", entity_type: "student", created_at: "2026-06-02" },
        ],
      },
      { rows: [{ id: "student-a" }] }, // candidate recheck
      { rows: [{ id: "student-a" }] }, // merge + assign Student profile
      { rows: [] }, // insert link
      { rows: [{}] }, // link summary
    ]);

    await service.autoLinkByPhone(actor, "profile-a");

    const decisionSql = query.mock.calls
      .slice(0, -1)
      .map((call: unknown[]) => String(call[0]))
      .join("\n");
    expect(decisionSql).toContain("update app.students");
    expect(decisionSql).not.toContain("from app.leads l");
    expect(decisionSql).not.toContain("from app.teachers t");
    expect(decisionSql).not.toContain("from app.staff_members sm");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "profile.crm_student_linked",
        entityId: "profile-a",
      }),
    );
  });
});
