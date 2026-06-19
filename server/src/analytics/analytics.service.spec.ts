import { AnalyticsService } from "./analytics.service";
import { DatabaseService } from "../db/database.service";
import { CrmService } from "../crm/crm.service";
import { CrmPolicy } from "../crm/crm.policy";

describe("AnalyticsService", () => {
  const actor = { userId: "u1", role: "manager" as const };
  const build = (rows: Record<string, unknown>[]) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const policy = { assertCanReadOperationalData: jest.fn(), assertCanWriteCrm: jest.fn() };
    const crm = {} as unknown as CrmService;
    const service = new AnalyticsService(
      { query } as unknown as DatabaseService,
      crm,
      policy as unknown as CrmPolicy,
    );
    return { service, query, policy };
  };

  it("reads finance monthly from the matview with a date filter", async () => {
    const { service, query, policy } = build([
      { month_start: "2026-06-01", lessons: 10, completed_lessons: 8, revenue: 5000, expenses: 1200, new_students: 3 },
    ]);
    const result = await service.financeMonthly(actor, { from: "2026-01-01", to: "2026-07-01" });
    expect(result.items[0]).toEqual({
      monthStart: "2026-06-01", lessons: 10, completedLessons: 8, revenue: 5000, expenses: 1200, newStudents: 3,
    });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.mv_finance_monthly");
  });

  it("renders finance monthly as RFC-4180 CSV with a header row", async () => {
    const { service } = build([
      { month_start: "2026-06-01", lessons: 10, completed_lessons: 8, revenue: 5000, expenses: 1200, new_students: 3 },
    ]);
    const csv = await service.financeMonthlyCsv(actor, {});
    const lines = csv.trim().split("\n");
    expect(lines[0]).toBe("month_start,lessons,completed_lessons,revenue,expenses,new_students");
    expect(lines[1]).toBe("2026-06-01,10,8,5000,1200,3");
  });

  it("funnel returns stage counts ordered by sort_order, gated to manager/admin", async () => {
    const { service, query, policy } = build([
      { status_id: "s1", name: "Новый", sort_order: 0, leads_entered: "100" },
      { status_id: "s2", name: "Пробный", sort_order: 1, leads_entered: "40" },
    ]);
    const result = await service.funnel(actor, { from: "2026-01-01", to: "2026-04-01" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_status_history");
    expect(result.from).toBe("2026-01-01");
    expect(result.to).toBe("2026-04-01");
    expect(result.stages).toEqual([
      { statusId: "s1", name: "Новый", sortOrder: 0, leadsEntered: 100, ratioToPrevStage: null },
      { statusId: "s2", name: "Пробный", sortOrder: 1, leadsEntered: 40, ratioToPrevStage: 40 },
    ]);
  });

  it("branchComparison returns per-branch metrics, gated to manager/admin", async () => {
    const { service, query, policy } = build([
      { branch_id: "b1", name: "Сокол", revenue: "500000", active_students: "120", new_leads: "30", completed_lessons: "800" },
    ]);
    const result = await service.branchComparison(actor, { from: "2026-01-01", to: "2026-04-01" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.branches");
    expect(result.from).toBe("2026-01-01");
    expect(result.to).toBe("2026-04-01");
    expect(result.branches).toEqual([
      { branchId: "b1", name: "Сокол", revenue: 500000, activeStudents: 120, newLeads: 30, completedLessons: 800 },
    ]);
  });

  it("lossReasons groups terminal-transition reasons, gated to manager/admin", async () => {
    const query = jest.fn()
      .mockResolvedValueOnce({ rows: [
        { reason_id: "r1", name: "Дорого", kind: "lost", leads: "25" },
        { reason_id: "r2", name: "Переезд", kind: "lost", leads: "10" },
      ] })
      .mockResolvedValueOnce({ rows: [{ unspecified: "5" }] });
    const policy = { assertCanReadOperationalData: jest.fn(), assertCanWriteCrm: jest.fn() };
    const crm = {} as unknown as CrmService;
    const service = new AnalyticsService(
      { query } as unknown as DatabaseService,
      crm,
      policy as unknown as CrmPolicy,
    );
    const result = await service.lossReasons(actor, { from: "2026-01-01", to: "2026-04-01" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.lead_status_history");
    expect(sql).toContain("is_terminal");
    expect(result.from).toBe("2026-01-01");
    expect(result.to).toBe("2026-04-01");
    expect(result.reasons).toEqual([
      { reasonId: "r1", name: "Дорого", kind: "lost", leads: 25 },
      { reasonId: "r2", name: "Переезд", kind: "lost", leads: 10 },
    ]);
    expect(result.unspecifiedCount).toBe(5);
  });
});
