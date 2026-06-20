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

  it("debts buckets overdue payments in fixed order with zero-fill, gated to manager/admin", async () => {
    const query = jest.fn()
      .mockResolvedValueOnce({ rows: [
        { bucket: "0-7", students: "5", amount: "50000" },
        { bucket: "30+", students: "2", amount: "30000" },
      ] })
      .mockResolvedValueOnce({ rows: [{ distinct_students: "6" }] });
    const policy = { assertCanReadOperationalData: jest.fn(), assertCanWriteCrm: jest.fn() };
    const crm = {} as unknown as CrmService;
    const service = new AnalyticsService(
      { query } as unknown as DatabaseService,
      crm,
      policy as unknown as CrmPolicy,
    );
    const result = await service.debts(actor, {});
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.expected_payments");
    expect(result.buckets).toEqual([
      { bucket: "0-7", students: 5, amount: 50000 },
      { bucket: "8-14", students: 0, amount: 0 },
      { bucket: "15-30", students: 0, amount: 0 },
      { bucket: "30+", students: 2, amount: 30000 },
    ]);
    expect(result.bucketStudentSum).toBe(7);
    expect(result.distinctStudents).toBe(6);
    expect(result.totalAmount).toBe(80000);
  });

  it("revenueForecast sums unpaid payments due within 7/14/30 days, gated", async () => {
    const { service, query, policy } = build([{ next7: "10000", next14: "25000", next30: "60000" }]);
    const result = await service.revenueForecast(actor, {});
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.expected_payments");
    expect(result).toEqual({ next7: 10000, next14: 25000, next30: 60000 });
  });

  it("churnRisk lists active students with no recent completed lesson, gated", async () => {
    const { service, query, policy } = build([
      { student_id: "stu1", name: "Иван Петров", last_completed_at: "2026-03-01T10:00:00Z", days_since_last: "40", total_at_risk: "250" },
      { student_id: "stu2", name: "Без занятий", last_completed_at: null, days_since_last: null, total_at_risk: "250" },
    ]);
    const result = await service.churnRisk(actor, { inactiveDays: 30 });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.lessons");
    expect(sql).toContain("lesson_participation");
    expect(result.inactiveDays).toBe(30);
    expect(result.totalAtRisk).toBe(250);
    expect(result.students).toEqual([
      { studentId: "stu1", name: "Иван Петров", lastCompletedAt: "2026-03-01T10:00:00Z", daysSinceLast: 40 },
      { studentId: "stu2", name: "Без занятий", lastCompletedAt: null, daysSinceLast: null },
    ]);
  });

  it("chatsSla computes first-response stats over administration chats, gated", async () => {
    const { service, query, policy } = build([
      {
        inbound_count: "10",
        responded_count: "8",
        avg_minutes: "12.5",
        median_minutes: "9",
        p90_minutes: "30",
      },
    ]);
    const result = await service.chatsSla(actor, { from: "2026-06-01", to: "2026-06-08" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("'administration'");
    expect(sql).toContain("percentile_cont");
    expect(result).toEqual({
      from: "2026-06-01",
      to: "2026-06-08",
      inboundCount: 10,
      respondedCount: 8,
      responseRate: 0.8,
      avgMinutes: 12.5,
      medianMinutes: 9,
      p90Minutes: 30,
    });
  });

  it("weeklyReport composes the sub-reports over a 7-day window, gated", async () => {
    const { service, policy } = build([]);
    jest.spyOn(service, "funnel").mockResolvedValue({ from: "x", to: "y", stages: ["F"] } as never);
    jest.spyOn(service, "debts").mockResolvedValue({ buckets: ["D"] } as never);
    jest.spyOn(service, "revenueForecast").mockResolvedValue({ next7: 1, next14: 2, next30: 3 } as never);
    jest.spyOn(service, "churnRisk").mockResolvedValue({ inactiveDays: 21, students: [{}], totalAtRisk: 42 } as never);
    jest.spyOn(service, "branchComparison").mockResolvedValue({ branches: ["B"] } as never);
    jest.spyOn(service, "lossReasons").mockResolvedValue({ reasons: ["L"], unspecifiedCount: 3 } as never);
    jest.spyOn(service, "chatsSla").mockResolvedValue({ avgMinutes: 5 } as never);

    const result = await service.weeklyReport(actor, {});

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(result.funnel).toEqual({ from: "x", to: "y", stages: ["F"] });
    expect(result.debts).toEqual({ buckets: ["D"] });
    expect(result.forecast).toEqual({ next7: 1, next14: 2, next30: 3 });
    expect(result.churn).toEqual({ inactiveDays: 21, totalAtRisk: 42 }); // summary only, no student list
    expect(result.branches).toEqual({ branches: ["B"] });
    expect(result.lossReasons).toEqual({ reasons: ["L"], unspecifiedCount: 3 });
    expect(result.chatSla).toEqual({ avgMinutes: 5 });
    expect(result.window.from).toBeDefined();
    expect(result.window.to).toBeDefined();
  });

  it("weeklyReport degrades gracefully when one sub-report rejects (Promise.allSettled)", async () => {
    const { service } = build([]);
    jest.spyOn(service, "funnel").mockResolvedValue({ from: "x", to: "y", stages: ["F"] } as never);
    jest.spyOn(service, "debts").mockResolvedValue({ buckets: ["D"] } as never);
    jest.spyOn(service, "revenueForecast").mockResolvedValue({ next7: 1, next14: 2, next30: 3 } as never);
    jest.spyOn(service, "churnRisk").mockRejectedValue(new Error("boom"));
    jest.spyOn(service, "branchComparison").mockResolvedValue({ branches: ["B"] } as never);
    jest.spyOn(service, "lossReasons").mockResolvedValue({ reasons: ["L"], unspecifiedCount: 3 } as never);
    jest.spyOn(service, "chatsSla").mockResolvedValue({ avgMinutes: 5 } as never);

    const result = await service.weeklyReport(actor, {});

    expect(result.churn).toEqual({ error: "boom" });
    expect(result.funnel).toEqual({ from: "x", to: "y", stages: ["F"] });
    expect(result.debts).toEqual({ buckets: ["D"] });
    expect(result.forecast).toEqual({ next7: 1, next14: 2, next30: 3 });
    expect(result.branches).toEqual({ branches: ["B"] });
    expect(result.lossReasons).toEqual({ reasons: ["L"], unspecifiedCount: 3 });
    expect(result.chatSla).toEqual({ avgMinutes: 5 });
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

  it("sourceAnalytics groups new leads by source with display names + shares, gated", async () => {
    const { service, query, policy } = build([
      { source: "site", display_name: "Сайт", leads: "60" },
      { source: "ads", display_name: "Реклама", leads: "30" },
      { source: null, display_name: null, leads: "10" },
    ]);
    const result = await service.sourceAnalytics(actor, { from: "2026-01-01", to: "2026-04-01" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.leads");
    expect(sql).toContain("app.lead_sources");
    expect(result.from).toBe("2026-01-01");
    expect(result.to).toBe("2026-04-01");
    expect(result.total).toBe(100);
    expect(result.sources).toEqual([
      { source: "site", displayName: "Сайт", leads: 60, share: 60 },
      { source: "ads", displayName: "Реклама", leads: 30, share: 30 },
      { source: null, displayName: "(не указан)", leads: 10, share: 10 },
    ]);
  });
});
