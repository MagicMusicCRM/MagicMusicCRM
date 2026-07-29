import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { BranchesService } from "./branches.service";

describe("BranchesService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
    };
    const service = new BranchesService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, audit, policy };
  };

  it("lists branches through operational-data policy", async () => {
    const { service, query, policy } = createService([
      {
        id: "branch-a",
        name: "Центр",
        address: "Москва",
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listBranches(actor, { q: "центр", limit: 10 }),
    ).resolves.toEqual({
      items: [
        {
          id: "branch-a",
          name: "Центр",
          address: "Москва",
          // No utc_offset_minutes in the mock row → defaults to Moscow (180).
          utcOffsetMinutes: 180,
          timezone: "Europe/Moscow",
          scheduleReferenceVersion: 1,
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["центр", 10]);
  });

  it("updates a branch's utc offset and returns the dto", async () => {
    const { service, query, policy } = createService([
      {
        id: "branch-a",
        name: "Сокол",
        address: "Москва",
        utc_offset_minutes: 240,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);
    const result = await service.updateBranch(actor, "branch-a", {
      utcOffsetMinutes: 240,
    });
    expect(result).toMatchObject({
      id: "branch-a",
      name: "Сокол",
      utcOffsetMinutes: 240,
    });
    expect(policy.assertCanWriteCrm).toHaveBeenCalled();
    expect(query.mock.calls[0][0]).toContain("update app.branches");
    expect(query.mock.calls[0][1]).toEqual([
      "branch-a",
      null,
      null,
      240,
      null,
    ]);
  });

  it("creates a branch through CRM write policy and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "branch-b",
        name: "Сокол",
        address: "Москва, Сокол",
        utc_offset_minutes: 240,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createBranch(actor, {
        name: " Сокол ",
        address: " Москва, Сокол ",
        utcOffsetMinutes: 240,
      }),
    ).resolves.toEqual({
      id: "branch-b",
      name: "Сокол",
      address: "Москва, Сокол",
      utcOffsetMinutes: 240,
      timezone: "Europe/Moscow",
      scheduleReferenceVersion: 1,
      createdAt: "2026-06-12T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.branches");
    expect(query.mock.calls[0][1]).toEqual([
      "Сокол",
      "Москва, Сокол",
      240,
      null,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.branch_created",
        entityType: "branch",
        entityId: "branch-b",
        metadata: {
          utcOffsetMinutes: 240,
          timezone: "Europe/Moscow",
        },
      }),
    );
  });

  it("defaults a new branch to Moscow offset and null address when omitted", async () => {
    const { service, query } = createService([
      {
        id: "branch-c",
        name: "Новый",
        address: null,
        utc_offset_minutes: 180,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createBranch(actor, { name: "Новый" }),
    ).resolves.toMatchObject({
      id: "branch-c",
      name: "Новый",
      address: null,
      utcOffsetMinutes: 180,
    });

    expect(query.mock.calls[0][1]).toEqual(["Новый", null, 180, null]);
  });

  it("rejects branch creation when name is blank", async () => {
    const { service, query } = createService();

    await expect(
      service.createBranch(actor, { name: "   " }),
    ).rejects.toThrow("Название филиала обязательно.");
    expect(query).not.toHaveBeenCalled();
  });
});
