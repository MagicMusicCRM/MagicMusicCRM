import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { DashboardService } from "./dashboard.service";

describe("DashboardService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const buildPolicy = () => ({
    assertManagerOnly: jest.fn(),
    assertCanReadSchoolFinance: jest.fn(),
    canReadSchoolFinance: jest.fn().mockReturnValue(true),
    assertCanWriteCrm: jest.fn(),
  });

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const policy = buildPolicy();
    const service = new DashboardService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, policy };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const policy = buildPolicy();
    const service = new DashboardService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, policy };
  };

  it("returns manager overview stats through CRM write policy", async () => {
    const { service, policy } = createService([
      {
        students_count: "12",
        teachers_count: "3",
        branches_count: "2",
        today_lessons_count: "5",
        month_completed_lessons_count: "18",
        open_tasks_count: "4",
        new_leads_count: "6",
        revenue_month: "125000.50",
      },
    ]);

    await expect(service.getOverview(actor)).resolves.toEqual({
      students: 12,
      teachers: 3,
      branches: 2,
      todayLessons: 5,
      monthCompletedLessons: 18,
      openTasks: 4,
      newLeads: 6,
      revenueMonth: 125000.5,
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
  });

  it("returns manager dashboard KPIs with period and branch filters", async () => {
    const { service, query, policy } = createService([
      {
        revenue: "120000.50",
        expected_payments: "35000.00",
        debt_students: "4",
        active_students: "120",
        new_leads: "18",
        open_tasks: "9",
        overdue_tasks: "3",
        trial_lessons: "7",
        schedule_issues: "2",
        room_load_lessons: "46",
        staff_activity: "31",
      },
    ]);

    await expect(
      service.getManagerDashboard(actor, {
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        branchId: "branch-a",
      }),
    ).resolves.toEqual({
      from: "2026-06-01T00:00:00.000Z",
      to: "2026-07-01T00:00:00.000Z",
      branchId: "branch-a",
      kpis: {
        revenue: 120000.5,
        expectedPayments: 35000,
        debtStudents: 4,
        activeStudents: 120,
        newLeads: 18,
        openTasks: 9,
        overdueTasks: 3,
        trialLessons: 7,
        scheduleIssues: 2,
        roomLoadLessons: 46,
        staffActivity: 31,
      },
      sources: {
        revenue: "/crm/reports/finance",
        expectedPayments: "/crm/expected-payments",
        debtStudents: "/crm/student-balances?debtOnly=true",
        newLeads: "/crm/leads/board",
        tasks: "/crm/tasks",
        schedule: "/crm/schedule/matrix",
        activity: "/crm/activity",
      },
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      "branch-a",
    ]);
    expect(String(query.mock.calls[0][0])).toContain("l.is_trial = false");
    expect(String(query.mock.calls[0][0])).toContain(
      "lp.attendance_kind = 'partially_paid'",
    );
    const overviewSql = String(query.mock.calls[0][0]);
    expect(overviewSql).toContain("coalesce(sub_pay.amount, pkg.price)");
    expect(overviewSql).toContain("/ nullif(sub.lessons_total, 0)");
    expect(overviewSql).toContain("* lp.charged_hours");
    expect(overviewSql).toContain(
      "group by coalesce(sub.student_id, l.student_id, lp.student_id)",
    );
  });

  it("returns finance report aggregates through CRM write policy", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            month_start: "2026-06-01T00:00:00.000Z",
            lessons_count: "4",
            completed_lessons_count: "3",
            new_students_count: "2",
            revenue: "12000.50",
            expenses: "3000.00",
          },
        ],
      },
      {
        rows: [
          {
            teacher_id: "teacher-a",
            teacher_name: "Иван Петров",
            completed_lessons_count: "3",
            revenue: "9000.00",
          },
        ],
      },
      {
        rows: [
          {
            room_id: "room-a",
            room_name: "101",
            lessons_count: "4",
          },
        ],
      },
    ]);

    await expect(
      service.getFinanceReport(actor, {
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
      }),
    ).resolves.toEqual({
      from: "2026-06-01T00:00:00.000Z",
      to: "2026-07-01T00:00:00.000Z",
      summary: {
        attendance: 75,
        revenue: 12000.5,
        totalLessons: 4,
        totalCompleted: 3,
      },
      monthly: [
        {
          monthStart: "2026-06-01T00:00:00.000Z",
          lessons: 4,
          completedLessons: 3,
          newStudents: 2,
          revenue: 12000.5,
          expenses: 3000,
        },
      ],
      teachers: [
        {
          teacherId: "teacher-a",
          teacherName: "Иван Петров",
          completedLessons: 3,
          revenue: 9000,
        },
      ],
      rooms: [
        {
          roomId: "room-a",
          roomName: "101",
          lessons: 4,
        },
      ],
    });

    expect(policy.assertCanReadSchoolFinance).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(3);
    expect(query.mock.calls[0][1]).toEqual([
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
    ]);
  });

  it("lists CRM activity log with actor and metadata context", async () => {
    const { service, query, policy } = createService([
      {
        id: "audit-a",
        actor_user_id: "manager-a",
        actor_email: "manager@example.com",
        actor_app_role: "manager",
        actor_staff_role: "manager",
        actor_position: "Управляющий",
        actor_first_name: "Ольга",
        actor_last_name: "Смирнова",
        actor_branches: [{ id: "branch-a", name: "Центр" }],
        action: "crm.student_updated",
        entity_type: "student",
        entity_id: "student-a",
        metadata: {
          historyType: "student",
          description: "Обновлена карточка",
          branchId: "branch-a",
        },
        created_at: "2026-06-15T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listActivityLog(actor, {
        q: "карточка",
        actorUserId: "manager-a",
        entityType: "student",
        entityId: "student-a",
        branchId: "branch-a",
        role: "manager",
        historyType: "student",
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        limit: 25,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "audit-a",
          actorUserId: "manager-a",
          actorName: "Ольга Смирнова",
          actorEmail: "manager@example.com",
          actorRole: "manager",
          actorStaffRole: "manager",
          actorPosition: "Управляющий",
          actorBranches: [{ id: "branch-a", name: "Центр" }],
          action: "crm.student_updated",
          entityType: "student",
          entityId: "student-a",
          historyType: "student",
          description: "Обновлена карточка",
          branchId: "branch-a",
          metadata: {
            historyType: "student",
            description: "Обновлена карточка",
            branchId: "branch-a",
          },
          createdAt: "2026-06-15T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "карточка",
      "manager-a",
      "student",
      "student-a",
      "branch-a",
      "manager",
      "student",
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      25,
    ]);
  });
});
