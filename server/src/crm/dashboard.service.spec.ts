import { DatabaseService } from "../db/database.service";
import { AuditPresentationService } from "../audit/audit-presentation.service";
import { CrmPolicy } from "./crm.policy";
import { DashboardService } from "./dashboard.service";

describe("DashboardService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const buildPolicy = (canReadSchoolFinance = true) => ({
    assertManagerOnly: jest.fn(),
    assertCanReadSchoolFinance: jest.fn(),
    canReadSchoolFinance: jest.fn().mockReturnValue(canReadSchoolFinance),
    assertCanWriteCrm: jest.fn(),
  });

  const createService = (
    rows: Record<string, unknown>[] = [],
    canReadSchoolFinance = true,
  ) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const policy = buildPolicy(canReadSchoolFinance);
    const service = new DashboardService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
      new AuditPresentationService(),
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
      new AuditPresentationService(),
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
        tasks: "/crm/shared-tasks?state=open",
        schedule: "/crm/schedule/matrix",
        activity: "/crm/activity",
      },
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      "branch-a",
      "manager-a",
      true,
    ]);
    const overviewSql = String(query.mock.calls[0][0]);
    expect(overviewSql).toContain(
      "app.commerce_receivable_schedule_projection",
    );
    expect(overviewSql).toContain(
      "app.commerce_student_account_projection",
    );
    expect(overviewSql).not.toContain("app.expected_payments");
  });

  it("redacts and skips school finance for a manager", async () => {
    const { service, query } = createService(
      [
        {
          revenue: "120000.50",
          expected_payments: "35000.00",
          debt_students: "4",
        },
      ],
      false,
    );

    const result = await service.getManagerDashboard(actor, {
      from: "2026-06-01T00:00:00.000Z",
      to: "2026-07-01T00:00:00.000Z",
    });

    expect(result.kpis).toMatchObject({
      revenue: null,
      expectedPayments: null,
      debtStudents: null,
    });
    expect(result.sources).not.toHaveProperty("revenue");
    expect(result.sources).not.toHaveProperty("expectedPayments");
    expect(result.sources).not.toHaveProperty("debtStudents");
    expect(query.mock.calls[0][1][4]).toBe(false);
    expect(String(query.mock.calls[0][0])).toContain(
      "case when $5::boolean then",
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

  it("presents CRM activity log through the shared audit contract", async () => {
    const { service, query, policy } = createService([
      {
        id: "audit-1",
        actor_user_id: actor.userId,
        actor_email: "natalia@example.com",
        actor_app_role: "manager",
        actor_staff_role: "manager",
        actor_position: "Управляющий",
        actor_first_name: "Наталия",
        actor_last_name: "Назарова",
        actor_branches: [{ id: "branch-a", name: "Центр" }],
        action: "crm.student_updated",
        entity_type: "crm:student",
        entity_id: "student-1",
        target_display_name: "Мария Баранова",
        metadata: { branchId: "branch-a", internalTrace: "not-for-response" },
        before_ref: {
          email: "old@example.com",
        },
        after_ref: {
          email: "new@example.com",
        },
        reason: "contact.update",
        reason_text: "Адрес изменён по просьбе ученика",
        created_at: "2026-06-15T00:00:00.000Z",
      },
      {
        id: "audit-lead-1",
        action: "crm.lead_updated",
        entity_type: "crm:lead",
        entity_id: "lead-1",
        target_display_name: "Вера Власова",
        metadata: null,
        before_ref: null,
        after_ref: null,
        reason: null,
        reason_text: null,
        created_at: "2026-06-14T00:00:00.000Z",
      },
      {
        id: "audit-comment-1",
        action: "crm.comment_created",
        entity_type: "crm:comment",
        entity_id: "comment-1",
        target_display_name: "PRIVATE-COMMENT-BODY-MUST-NOT-LEAK",
        metadata: null,
        before_ref: null,
        after_ref: null,
        reason: null,
        reason_text: null,
        created_at: "2026-06-13T00:00:00.000Z",
      },
      {
        id: "audit-task-1",
        action: "task.created",
        entity_type: "shared_task",
        entity_id: "task-1",
        target_display_name: "Позвонить родителю",
        metadata: null,
        before_ref: null,
        after_ref: null,
        reason: null,
        reason_text: null,
        created_at: "2026-06-12T00:00:00.000Z",
      },
      {
        id: "audit-archived-student-1",
        action: "crm.student_archived",
        entity_type: "student",
        entity_id: "archived-student-1",
        target_display_name: null,
        metadata: null,
        before_ref: null,
        after_ref: null,
        reason: null,
        reason_text: null,
        created_at: "2026-06-11T00:00:00.000Z",
      },
    ]);

    const result = await service.listActivityLog(actor, {
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
    });

    expect(result.items[0]).toMatchObject({
      id: "audit-1",
      title: "Электронная почта изменена",
      actor: { id: actor.userId, name: "Наталия Назарова" },
      target: {
        type: "student",
        id: "student-1",
        label: "Ученик",
        displayName: "Мария Баранова",
      },
      changes: [
        {
          key: "email",
          label: "Электронная почта",
          before: "old@example.com",
          after: "new@example.com",
        },
      ],
      reason: null,
      summary: "Адрес изменён по просьбе ученика",
    });
    expect(result.items[0]).not.toHaveProperty("metadata");
    expect(result.items[1].target).toMatchObject({
      type: "lead",
      id: "lead-1",
      label: "Лид",
      displayName: "Вера Власова",
      routeType: "lead",
    });
    expect(result.items[2].target).toMatchObject({
      type: "comment",
      id: "comment-1",
      label: "Комментарий",
      displayName: null,
      routeType: "comment",
    });
    expect(JSON.stringify(result.items)).not.toContain("PRIVATE-COMMENT-BODY-MUST-NOT-LEAK");
    expect(result.items[3].target).toMatchObject({
      type: "task",
      id: "task-1",
      label: "Задача",
      displayName: "Позвонить родителю",
      routeType: "task",
    });
    expect(result.items[4].target).toMatchObject({
      type: "student",
      id: "archived-student-1",
      displayName: null,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(1);
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
    const activitySql = String(query.mock.calls[0][0]);
    expect(activitySql).toContain("ae.action not like 'auth.%'");
    expect(activitySql).toContain("when 'crm:student' then 'student'");
    expect(activitySql).toContain("when 'crm:lead' then 'lead'");
    expect(activitySql).toContain("when 'crm:comment' then 'comment'");
    expect(activitySql).toContain("when 'shared_task' then 'task'");
    expect(activitySql).toContain("ae.presentation_entity_type = $3");
    expect(activitySql).toContain("left join app.shared_tasks shared_task");
    expect(activitySql).not.toContain("app.tasks");
    expect(activitySql).toContain("target_student_record.deleted_at is null");
    expect(activitySql).toContain("target_student_record.id = ae.target_entity_uuid");
    expect(activitySql).not.toContain("target_student.id::text = ae.entity_id");
    expect(activitySql).not.toContain("target_comment.body");
    expect(activitySql).not.toContain("target_lead_comment.body");
    expect(activitySql).not.toContain("join app.entity_comments");
    expect(activitySql).not.toContain("join app.lead_comments");
    expect(activitySql.indexOf("limit $10")).toBeLessThan(
      activitySql.indexOf("from app.students target_student_record"),
    );
  });
});
