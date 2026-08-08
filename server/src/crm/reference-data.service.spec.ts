import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { ReferenceDataService } from "./reference-data.service";

describe("ReferenceDataService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    return build(query);
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    return build(query);
  };

  const build = (query: jest.Mock) => {
    const database = {
      query,
      // reorderLeadStatuses wraps its writes in a transaction; the callback
      // shares the same query mock so the mockResolvedValueOnce chain still lines up.
      transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanManageSystemSettings: jest.fn(),
    };
    const hollihop = {
      listDisciplines: jest
        .fn()
        .mockResolvedValue({ configured: false, items: [] }),
      listLevels: jest.fn().mockResolvedValue({ configured: false, items: [] }),
      listCategories: jest
        .fn()
        .mockResolvedValue({ configured: false, items: [] }),
      listLeadStatuses: jest
        .fn()
        .mockResolvedValue({ configured: false, items: [] }),
    };

    const service = new ReferenceDataService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      hollihop as unknown as HolliHopMetadataService,
    );

    return { service, query, audit, policy, hollihop };
  };

  it("restricts lead statuses to CRM writers", async () => {
    const { service, policy } = createService([
      {
        id: "status-a",
        name: "Новый",
        sort_order: 1,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listLeadStatuses(actor, { limit: 10 }),
    ).resolves.toEqual({
      items: [
        {
          id: "status-a",
          name: "Новый",
          sortOrder: 1,
          createdAt: "2026-06-12T00:00:00.000Z",
          requiresReason: false,
          isTerminal: false,
        },
      ],
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
  });

  it("exposes requiresReason/isTerminal on lead statuses (P3-7)", async () => {
    const { service } = createService([
      {
        id: "status-lost",
        name: "Потерян",
        sort_order: 9,
        created_at: "2026-06-12T00:00:00.000Z",
        color: "#E53935",
        requires_reason: true,
        is_terminal: true,
      },
    ]);
    const result = await service.listLeadStatuses(actor, { limit: 10 });
    expect(result.items[0]).toMatchObject({
      id: "status-lost",
      requiresReason: true,
      isTerminal: true,
    });
  });

  it("lists active loss reasons ordered by sort_order", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "r1", name: "Дорого", kind: "lost", sort_order: 1, color: null }] },
    ]);
    const result = await service.listLossReasons(actor);
    expect(result.items[0]).toEqual({ id: "r1", name: "Дорого", kind: "lost", sortOrder: 1, color: null });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_loss_reasons");
    expect(query.mock.calls[0][0]).toContain("is_active");
  });

  it("lists branch disciplines ordered for a branch", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "bd1", discipline_id: "d1", name: "Вокал", sort_order: 0 }] },
    ]);
    const result = await service.listBranchDisciplines(actor, "branch-1");
    expect(result.items[0]).toEqual({ id: "bd1", disciplineId: "d1", name: "Вокал", sortOrder: 0 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.branch_disciplines");
    expect(query.mock.calls[0][1]).toEqual(["branch-1"]);
    expect(query.mock.calls[0][0]).toContain("d.is_active");
  });

  it("proxies HolliHop metadata through CRM write policy", async () => {
    const { service, policy, hollihop } = createService();
    hollihop.listDisciplines.mockResolvedValueOnce({
      configured: true,
      items: ["Вокал"],
    });
    hollihop.listLevels.mockResolvedValueOnce({
      configured: true,
      items: ["Начальный"],
    });
    hollihop.listCategories.mockResolvedValueOnce({
      configured: true,
      items: ["Взрослые"],
    });
    hollihop.listLeadStatuses.mockResolvedValueOnce({
      configured: true,
      items: [{ externalId: "1", name: "Новый", color: null, sortOrder: 0 }],
    });

    await expect(service.listHolliHopDisciplines(actor)).resolves.toEqual({
      configured: true,
      items: ["Вокал"],
    });
    await expect(service.listHolliHopLevels(actor)).resolves.toEqual({
      configured: true,
      items: ["Начальный"],
    });
    await expect(service.listHolliHopCategories(actor)).resolves.toEqual({
      configured: true,
      items: ["Взрослые"],
    });
    await expect(service.listHolliHopLeadStatuses(actor)).resolves.toEqual({
      configured: true,
      items: [{ externalId: "1", name: "Новый", color: null, sortOrder: 0 }],
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledTimes(4);
  });

  it("creates a discipline", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "d9", name: "Скрипка" }] },
    ]);
    const result = await service.createDiscipline(actor, { name: "Скрипка" });
    expect(result).toEqual({ id: "d9", name: "Скрипка" });
    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.disciplines");
    expect(query.mock.calls[0][1]).toEqual(["Скрипка"]);
  });

  it("reorders branch disciplines by array position", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [], rowCount: 2 } as unknown as { rows: Record<string, unknown>[] },
    ]);
    const director = { userId: "director-a", role: "director" as const };
    const result = await service.reorderBranchDisciplines(director, "branch-1", {
      disciplineIds: ["d2", "d1"],
    });
    expect(result).toEqual({ updated: 2 });
    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledWith(director);
    expect(query.mock.calls[0][0]).toContain("with ordinality");
    expect(query.mock.calls[0][1]).toEqual(["branch-1", ["d2", "d1"]]);
  });

  it("assignBranchDiscipline upserts with conflict preservation and returns DTO", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "bd1", discipline_id: "d1", sort_order: 3 }] },
    ]);
    const director = { userId: "director-a", role: "director" as const };
    const result = await service.assignBranchDiscipline(director, "branch-1", {
      disciplineId: "d1",
    });
    expect(result).toEqual({ id: "bd1", disciplineId: "d1", sortOrder: 3 });
    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledWith(director);
    expect(query.mock.calls[0][0]).toContain("on conflict (branch_id, discipline_id)");
    expect(query.mock.calls[0][0]).toContain("deleted_at = null");
    expect(query.mock.calls[0][1]).toEqual(["branch-1", "d1", null]);
  });

  it("createLossReason inserts with default kind and sortOrder", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "lr1", name: "Тест", kind: "lost", sort_order: 0 }] },
    ]);
    const result = await service.createLossReason(actor, { name: "Тест" });
    expect(result).toEqual({ id: "lr1", name: "Тест", kind: "lost", sortOrder: 0 });
    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.lead_loss_reasons");
    expect(query.mock.calls[0][1]).toEqual(["Тест", "lost", 0]);
  });
});
