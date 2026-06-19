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
});
