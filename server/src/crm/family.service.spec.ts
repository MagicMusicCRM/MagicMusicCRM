import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { FamilyService } from "./family.service";

describe("FamilyService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanWriteCrm: jest.fn(),
      assertCanReadOperationalData: jest.fn(),
    };
    const service = new FamilyService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
      audit as unknown as AuditService,
    );
    return { service, query, audit, policy };
  };

  it("creates a family", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "fam-1", name: "Ивановы", branch_id: "b1" }] },
    ]);
    const result = await service.createFamily(actor, { name: "Ивановы", branchId: "b1" });
    expect(result).toEqual({ id: "fam-1", name: "Ивановы", branchId: "b1" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.families");
    expect(query.mock.calls[0][0]).toContain("select $1, $2::uuid");
    expect(query.mock.calls[0][0]).toContain("app.staff_branch_assignments");
    expect(query.mock.calls[0][1]).toEqual(["Ивановы", "b1", actor.userId]);
  });

  it("returns a family with members and resolved names for an entity", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ family_id: "fam-1", name: "Ивановы", branch_id: "b1", primary_payer_member_id: null }] }, // family lookup
      {
        rows: [
          { id: "m1", entity_type: "student", entity_id: "s1", role: "child", is_primary_contact: false, member_name: "Петя Иванов" },
          { id: "m2", entity_type: "profile", entity_id: "p1", role: "parent", is_primary_contact: true, member_name: "Иван Иванов" },
        ],
      }, // members
    ]);
    const result = await service.getFamilyForEntity(actor, "student", "s1");
    expect(result.family).toEqual({ id: "fam-1", name: "Ивановы", branchId: "b1", primaryPayerMemberId: null });
    expect(result.members).toEqual([
      { id: "m1", entityType: "student", entityId: "s1", role: "child", isPrimaryContact: false, name: "Петя Иванов" },
      { id: "m2", entityType: "profile", entityId: "p1", role: "parent", isPrimaryContact: true, name: "Иван Иванов" },
    ]);
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.staff_branch_assignments");
    expect(query.mock.calls[0][1]).toEqual(["student", "s1", actor.userId]);
    expect(query.mock.calls[1][1]).toEqual(["fam-1", actor.userId]);
  });

  it("setPrimaryPayer enforces member-in-family and 404s on no match", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [], rowCount: 0 } as unknown as { rows: Record<string, unknown>[] },
    ]);
    await expect(
      service.setPrimaryPayer(actor, "fam-1", "other-fam-member"),
    ).rejects.toThrow("Семья или участник не найдены.");
    expect(query.mock.calls[0][0]).toContain("from app.family_members m");
    expect(query.mock.calls[0][0]).toContain("m.family_id = $1");
    expect(query.mock.calls[0][0]).toContain("app.staff_branch_assignments");
  });

  it("setPrimaryPayer succeeds when the member belongs to the family", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [], rowCount: 1 } as unknown as { rows: Record<string, unknown>[] },
    ]);
    await expect(service.setPrimaryPayer(actor, "fam-1", "m1")).resolves.toEqual({ success: true });
  });

  it("removeFamilyMember 404s when nothing was deleted", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [], rowCount: 0 } as unknown as { rows: Record<string, unknown>[] },
    ]);
    await expect(service.removeFamilyMember(actor, "missing")).rejects.toThrow("Участник семьи не найден.");
  });

  it("clears the payer reference before removing the current primary payer", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [{ member_id: "fm-1", is_primary_payer: true, removed_id: "fm-1" }],
      },
    ]);
    await expect(service.removeFamilyMember(actor, "fm-1")).resolves.toEqual({
      success: true,
    });
  });

  it("returns 404 when an entity belongs to a family outside actor scope", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [] },
      { rows: [{ exists: true }] },
    ]);
    await expect(
      service.getFamilyForEntity(actor, "lead", "foreign-lead"),
    ).rejects.toThrow("Семья не найдена.");
  });

  it("rejects a missing or cross-branch family member target", async () => {
    const { service, query, audit } = createServiceWithQueryResults([{ rows: [] }]);
    await expect(
      service.addFamilyMember(actor, "fam-1", {
        entityType: "student",
        entityId: "missing",
        role: "child",
      }),
    ).rejects.toThrow("Семья или участник не найдены в доступном филиале.");
    expect(query.mock.calls[0][0]).toContain("app.students target");
    expect(query.mock.calls[0][0]).toContain("app.staff_branch_assignments");
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("audits adding a family member", async () => {
    const { service, audit } = createServiceWithQueryResults([
      {
        rows: [
          { id: "fm-1", family_id: "fam-1", entity_type: "student", entity_id: "st-1", role: "child" },
        ],
      },
    ]);
    await service.addFamilyMember(actor, "fam-1", {
      entityType: "student",
      entityId: "st-1",
      role: "child",
    });
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.family_member_added", entityId: "fam-1" }),
    );
  });

  it("audits removing a family member", async () => {
    const { service, audit } = createServiceWithQueryResults([
      { rows: [{ member_id: "fm-1", is_primary_payer: false, removed_id: "fm-1" }] },
    ]);
    await service.removeFamilyMember(actor, "fm-1");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.family_member_removed", entityId: "fm-1" }),
    );
  });

  it("audits setting the primary payer", async () => {
    const { service, audit } = createServiceWithQueryResults([
      { rows: [], rowCount: 1 } as unknown as { rows: Record<string, unknown>[] },
    ]);
    await service.setPrimaryPayer(actor, "fam-1", "fm-1");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.family_primary_payer_set", entityId: "fam-1" }),
    );
  });
});
