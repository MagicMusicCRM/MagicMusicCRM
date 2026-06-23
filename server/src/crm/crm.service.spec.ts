import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { CrmPolicy } from "./crm.policy";
import { CrmService } from "./crm.service";

describe("CrmService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = {
      sendEmail: jest.fn().mockResolvedValue({ queued: true }),
      notifyUser: jest.fn().mockResolvedValue({ notificationId: "notif-test" }),
    };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
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

    const service = new CrmService(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      hollihop as unknown as HolliHopMetadataService,
      notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
    );

    return { service, query, audit, policy, hollihop, notifications };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = {
      sendEmail: jest.fn().mockResolvedValue({ queued: true }),
      notifyUser: jest.fn().mockResolvedValue({ notificationId: "notif-test" }),
    };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
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

    const service = new CrmService(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      hollihop as unknown as HolliHopMetadataService,
      notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
    );

    return { service, query, audit, policy, hollihop, notifications };
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
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["центр", 10]);
  });

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

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(3);
    expect(query.mock.calls[0][1]).toEqual([
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
    ]);
  });

  it("filters rooms by branch id", async () => {
    const { service, query } = createService([
      {
        id: "room-a",
        branch_id: "branch-a",
        branch_name: "Центр",
        name: "101",
        capacity: 4,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listRooms(actor, { branchId: "branch-a", limit: 5 }),
    ).resolves.toEqual({
      items: [
        {
          id: "room-a",
          branchId: "branch-a",
          branchName: "Центр",
          name: "101",
          capacity: 4,
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual(["branch-a", null, 5]);
  });

  it("returns room availability with slot conflicts", async () => {
    const { service, query, policy } = createService([
      {
        room_id: "room-a",
        branch_id: "branch-a",
        branch_name: "Центр",
        room_name: "101",
        capacity: 4,
        lessons: [
          {
            id: "lesson-a",
            teacherId: "teacher-a",
            teacherName: "Мария Петрова",
            scheduledAt: "2026-06-15T09:00:00.000Z",
            durationMinutes: 60,
            status: "scheduled",
            isTrial: false,
          },
        ],
        is_available: false,
        conflict_types: ["room_overlap"],
      },
    ]);

    await expect(
      service.listRoomAvailability(actor, {
        branchId: "branch-a",
        roomId: "room-a",
        teacherId: "teacher-a",
        date: "2026-06-15",
        from: "2026-06-15T09:00:00.000Z",
        to: "2026-06-15T10:00:00.000Z",
        durationMinutes: 60,
        limit: 20,
      }),
    ).resolves.toEqual({
      dateFrom: "2026-06-15T00:00:00.000Z",
      dateTo: "2026-06-16T00:00:00.000Z",
      slotFrom: "2026-06-15T09:00:00.000Z",
      slotTo: "2026-06-15T10:00:00.000Z",
      items: [
        {
          roomId: "room-a",
          branchId: "branch-a",
          branchName: "Центр",
          roomName: "101",
          capacity: 4,
          lessons: [
            {
              id: "lesson-a",
              teacherId: "teacher-a",
              teacherName: "Мария Петрова",
              scheduledAt: "2026-06-15T09:00:00.000Z",
              durationMinutes: 60,
              status: "scheduled",
              isTrial: false,
            },
          ],
          isAvailable: false,
          conflictTypes: ["room_overlap"],
        },
      ],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "branch-a",
      "room-a",
      "2026-06-15T00:00:00.000Z",
      "2026-06-16T00:00:00.000Z",
      "2026-06-15T09:00:00.000Z",
      "2026-06-15T10:00:00.000Z",
      "teacher-a",
      20,
    ]);
  });

  it("creates rooms through CRM write policy and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "room-b",
        branch_id: "branch-a",
        branch_name: "Центр",
        name: "102",
        capacity: 6,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createRoom(actor, {
        branchId: "branch-a",
        name: " 102 ",
        capacity: 6,
      }),
    ).resolves.toEqual({
      id: "room-b",
      branchId: "branch-a",
      branchName: "Центр",
      name: "102",
      capacity: 6,
      createdAt: "2026-06-12T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["branch-a", "102", 6]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.room_created",
        entityType: "room",
        entityId: "room-b",
      }),
    );
  });

  it("creates students through v3 identity/profile contract and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "student-a",
        status: "active",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        lead_id: null,
        custom_data: {},
        first_name: "Анна",
        last_name: "Иванова",
        email: "student@example.com",
        phone: "+79990000000",
        teacher_user_ids: [],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createStudent(actor, {
        firstName: " Анна ",
        lastName: " Иванова ",
        email: "Student@Example.com",
        phone: "+79990000000",
      }),
    ).resolves.toMatchObject({
      id: "student-a",
      firstName: "Анна",
      email: "student@example.com",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "Анна",
      "Иванова",
      "student@example.com",
      "Анна Иванова",
      "+79990000000",
      "active",
      null,
      JSON.stringify({}),
      null, // branch_id: no branchId in customDataPatch
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_created",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("queues student invitation email without activating app account", async () => {
    const { service, notifications, audit, policy } = createService([
      {
        id: "student-a",
        status: "active",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        lead_id: null,
        custom_data: {},
        first_name: "Анна",
        last_name: "Иванова",
        email: "Student@Example.com",
        phone: "+79990000000",
        teacher_user_ids: [],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(service.inviteStudent(actor, "student-a")).resolves.toEqual({
      studentId: "student-a",
      email: "student@example.com",
      status: "queued",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(notifications.sendEmail).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "user-a",
        template: "student_invite",
        title: "Приглашение в личный кабинет Magic Music",
      }),
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_invite_sent",
        entityType: "student",
        entityId: "student-a",
        metadata: expect.objectContaining({ emailHash: expect.any(String) }),
      }),
    );
  });

  it("rejects student invitation when email is not deliverable", async () => {
    const { service, notifications } = createService([
      {
        id: "student-a",
        status: "active",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        lead_id: null,
        custom_data: {},
        first_name: "Анна",
        last_name: "Иванова",
        email: "student-a@local.magicmusiccrm.invalid",
        phone: "+79990000000",
        teacher_user_ids: [],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(service.inviteStudent(actor, "student-a")).rejects.toThrow(
      "У ученика нет email для приглашения.",
    );
    expect(notifications.sendEmail).not.toHaveBeenCalled();
  });

  it("creates student from lead and preserves conversion link", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a" }] },
      { rows: [] },
      {
        rows: [
          {
            id: "student-a",
            lead_id: "lead-a",
            status: "active",
            custom_data: { discipline: "Вокал", sourceLeadId: "lead-a" },
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
            created_at: "2026-06-13T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
    ]);

    await expect(
      service.createStudent(actor, {
        firstName: "Анна",
        lastName: "Иванова",
        email: "anna@example.com",
        phone: "+79990000000",
        leadId: "lead-a",
        customDataPatch: { discipline: "Вокал", sourceLeadId: "lead-a" },
      }),
    ).resolves.toEqual(
      expect.objectContaining({
        id: "student-a",
        leadId: "lead-a",
        customData: { discipline: "Вокал", sourceLeadId: "lead-a" },
      }),
    );

    expect(query.mock.calls[0][1]).toEqual(["lead-a"]);
    expect(query.mock.calls[1][1]).toEqual(["lead-a"]);
    expect(query.mock.calls[2][1]).toEqual([
      "Анна",
      "Иванова",
      "anna@example.com",
      "Анна Иванова",
      "+79990000000",
      "active",
      "lead-a",
      JSON.stringify({ discipline: "Вокал", sourceLeadId: "lead-a" }),
      null, // branch_id: no branchId UUID in customDataPatch
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_created",
        entityId: "student-a",
        metadata: { leadId: "lead-a" },
      }),
    );
  });

  it("rejects lead conversion when lead already has active student", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a" }] },
      { rows: [{ id: "student-existing" }] },
    ]);

    await expect(
      service.createStudent(actor, {
        firstName: "Анна",
        leadId: "lead-a",
      }),
    ).rejects.toThrow("Этот лид уже конвертирован в ученика.");
  });

  it("creates teachers through v3 identity/profile contract and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
      },
    ]);

    await expect(
      service.createTeacher(actor, {
        firstName: " Мария ",
        lastName: " Петрова ",
        email: "Teacher@Example.com",
        phone: "+79991111111",
        specialization: " Вокал ",
      }),
    ).resolves.toMatchObject({
      id: "teacher-a",
      firstName: "Мария",
      specialization: "Вокал",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "Мария",
      "Петрова",
      "teacher@example.com",
      "Мария Петрова",
      "+79991111111",
      "active",
      "Вокал",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.teacher_created",
        entityType: "teacher",
        entityId: "teacher-a",
      }),
    );
  });

  it("lists teachers for clients through individual or group relationships", async () => {
    const clientActor = { userId: "client-a", role: "client" as const };
    const { service, query } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Фортепиано",
        profile_id: "profile-teacher-a",
        profile_user_id: "teacher-user-a",
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
      },
    ]);

    await expect(
      service.listTeachers(clientActor, { limit: 10 }),
    ).resolves.toEqual({
      items: [
        {
          id: "teacher-a",
          status: "active",
          specialization: "Фортепиано",
          profileId: "profile-teacher-a",
          profileUserId: "teacher-user-a",
          firstName: "Мария",
          lastName: "Петрова",
          email: "teacher@example.com",
          phone: "+79991111111",
        },
      ],
    });

    // Client visibility now via EXISTS (individual lessons OR group membership),
    // replacing the former cartesian LEFT JOINs + DISTINCT.
    expect(query.mock.calls[0][0]).toContain("csp.user_id = $2");
    expect(query.mock.calls[0][0]).toContain("cgsp.user_id = $2");
    expect(query.mock.calls[0][0]).not.toContain("select distinct");
    expect(query.mock.calls[0][1]).toEqual([
      "client",
      "client-a",
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      10,
    ]);
  });

  it("lists teachers with HolliHop staff filters and aggregate metadata", async () => {
    const { service, query } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        custom_data: {
          disciplines: ["Вокал"],
          levels: ["Начальный"],
          categories: ["Взрослые"],
          rating: 4.8,
        },
        profile_id: "profile-teacher-a",
        profile_user_id: "teacher-user-a",
        app_role: "teacher",
        is_app_account: false,
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
        branches: [{ id: "branch-a", name: "Центр" }],
        students_count: "12",
        lessons_count: "34",
        rating: "4.8",
        created_at: "2026-06-15T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listTeachers(actor, {
        q: "мария",
        status: "active",
        branchId: "branch-a",
        discipline: "Вокал",
        level: "Начальный",
        category: "Взрослые",
        appRole: "teacher",
        authorization: "technical",
        ratingFrom: 4,
        ratingTo: 5,
        birthdayMonth: 6,
        limit: 20,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "teacher-a",
          status: "active",
          specialization: "Вокал",
          customData: {
            disciplines: ["Вокал"],
            levels: ["Начальный"],
            categories: ["Взрослые"],
            rating: 4.8,
          },
          profileId: "profile-teacher-a",
          profileUserId: "teacher-user-a",
          appRole: "teacher",
          isAppAccount: false,
          firstName: "Мария",
          lastName: "Петрова",
          email: "teacher@example.com",
          phone: "+79991111111",
          branches: [{ id: "branch-a", name: "Центр" }],
          studentsCount: 12,
          lessonsCount: 34,
          rating: 4.8,
          createdAt: "2026-06-15T00:00:00.000Z",
        },
      ],
    });

    expect(query.mock.calls[0][0]).toContain("app.user_crm_links link");
    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      "мария",
      "active",
      "branch-a",
      "Вокал",
      "Начальный",
      "Взрослые",
      "teacher",
      "technical",
      4,
      5,
      6,
      20,
    ]);
  });

  it("updates teachers through CRM write policy and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
      },
    ]);

    await expect(
      service.updateTeacher(actor, "teacher-a", {
        firstName: " Мария ",
        lastName: " Петрова ",
        email: "Teacher@Example.com",
        phone: "+79991111111",
        specialization: " Вокал ",
      }),
    ).resolves.toMatchObject({
      id: "teacher-a",
      firstName: "Мария",
      specialization: "Вокал",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "teacher-a",
      "Мария",
      "Петрова",
      "+79991111111",
      "teacher@example.com",
      null,
      "Вокал",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.teacher_updated",
        entityType: "teacher",
        entityId: "teacher-a",
      }),
    );
  });

  it("forbids admin from creating staff and manager from minting manager/system_admin", async () => {
    const { service } = createService();

    // Администратор (ниже Управляющего) не управляет ролями вовсе.
    await expect(
      service.createStaff(
        { userId: "admin-a", role: "admin" as const },
        {
          firstName: "Ольга",
          lastName: "Смирнова",
          email: "staff-admin@example.com",
          role: "manager",
        },
      ),
    ).rejects.toThrow("Недостаточно прав");

    // Управляющий не может создать manager или system_admin (роль >= своей).
    await expect(
      service.createStaff(actor, {
        firstName: "Ольга",
        lastName: "Смирнова",
        email: "staff@example.com",
        role: "system_admin",
      }),
    ).rejects.toThrow("Недостаточно прав");
  });

  it("creates staff profiles for privileged roles (system_admin)", async () => {
    const adminActor = { userId: "sys-a", role: "system_admin" as const };
    const { service, query, audit } = createService([
      {
        id: "profile-a",
        userId: "user-a",
        email: "staff@example.com",
        role: "manager",
        firstName: "Ольга",
        lastName: "Смирнова",
        phone: "+79992222222",
        avatarFileId: null,
        emailOtp2faEnabled: false,
        createdAt: "2026-06-13T00:00:00.000Z",
        updatedAt: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createStaff(adminActor, {
        firstName: " Ольга ",
        lastName: " Смирнова ",
        email: "Staff@Example.com",
        phone: "+79992222222",
        role: "manager",
      }),
    ).resolves.toMatchObject({
      id: "profile-a",
      email: "staff@example.com",
      role: "manager",
    });

    expect(query.mock.calls[0][1]).toEqual([
      "staff@example.com",
      "Ольга Смирнова",
      "+79992222222",
      "manager",
      "Ольга",
      "Смирнова",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.staff_created",
        entityType: "profile",
        entityId: "profile-a",
      }),
    );
  });

  it("limits staff updates to admins", async () => {
    const { service } = createService();

    await expect(
      service.updateStaff(actor, "staff-a", {
        firstName: "Ольга",
      }),
    ).rejects.toThrow("Только администратор");
  });

  it("updates staff profile and CRM fields for admins", async () => {
    const adminActor = { userId: "admin-a", role: "admin" as const };
    const { service, query, audit } = createService([
      {
        id: "staff-a",
        role: "manager",
        position: "Операционный управляющий",
        status: "working",
        custom_data: { birthday: "1990-06-01", telegram: "@staff" },
        profile_id: "profile-a",
        profile_user_id: "user-a",
        app_role: "manager",
        is_app_account: true,
        first_name: "Ольга",
        last_name: "Смирнова",
        email: "staff@example.com",
        phone: "+79992222222",
        branches: [{ id: "branch-a", name: "Центр" }],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.updateStaff(adminActor, "staff-a", {
        firstName: " Ольга ",
        lastName: " Смирнова ",
        phone: "+79992222222",
        email: "Staff@Example.com",
        role: "manager",
        position: " Операционный управляющий ",
        status: "working",
        customDataPatch: { telegram: "@staff" },
      }),
    ).resolves.toMatchObject({
      id: "staff-a",
      role: "manager",
      position: "Операционный управляющий",
      status: "working",
      customData: { birthday: "1990-06-01", telegram: "@staff" },
      firstName: "Ольга",
      lastName: "Смирнова",
      email: "staff@example.com",
      phone: "+79992222222",
      branches: [{ id: "branch-a", name: "Центр" }],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "staff-a",
      "Ольга",
      "Смирнова",
      "+79992222222",
      "staff@example.com",
      "manager",
      "Операционный управляющий",
      "working",
      JSON.stringify({ telegram: "@staff" }),
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.staff_updated",
        entityType: "staff",
        entityId: "staff-a",
      }),
    );
  });

  it("lists staff with role status authorization and birthday filters", async () => {
    const { service, query, policy } = createService([
      {
        id: "staff-a",
        role: "manager",
        position: "Управляющий",
        status: "working",
        custom_data: { birthday: "1990-06-01" },
        profile_id: "profile-a",
        profile_user_id: "user-a",
        app_role: "manager",
        is_app_account: true,
        first_name: "Ольга",
        last_name: "Смирнова",
        email: "staff@example.com",
        phone: "+79992222222",
        branches: [{ id: "branch-a", name: "Центр" }],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listStaff(actor, {
        branchId: "branch-a",
        q: "ольга",
        role: "manager",
        status: "working",
        appRole: "manager",
        authorization: "app",
        birthdayMonth: 6,
        limit: 15,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "staff-a",
          role: "manager",
          position: "Управляющий",
          status: "working",
          customData: { birthday: "1990-06-01" },
          profileId: "profile-a",
          profileUserId: "user-a",
          appRole: "manager",
          isAppAccount: true,
          firstName: "Ольга",
          lastName: "Смирнова",
          email: "staff@example.com",
          phone: "+79992222222",
          branches: [{ id: "branch-a", name: "Центр" }],
          createdAt: "2026-06-13T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "branch-a",
      "ольга",
      "manager",
      "working",
      "manager",
      "app",
      6,
      15,
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

  it("updates and soft-deletes rooms through CRM write policy", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "room-a",
            branch_id: "branch-b",
            branch_name: "Север",
            name: "201",
            capacity: 8,
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
      { rows: [{ id: "room-a" }] },
    ]);

    await expect(
      service.updateRoom(actor, "room-a", {
        branchId: "branch-b",
        name: " 201 ",
        capacity: 8,
      }),
    ).resolves.toMatchObject({
      id: "room-a",
      branchId: "branch-b",
      branchName: "Север",
      name: "201",
      capacity: 8,
    });
    await expect(service.deleteRoom(actor, "room-a")).resolves.toEqual({
      success: true,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledTimes(2);
    expect(query.mock.calls[0][1]).toEqual(["room-a", "branch-b", "201", 8]);
    expect(query.mock.calls[1][1]).toEqual(["room-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.room_updated",
        entityType: "room",
        entityId: "room-a",
      }),
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.room_deleted",
        entityType: "room",
        entityId: "room-a",
      }),
    );
  });

  it("maps groups with numeric lesson price", async () => {
    const { service } = createService([
      {
        id: "group-a",
        teacher_id: "teacher-a",
        branch_id: "branch-a",
        room_id: "room-a",
        name: "Гитара",
        price_per_lesson: "2500.00",
        teacher_name: "Иван Петров",
        branch_name: "Центр",
        room_name: "101",
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(service.listGroups(actor, { limit: 20 })).resolves.toEqual({
      items: [
        {
          id: "group-a",
          teacherId: "teacher-a",
          branchId: "branch-a",
          roomId: "room-a",
          name: "Гитара",
          pricePerLesson: 2500,
          teacherName: "Иван Петров",
          branchName: "Центр",
          roomName: "101",
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });
  });

  it("creates groups through CRM write policy and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "group-b",
        teacher_id: "teacher-a",
        branch_id: "branch-a",
        room_id: "room-a",
        name: "Фортепиано",
        price_per_lesson: "3000.00",
        teacher_name: "Мария Петрова",
        branch_name: "Центр",
        room_name: "101",
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createGroup(actor, {
        name: " Фортепиано ",
        teacherId: "teacher-a",
        branchId: "branch-a",
        roomId: "room-a",
        pricePerLesson: 3000,
      }),
    ).resolves.toMatchObject({
      id: "group-b",
      name: "Фортепиано",
      pricePerLesson: 3000,
      teacherName: "Мария Петрова",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "teacher-a",
      "branch-a",
      "room-a",
      "Фортепиано",
      3000,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.group_created",
        entityType: "group",
        entityId: "group-b",
      }),
    );
  });

  it("lists adds and removes group students through v3 contract", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            profile_id: "profile-a",
            profile_user_id: "user-a",
            lead_id: null,
            custom_data: {},
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            teacher_user_ids: [],
            created_at: "2026-06-13T00:00:00.000Z",
          },
        ],
      },
      { rows: [{ id: "group-student-a", student_id: "student-a" }] },
      { rows: [{ id: "group-student-a" }] },
    ]);

    await expect(
      service.listGroupStudents(actor, "group-a", { limit: 10 }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "student-a",
          firstName: "Анна",
        }),
      ],
    });
    await expect(
      service.addGroupStudent(actor, "group-a", "student-a"),
    ).resolves.toEqual({ success: true });
    await expect(
      service.removeGroupStudent(actor, "group-a", "student-a"),
    ).resolves.toEqual({ success: true });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledTimes(2);
    expect(query.mock.calls[0][1]).toEqual(["group-a", 10]);
    expect(query.mock.calls[1][1]).toEqual(["group-a", "student-a"]);
    expect(query.mock.calls[2][1]).toEqual(["group-a", "student-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.group_student_added",
        entityType: "group",
        entityId: "group-a",
        metadata: { studentId: "student-a" },
      }),
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.group_student_removed",
        entityType: "group",
        entityId: "group-a",
        metadata: { studentId: "student-a" },
      }),
    );
  });

  it("lists tasks with status and student filters plus display names", async () => {
    const { service, query, policy } = createService([
      {
        id: "task-a",
        entity_type: "student",
        entity_id: "student-a",
        assigned_to: "manager-a",
        assigned_first_name: "Мария",
        assigned_last_name: "Менеджер",
        entity_first_name: "Анна",
        entity_last_name: "Иванова",
        entity_name: null,
        title: "Позвонить",
        description: null,
        status: "open",
        due_at: "2026-06-13T00:00:00.000Z",
        created_by: "admin-a",
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listTasks(actor, {
        studentId: "student-a",
        status: "open",
        limit: 15,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "task-a",
          entityType: "student",
          entityId: "student-a",
          assignedTo: "manager-a",
          assignedName: "Мария Менеджер",
          entityName: "Анна Иванова",
          title: "Позвонить",
          description: null,
          status: "open",
          dueAt: "2026-06-13T00:00:00.000Z",
          createdBy: "admin-a",
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      15,
      "student-a",
      "open",
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
    ]);
    // Reading tasks is operational (shown in client cards to admin/teacher),
    // not a manager-only management op.
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(policy.assertManagerOnly).not.toHaveBeenCalled();
  });

  it("lists task board with operational filters and branch context", async () => {
    const { service, query } = createService([
      {
        id: "task-a",
        entity_type: "lead",
        entity_id: "lead-a",
        assigned_to: "manager-a",
        assigned_first_name: "Мария",
        assigned_last_name: "Менеджер",
        creator_first_name: "Ольга",
        creator_last_name: "Админ",
        entity_first_name: null,
        entity_last_name: null,
        entity_name: "Анна Иванова",
        branch_id: "branch-a",
        branch_name: "Центр",
        title: "Позвонить",
        description: "Приоритет высокий, WhatsApp",
        status: "open",
        due_at: "2026-06-13T00:00:00.000Z",
        created_by: "admin-a",
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listTasks(actor, {
        q: "анна",
        entityType: "lead",
        entityId: "lead-a",
        assignedTo: "manager-a",
        createdBy: "admin-a",
        branchId: "branch-a",
        status: "open",
        priority: "высокий",
        taskType: "звонок",
        communicationMethod: "WhatsApp",
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        limit: 25,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "task-a",
          entityType: "lead",
          entityId: "lead-a",
          assignedTo: "manager-a",
          assignedName: "Мария Менеджер",
          entityName: "Анна Иванова",
          title: "Позвонить",
          description: "Приоритет высокий, WhatsApp",
          status: "open",
          dueAt: "2026-06-13T00:00:00.000Z",
          createdBy: "admin-a",
          createdAt: "2026-06-12T00:00:00.000Z",
          creatorName: "Ольга Админ",
          branchId: "branch-a",
          branchName: "Центр",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      25,
      null,
      "open",
      "анна",
      "lead",
      "lead-a",
      "manager-a",
      "admin-a",
      "branch-a",
      "высокий",
      "звонок",
      "WhatsApp",
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
    ]);
  });

  it("returns unified timeline events for a student", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            profile_user_id: "client-a",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            type: "comment",
            title: "Комментарий",
            body: "Позвонить родителю",
            status: null,
            amount: null,
            actor_user_id: "manager-a",
            actor_first_name: "Мария",
            actor_last_name: "Менеджер",
            occurred_at: "2026-06-15T09:00:00.000Z",
          },
          {
            id: "payment-a",
            type: "payment",
            title: "Платеж",
            body: "Абонемент",
            status: "cash",
            amount: "12000.00",
            actor_user_id: "manager-a",
            actor_first_name: "Мария",
            actor_last_name: "Менеджер",
            occurred_at: "2026-06-14T09:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listTimeline(actor, {
        entityType: "student",
        entityId: "student-a",
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        includeAudit: true,
        limit: 40,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "comment-a",
          type: "comment",
          title: "Комментарий",
          body: "Позвонить родителю",
          status: null,
          amount: null,
          actorUserId: "manager-a",
          actorName: "Мария Менеджер",
          occurredAt: "2026-06-15T09:00:00.000Z",
        },
        {
          id: "payment-a",
          type: "payment",
          title: "Платеж",
          body: "Абонемент",
          status: "cash",
          amount: 12000,
          actorUserId: "manager-a",
          actorName: "Мария Менеджер",
          occurredAt: "2026-06-14T09:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(actor, {
      profileUserId: "client-a",
      teacherUserIds: [],
    });
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      true,
      40,
      ["admin_comment", "teacher_note", "progress"],
    ]);
  });

  it("lists trial lessons with actor-scoped query", async () => {
    const { service, query } = createService([
      {
        id: "lesson-a",
        student_id: "student-a",
        group_id: null,
        lead_id: null,
        teacher_id: "teacher-a",
        branch_id: null,
        room_id: null,
        scheduled_at: "2026-06-12T12:00:00.000Z",
        duration_minutes: 60,
        status: "completed",
        is_trial: true,
        notes: null,
        student_user_id: null,
        teacher_user_id: null,
        student_name: "Анна Иванова",
        teacher_name: "Иван Петров",
        branch_name: null,
        room_name: null,
        group_name: null,
        group_price_per_lesson: null,
      },
    ]);

    await expect(
      service.listLessons(actor, { isTrial: true, limit: 10 }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "lesson-a",
          isTrial: true,
          status: "completed",
        }),
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      null,
      null,
      null,
      null,
      true,
      10,
    ]);
  });

  it("returns schedule matrix grouped by room with conflicts", async () => {
    const { service, query, policy } = createService([
      {
        id: "lesson-a",
        student_id: "student-a",
        group_id: null,
        lead_id: null,
        teacher_id: "teacher-a",
        branch_id: "branch-a",
        room_id: "room-a",
        scheduled_at: "2026-06-15T09:00:00.000Z",
        duration_minutes: 60,
        status: "scheduled",
        is_trial: true,
        notes: null,
        student_user_id: null,
        teacher_user_id: null,
        student_name: "Анна Иванова",
        teacher_name: "Иван Петров",
        branch_name: "Центр",
        room_name: "101",
        group_name: null,
        group_price_per_lesson: null,
        conflict_types: ["room_overlap"],
      },
    ]);

    const matrix = await service.getScheduleMatrix(actor, {
      from: "2026-06-15T00:00:00.000Z",
      to: "2026-06-16T00:00:00.000Z",
      branchId: "branch-a",
      roomId: "room-a",
      teacherId: "teacher-a",
      isTrial: true,
      groupBy: "room",
      limit: 30,
    });

    expect(matrix).toMatchObject({
      from: "2026-06-15T00:00:00.000Z",
      to: "2026-06-16T00:00:00.000Z",
      groupBy: "room",
      groups: [
        {
          key: "room-a",
          label: "101",
          items: [expect.objectContaining({ id: "lesson-a" })],
        },
      ],
      conflicts: [
        {
          type: "room_overlap",
          lessonId: "lesson-a",
          scheduledAt: "2026-06-15T09:00:00.000Z",
          roomId: "room-a",
          teacherId: "teacher-a",
        },
      ],
    });
    expect(matrix.items[0]).toMatchObject({
      id: "lesson-a",
      conflictTypes: ["room_overlap"],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "2026-06-15T00:00:00.000Z",
      "2026-06-16T00:00:00.000Z",
      "branch-a",
      "room-a",
      "teacher-a",
      true,
      30,
    ]);
  });

  it("counts an overlapping pair once, not twice (KVA-166 dedup)", async () => {
    // Two lessons share a room and overlap each other. Each row is flagged
    // room_overlap (correct, both get red borders), and each row's
    // room_overlap_ids points at the OTHER lesson. The aggregated conflicts
    // list must contain ONE entry for the pair, not two.
    const baseRow = {
      student_id: null,
      group_id: null,
      lead_id: null,
      teacher_id: "teacher-a",
      branch_id: "branch-a",
      room_id: "room-a",
      duration_minutes: 60,
      status: "scheduled",
      is_trial: false,
      notes: null,
      student_user_id: null,
      teacher_user_id: null,
      student_name: null,
      teacher_name: null,
      branch_name: "Центр",
      room_name: "101",
      group_name: null,
      group_price_per_lesson: null,
      conflict_types: ["room_overlap"],
    };
    const { service } = createService([
      {
        ...baseRow,
        id: "lesson-a",
        scheduled_at: "2026-06-15T09:00:00.000Z",
        room_overlap_ids: ["lesson-b"],
        teacher_overlap_ids: [],
      },
      {
        ...baseRow,
        id: "lesson-b",
        scheduled_at: "2026-06-15T09:30:00.000Z",
        room_overlap_ids: ["lesson-a"],
        teacher_overlap_ids: [],
      },
    ]);

    const matrix = await service.getScheduleMatrix(actor, {
      from: "2026-06-15T00:00:00.000Z",
      to: "2026-06-16T00:00:00.000Z",
      groupBy: "room",
    });

    // Both lessons still individually flagged for the UI.
    expect(matrix.items.map((i: { id: string }) => i.id)).toEqual([
      "lesson-a",
      "lesson-b",
    ]);
    expect(matrix.items[0].conflictTypes).toEqual(["room_overlap"]);
    expect(matrix.items[1].conflictTypes).toEqual(["room_overlap"]);
    // But the overlapping pair is counted exactly once.
    expect(matrix.conflicts).toHaveLength(1);
    expect(matrix.conflicts[0]).toMatchObject({
      type: "room_overlap",
      lessonId: "lesson-a",
    });
  });

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

  it("returns lead board columns with counts and aggregate lead fields", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "status-a",
            name: "Новый",
            color: "#C5A059",
            sort_order: 1,
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
      { rows: [{ status_id: "status-a", count: "2" }] },
      {
        rows: [
          {
            id: "11111111-1111-4111-8111-111111111111",
            status_id: "status-a",
            status_name: "Новый",
            status_color: "#C5A059",
            status_sort_order: 1,
            first_name: "Анна",
            last_name: "Иванова",
            phone: "+79990000000",
            email: "anna@example.com",
            source: "site",
            notes: null,
            assigned_to: "manager-a",
            assigned_first_name: "Мария",
            assigned_last_name: "Менеджер",
            branch_id: "branch-a",
            branch_name: "Центр",
            linked_student_id: "student-a",
            open_tasks_count: "2",
            comments_count: "3",
            trial_lessons_count: "1",
            custom_data: { discipline: "Вокал", hollihopId: "HH-42" },
            created_by: "manager-a",
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listLeadBoard(actor, {
        q: "анна",
        branchId: "22222222-2222-4222-8222-222222222222",
        discipline: "Вокал",
        quick: "active",
        openTasks: true,
        limit: 10,
      }),
    ).resolves.toEqual({
      columns: [
        expect.objectContaining({
          id: "status-a",
          name: "Новый",
          totalCount: 2,
          items: [
            expect.objectContaining({
              id: "11111111-1111-4111-8111-111111111111",
              assignedName: "Мария Менеджер",
              branchName: "Центр",
              linkedStudentId: "student-a",
              openTasksCount: 2,
              commentsCount: 3,
              trialLessonsCount: 1,
            }),
          ],
        }),
      ],
      totalCount: 2,
      nextCursor:
        "2026-06-12T00:00:00.000Z|11111111-1111-4111-8111-111111111111",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(3);
    expect(query.mock.calls[2][1]).toContain("анна");
    expect(query.mock.calls[2][1]).toContain("Вокал");
    expect(query.mock.calls[2][1]).toContain(10);
  });

  it("hides converted leads from the board when hideConverted is set", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // statuses
      { rows: [] }, // counts
      { rows: [] }, // leads
    ]);
    await service.listLeadBoard(actor, { hideConverted: true });
    // count query (call 1) and lead query (call 2) both carry the predicate
    expect(query.mock.calls[1][0]).toContain("from app.students");
    expect(query.mock.calls[1][0]).toContain("linked_conv.lead_id = l.id");
    expect(query.mock.calls[1][0]).toContain(
      "p_conv.phone_normalized = l.phone_normalized",
    );
    expect(query.mock.calls[2][0]).toContain("not exists");
  });

  it("does not add the converted filter by default", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);
    await service.listLeadBoard(actor, {});
    expect(query.mock.calls[2][0]).not.toContain("linked_conv.lead_id = l.id");
  });

  it("returns lead card aggregate with linked records and timeline", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lead-a",
            status_id: "status-a",
            status_name: "Новый",
            status_color: "#C5A059",
            status_sort_order: 1,
            first_name: "Анна",
            last_name: "Иванова",
            phone: "+79990000000",
            email: "anna@example.com",
            source: "site",
            notes: null,
            assigned_to: "manager-a",
            assigned_first_name: "Мария",
            assigned_last_name: "Менеджер",
            branch_id: "branch-a",
            branch_name: "Центр",
            linked_student_id: "student-a",
            open_tasks_count: "1",
            comments_count: "1",
            trial_lessons_count: "1",
            custom_data: { discipline: "Вокал" },
            created_by: "manager-a",
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            profile_id: "profile-a",
            profile_user_id: "client-a",
            lead_id: "lead-a",
            custom_data: {},
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
            created_at: "2026-06-12T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      { rows: [] },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "lead",
            entity_id: "lead-a",
            author_id: "manager-a",
            author_first_name: "Мария",
            author_last_name: "Менеджер",
            body: "Позвонить",
            created_at: "2026-06-12T10:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          {
            id: "task-a",
            entity_type: "lead",
            entity_id: "lead-a",
            assigned_to: "manager-a",
            assigned_first_name: "Мария",
            assigned_last_name: "Менеджер",
            entity_first_name: null,
            entity_last_name: null,
            entity_name: null,
            title: "Перезвонить",
            description: null,
            status: "open",
            due_at: null,
            created_by: "manager-a",
            created_at: "2026-06-12T09:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          {
            id: "lesson-a",
            student_id: null,
            group_id: null,
            lead_id: "lead-a",
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            scheduled_at: "2026-06-15T09:00:00.000Z",
            duration_minutes: 60,
            status: "scheduled",
            is_trial: true,
            notes: null,
            student_user_id: null,
            teacher_user_id: "teacher-user-a",
            student_name: null,
            teacher_name: "Иван Петров",
            branch_name: "Центр",
            room_name: "101",
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      },
    ]);

    await expect(service.getLeadCard(actor, "lead-a")).resolves.toEqual(
      expect.objectContaining({
        lead: expect.objectContaining({
          id: "lead-a",
          assignedName: "Мария Менеджер",
          openTasksCount: 1,
        }),
        linkedStudents: [
          expect.objectContaining({ id: "student-a", firstName: "Анна" }),
        ],
        comments: [expect.objectContaining({ body: "Позвонить" })],
        tasks: [expect.objectContaining({ title: "Перезвонить" })],
        trials: [expect.objectContaining({ teacherName: "Иван Петров" })],
        timeline: expect.arrayContaining([
          expect.objectContaining({ type: "comment" }),
          expect.objectContaining({ type: "task" }),
          expect.objectContaining({ type: "trial" }),
        ]),
      }),
    );

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(6);
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

  it("lists subscriptions with actor-scoped query and safe DTO", async () => {
    const { service, query } = createService([
      {
        id: "sub-a",
        student_id: "student-a",
        student_user_id: "client-a",
        lessons_total: 8,
        lessons_used: 3,
        starts_at: "2026-06-01",
        expires_at: "2026-07-01",
        status: "active",
        created_at: "2026-06-01T00:00:00.000Z",
        updated_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listSubscriptions(
        { userId: "client-a", role: "client" },
        { studentId: "student-a", limit: 1 },
      ),
    ).resolves.toEqual({
      items: [
        {
          id: "sub-a",
          studentId: "student-a",
          lessonsTotal: 8,
          lessonsUsed: 3,
          startsAt: "2026-06-01",
          expiresAt: "2026-07-01",
          status: "active",
          createdAt: "2026-06-01T00:00:00.000Z",
          updatedAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "client",
      "client-a",
      "student-a",
      1,
    ]);
  });

  it("lists payments with date filters and student summary", async () => {
    const { service, query } = createService([
      {
        id: "payment-a",
        student_id: "student-a",
        student_user_id: "client-a",
        student_first_name: "Анна",
        student_last_name: "Иванова",
        amount: "5000.00",
        currency: "RUB",
        payment_date: "2026-06-12T12:00:00.000Z",
        method: "subscription",
        external_id: null,
        notes: null,
        created_by: "manager-a",
        created_at: "2026-06-12T12:00:00.000Z",
      },
    ]);

    await expect(
      service.listPayments(actor, {
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        limit: 10,
      }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "payment-a",
          studentId: "student-a",
          studentName: "Анна Иванова",
          amount: 5000,
          method: "subscription",
        }),
      ],
      // Totals come from a separate aggregate query (mocked with the same row,
      // which has no total_* fields, so they resolve to 0 here).
      totalAmount: 0,
      totalCount: 0,
    });

    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      null,
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      10,
    ]);
  });

  it("lists computed student balances for CRM writers", async () => {
    const { service, query, policy } = createService([
      {
        student_id: "student-a",
        first_name: "Анна",
        last_name: "Иванова",
        phone: "+79990000000",
        total_paid: "2000.00",
        total_cost: "5000.00",
        balance: "-3000.00",
        updated_at: "2026-06-12T12:00:00.000Z",
      },
    ]);

    await expect(
      service.listStudentBalances(actor, {
        studentId: "student-a",
        debtOnly: true,
        limit: 20,
      }),
    ).resolves.toEqual({
      items: [
        {
          studentId: "student-a",
          balance: -3000,
          totalPaid: 2000,
          totalCost: 5000,
          updatedAt: "2026-06-12T12:00:00.000Z",
          student: {
            firstName: "Анна",
            lastName: "Иванова",
            phone: "+79990000000",
          },
        },
      ],
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["student-a", true, 20]);
  });

  it("returns lesson attendance for allowed staff", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-a",
            student_id: null,
            group_id: "group-a",
            teacher_user_id: "teacher-user-a",
          },
        ],
      },
      {
        rows: [
          {
            student_id: "student-a",
            first_name: "Анна",
            last_name: "Иванова",
          },
          {
            student_id: "student-b",
            first_name: "Олег",
            last_name: "Петров",
          },
        ],
      },
      {
        rows: [
          {
            student_id: "student-b",
            status: "absent",
            pass_reason: "Болеет",
          },
        ],
      },
    ]);

    await expect(
      service.getLessonAttendance(actor, "lesson-a"),
    ).resolves.toEqual({
      lessonId: "lesson-a",
      students: [
        {
          studentId: "student-a",
          studentName: "Анна Иванова",
          status: "present",
          passReason: "",
        },
        {
          studentId: "student-b",
          studentName: "Олег Петров",
          status: "absent",
          passReason: "Болеет",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual(["lesson-a"]);
    expect(query.mock.calls[1][1]).toEqual([null, "group-a"]);
    expect(query.mock.calls[2][1]).toEqual(["lesson-a"]);
  });

  it("upserts lesson attendance and completes the lesson", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            teacher_user_id: "teacher-user-a",
          },
        ],
      },
      {
        rows: [
          {
            student_id: "student-a",
            first_name: "Анна",
            last_name: "Иванова",
          },
        ],
      },
      { rows: [] },
      { rows: [] },
      // P5b-4: subscription lessons_used reconciliation query (no-op here).
      { rows: [] },
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            teacher_user_id: "teacher-user-a",
          },
        ],
      },
      {
        rows: [
          {
            student_id: "student-a",
            first_name: "Анна",
            last_name: "Иванова",
          },
        ],
      },
      {
        rows: [
          {
            student_id: "student-a",
            status: "absent",
            pass_reason: "Болеет",
          },
        ],
      },
    ]);

    await expect(
      service.upsertLessonAttendance(actor, "lesson-a", {
        items: [
          {
            studentId: "student-a",
            status: "absent",
            passReason: "Болеет",
          },
        ],
      }),
    ).resolves.toEqual({
      lessonId: "lesson-a",
      students: [
        {
          studentId: "student-a",
          studentName: "Анна Иванова",
          status: "absent",
          passReason: "Болеет",
        },
      ],
    });

    expect(query.mock.calls[2][1]).toEqual([
      "lesson-a",
      "student-a",
      "absent",
      "Болеет",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lesson_attendance_updated",
        entityType: "lesson",
        entityId: "lesson-a",
      }),
    );
  });

  it("lists active student groups after student read authorization", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: ["teacher-user-a"],
          },
        ],
      },
      {
        rows: [
          {
            id: "group-a",
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            name: "Гитара A",
            price_per_lesson: "1500.00",
            teacher_name: "Иван Петров",
            branch_name: "Центр",
            room_name: "101",
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listStudentGroups(actor, "student-a", { limit: 10 }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "group-a",
          name: "Гитара A",
          teacherName: "Иван Петров",
          pricePerLesson: 1500,
        }),
      ],
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(actor, {
      profileUserId: "client-a",
      teacherUserIds: ["teacher-user-a"],
    });
    expect(query.mock.calls[1][1]).toEqual(["student-a", 10]);
  });

  it("lists expected payments after student read authorization", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "expected-a",
            student_id: "student-a",
            student_user_id: "client-a",
            student_first_name: "Анна",
            student_last_name: "Иванова",
            amount: "5000.00",
            due_date: "2026-06-30",
            status: "pending",
            description: "Абонемент за июнь",
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listExpectedPayments(actor, {
        studentId: "student-a",
        limit: 10,
      }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "expected-a",
          studentId: "student-a",
          studentName: "Анна Иванова",
          amount: 5000,
          dueDate: "2026-06-30",
          status: "pending",
          description: "Абонемент за июнь",
        }),
      ],
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(actor, {
      profileUserId: "client-a",
      teacherUserIds: [],
    });
    expect(query.mock.calls[1][1]).toEqual(["student-a", 10]);
  });

  it("lists progress comments after student ownership check", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "student",
            entity_id: "student-a",
            author_id: "teacher-a",
            author_first_name: "Иван",
            author_last_name: "Петров",
            body: "Хорошая динамика",
            kind: "progress",
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listComments(
        { userId: "client-a", role: "client" },
        {
          entityType: "student",
          entityId: "student-a",
          progressOnly: true,
          limit: 5,
        },
      ),
    ).resolves.toEqual({
      items: [
        {
          id: "comment-a",
          entityType: "student",
          entityId: "student-a",
          authorId: "teacher-a",
          authorName: "Иван Петров",
          body: "Хорошая динамика",
          kind: "progress",
          progress: true,
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(
      { userId: "client-a", role: "client" },
      { profileUserId: "client-a", teacherUserIds: [] },
    );
    // A client may only ever see the progress stream.
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      ["progress"],
      5,
    ]);
  });

  it("limits teachers to teacher_note + progress (never admin comments)", async () => {
    const teacherActor = { userId: "teacher-a", role: "teacher" as const };
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: ["teacher-a"],
          },
        ],
      },
      { rows: [] },
    ]);

    await service.listComments(teacherActor, {
      entityType: "student",
      entityId: "student-a",
      limit: 5,
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(teacherActor, {
      profileUserId: "client-a",
      teacherUserIds: ["teacher-a"],
    });
    // Teacher sees their notes + progress, but NOT admin_comment.
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      ["teacher_note", "progress"],
      5,
    ]);
  });

  it("updates students through CRM write policy and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "student-a",
        status: "active",
        custom_data: { middleName: "Сергеевна", notes: "Важно" },
        profile_id: "profile-a",
        profile_user_id: "client-a",
        first_name: "Анна",
        last_name: "Иванова",
        email: "anna@example.com",
        phone: "+79990000000",
        created_at: "2026-06-01T00:00:00.000Z",
        teacher_user_ids: [],
      },
    ]);

    await expect(
      service.updateStudent(actor, "student-a", {
        firstName: " Анна ",
        lastName: " Иванова ",
        phone: " +79990000000 ",
        email: " ANNA@example.com ",
        customDataPatch: { middleName: "Сергеевна", notes: "Важно" },
      }),
    ).resolves.toMatchObject({
      id: "student-a",
      firstName: "Анна",
      lastName: "Иванова",
      email: "anna@example.com",
      customData: { middleName: "Сергеевна", notes: "Важно" },
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    // query.mock.calls[0] is the pre-select added by Task 2; the UPDATE CTE is now at index 1
    expect(query.mock.calls[1][1]).toEqual([
      "student-a",
      "Анна",
      "Иванова",
      "+79990000000",
      "anna@example.com",
      null,
      JSON.stringify({ middleName: "Сергеевна", notes: "Важно" }),
      null, // branch_id: no branchId UUID in customDataPatch
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_updated",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("searches students with CRM filters and account-link summary", async () => {
    const { service, query, policy } = createService([
      {
        id: "student-a",
        status: "active",
        custom_data: { discipline: "Вокал", branchId: "branch-a" },
        profile_id: "profile-a",
        profile_user_id: "technical-user-a",
        lead_id: null,
        first_name: "Анна",
        last_name: "Иванова",
        email: "anna@example.com",
        phone: "+79990000000",
        created_at: "2026-06-01T00:00:00.000Z",
        teacher_user_ids: [],
        branch_id: "branch-a",
        branch_name: "Центр",
        groups_count: "2",
        open_tasks_count: "1",
        lessons_count: "8",
        payments_total: "12000.00",
        linked_user_id: "client-a",
        linked_user_email: "client@example.com",
        is_app_account: true,
      },
    ]);

    await expect(
      service.searchStudents(actor, {
        q: "анна",
        branchId: "11111111-1111-4111-8111-111111111111",
        discipline: "Вокал",
        linkedUser: true,
        limit: 20,
      }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "student-a",
          firstName: "Анна",
          branchName: "Центр",
          groupsCount: 2,
          openTasksCount: 1,
          paymentsTotal: 12000,
          linkedUserId: "client-a",
          isAppAccount: true,
        }),
      ],
      totalCount: 1,
    });

    expect(policy.assertCanListStudents).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toContain("анна");
    expect(query.mock.calls[0][1]).toContain("Вокал");
    expect(query.mock.calls[0][1]).toContain(20);
  });

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

  it("creates comments for CRM writers after checking target entity", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "student",
            entity_id: "student-a",
            author_id: "manager-a",
            author_first_name: null,
            author_last_name: null,
            body: "Позвонить родителю",
            kind: "admin_comment",
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.createComment(actor, {
        entityType: "student",
        entityId: "student-a",
        body: " Позвонить родителю ",
      }),
    ).resolves.toEqual({
      id: "comment-a",
      entityType: "student",
      entityId: "student-a",
      authorId: "manager-a",
      authorName: null,
      body: "Позвонить родителю",
      kind: "admin_comment",
      progress: false,
      createdAt: "2026-06-12T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    // Default staff comment kind is admin_comment (no [PROGRESS] prefix).
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "manager-a",
      "Позвонить родителю",
      "admin_comment",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.comment_created",
        entityType: "student",
        entityId: "student-a",
        metadata: { commentId: "comment-a" },
      }),
    );
  });

  it("lets assigned teachers create progress comments for students", async () => {
    const teacherActor = { userId: "teacher-a", role: "teacher" as const };
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: ["teacher-a"],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "student",
            entity_id: "student-a",
            author_id: "teacher-a",
            author_first_name: null,
            author_last_name: null,
            body: "Хорошая динамика",
            kind: "progress",
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.createComment(teacherActor, {
        entityType: "student",
        entityId: "student-a",
        body: "Хорошая динамика",
        progress: true,
      }),
    ).resolves.toMatchObject({
      id: "comment-a",
      body: "Хорошая динамика",
      kind: "progress",
    });

    expect(policy.assertCanWriteCrm).not.toHaveBeenCalled();
    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(teacherActor, {
      profileUserId: "client-a",
      teacherUserIds: ["teacher-a"],
    });
    // progress=true resolves to kind='progress'; body stored verbatim.
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "teacher-a",
      "Хорошая динамика",
      "progress",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.comment_created",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("creates lessons with branch and room ids", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "lesson-a",
        student_id: "student-a",
        group_id: null,
        teacher_id: "teacher-a",
        branch_id: "branch-a",
        room_id: "room-a",
        scheduled_at: "2026-06-12T12:00:00.000Z",
        duration_minutes: 60,
        status: "scheduled",
        is_trial: false,
        notes: null,
        student_user_id: null,
        teacher_user_id: null,
        student_name: null,
        teacher_name: null,
        branch_name: null,
        room_name: null,
        group_name: null,
        group_price_per_lesson: null,
      },
    ]);

    await service.createLesson(actor, {
      studentId: "student-a",
      teacherId: "teacher-a",
      branchId: "branch-a",
      roomId: "room-a",
      scheduledAt: "2026-06-12T12:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "student-a",
      null,
      null,
      "teacher-a",
      "branch-a",
      "room-a",
      "2026-06-12T12:00:00.000Z",
      null,
      null,
      null,
      null,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lesson_created",
        entityId: "lesson-a",
      }),
    );
  });

  it("allows teachers to update only status and notes on their own lessons", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ teacher_user_id: "teacher-user-a" }] }, // access check
      {
        rows: [
          {
            teacher_id: "teacher-a",
            room_id: null,
            scheduled_at: "2026-06-12T12:00:00.000Z",
            teacher_user_id: "teacher-user-a",
          },
        ],
      }, // pre-update snapshot
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: "teacher-a",
            branch_id: null,
            room_id: null,
            scheduled_at: "2026-06-12T12:00:00.000Z",
            duration_minutes: 60,
            status: "completed",
            is_trial: false,
            notes: "План занятия",
            student_user_id: null,
            teacher_user_id: null,
            student_name: null,
            teacher_name: null,
            branch_name: null,
            room_name: null,
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      }, // UPDATE ... RETURNING
    ]);

    await expect(
      service.updateLesson(
        { userId: "teacher-user-a", role: "teacher" },
        "lesson-a",
        { status: "completed", notes: "План занятия" },
      ),
    ).resolves.toMatchObject({
      id: "lesson-a",
      status: "completed",
      notes: "План занятия",
    });

    expect(policy.assertCanWriteCrm).not.toHaveBeenCalled();
    expect(query.mock.calls[0][1]).toEqual(["lesson-a"]); // access check
    expect(query.mock.calls[1][1]).toEqual(["lesson-a"]); // pre-update snapshot
    expect(query.mock.calls[2][1]).toEqual([
      "lesson-a",
      null,
      null,
      null,
      null,
      null,
      null,
      undefined,
      null,
      "completed",
      null,
      "План занятия",
    ]);
  });

  it("soft-deletes a lesson and clears its reminder markers", async () => {
    const { service, query, policy, audit } = createServiceWithQueryResults([
      { rows: [{ id: "lesson-a" }] }, // update ... returning id
      { rows: [] }, // delete from lesson_reminders
    ]);
    const result = await service.deleteLesson(actor, "lesson-a");
    expect(result).toEqual({ success: true });
    expect(policy.assertCanWriteCrm).toHaveBeenCalled();
    expect(query.mock.calls[0][0]).toContain("set deleted_at = now()");
    expect(query.mock.calls[1][0]).toContain(
      "delete from app.lesson_reminders",
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lesson_deleted",
        entityId: "lesson-a",
      }),
    );
  });

  it("clears a lead's status when clearStatus is set (move to Без статуса)", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "s0", assigned_to: "o0", branch_id: "b0" }] }, // pre-select
      { rows: [{ id: "lead-1", status_id: null, assigned_to: "o0", source: "site", custom_data: {} }] }, // update ... returning
    ]);
    await service.updateLead(actor, "lead-1", { clearStatus: true } as never);
    // query.mock.calls[0] is the pre-select; the UPDATE is now at index 1
    const sql = query.mock.calls[1][0] as string;
    expect(sql).toContain("when $11::boolean then null");
    // 11th positional param ($11) carries the clearStatus flag.
    expect((query.mock.calls[1][1] as unknown[])[10]).toBe(true);
  });

  it("preserves a lead's status when clearStatus is not set", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "status-a", assigned_to: "o0", branch_id: "b0" }] }, // pre-select
      { rows: [{ id: "lead-1", status_id: "status-a", assigned_to: "o0", source: "site", custom_data: {} }] },
    ]);
    await service.updateLead(actor, "lead-1", {
      statusId: "11111111-1111-1111-1111-111111111111",
    } as never);
    // query.mock.calls[0] is the pre-select; the UPDATE is now at index 1
    expect((query.mock.calls[1][1] as unknown[])[10]).toBe(false);
  });

  it("records a lead_status_history row when status changes", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "old-status", assigned_to: "owner-1", branch_id: "branch-1" }] }, // pre-select
      { rows: [{ id: "lead-1", status_id: "new-status", assigned_to: "owner-1", source: "site", custom_data: {} }] }, // update returning
      { rows: [] }, // history insert
    ]);
    await service.updateLead(actor, "lead-1", { statusId: "new-status" } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.lead_status_history"));
    expect(insert).toBeDefined();
    const params = query.mock.calls.find((c) => String(c[0]).includes("insert into app.lead_status_history"))?.[1] as unknown[];
    expect(params).toEqual([
      "lead-1", "old-status", "new-status", "owner-1", "owner-1",
      actor.userId, null, null, "branch-1", "site",
    ]);
  });

  it("does NOT record lead_status_history when neither status nor owner changed", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "s1", assigned_to: "o1", branch_id: "b1" }] }, // pre-select
      { rows: [{ id: "lead-1", status_id: "s1", assigned_to: "o1", source: "site", custom_data: {} }] }, // update returning (unchanged)
    ]);
    await service.updateLead(actor, "lead-1", { firstName: "X" } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.lead_status_history"));
    expect(insert).toBeUndefined();
  });

  it("records a student_status_history row when status changes", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status: "active", branch_id: "b1" }] }, // pre-select
      {
        rows: [
          {
            id: "student-1",
            status: "paused",
            custom_data: { middleName: "Сергеевна", notes: "Важно" },
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      }, // updateStudent CTE
      { rows: [] }, // history insert
    ]);
    await service.updateStudent(actor, "student-1", { status: "paused" } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.student_status_history"));
    expect(insert).toBeDefined();
    const params = query.mock.calls.find((c) => String(c[0]).includes("insert into app.student_status_history"))?.[1] as unknown[];
    expect(params).toEqual(["student-1", "paused", "b1"]);
  });

  it("clears reminder markers when a lesson is rescheduled", async () => {
    // Manager actor: assertCanUpdateLesson returns without a query, so the
    // first DB call is the pre-update snapshot, then the UPDATE, then the
    // marker delete. The snapshot has no teacher_user_id so no teacher
    // notification fires here (keeping this test focused on reminders).
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            teacher_id: "teacher-a",
            room_id: null,
            scheduled_at: "2026-06-20T15:00:00.000Z",
            teacher_user_id: null,
          },
        ],
      }, // pre-update snapshot
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: "teacher-a",
            branch_id: null,
            room_id: null,
            scheduled_at: "2026-06-20T15:00:00.000Z",
            duration_minutes: 60,
            status: "scheduled",
            is_trial: false,
            notes: null,
            student_user_id: null,
            teacher_user_id: null,
            student_name: null,
            teacher_name: null,
            branch_name: null,
            room_name: null,
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      },
      { rows: [] }, // delete from app.lesson_reminders
    ]);

    await service.updateLesson(actor, "lesson-a", {
      scheduledAt: "2026-06-20T15:00:00.000Z",
    });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("delete from app.lesson_reminders"),
      ["lesson-a"],
    );
  });

  it("notifies the assigned teacher when a lesson is rescheduled (KVA-158)", async () => {
    // Pre-update snapshot has the OLD time + the teacher's user_id; the UPDATE
    // returns the NEW time. The time delta must trigger a teacher push/in_app.
    const { service, query, notifications } = createServiceWithQueryResults([
      {
        rows: [
          {
            teacher_id: "teacher-a",
            room_id: "room-a",
            scheduled_at: "2026-06-20T15:00:00.000Z",
            teacher_user_id: "teacher-user-a",
          },
        ],
      }, // pre-update snapshot
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: "teacher-a",
            branch_id: null,
            room_id: "room-a",
            scheduled_at: "2026-06-21T18:30:00.000Z",
            duration_minutes: 60,
            status: "scheduled",
            is_trial: false,
            notes: null,
            student_user_id: null,
            teacher_user_id: null,
            student_name: null,
            teacher_name: null,
            branch_name: null,
            room_name: null,
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      }, // UPDATE ... RETURNING
      { rows: [] }, // delete from app.lesson_reminders
    ]);

    await service.updateLesson(actor, "lesson-a", {
      scheduledAt: "2026-06-21T18:30:00.000Z",
    });

    expect(notifications.notifyUser).toHaveBeenCalledTimes(1);
    expect(notifications.notifyUser).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "teacher-user-a",
        title: "Перенос занятия",
        channels: ["push", "in_app"],
        data: { type: "lesson_rescheduled", lessonId: "lesson-a" },
      }),
    );
    const call = notifications.notifyUser.mock.calls[0][0];
    expect(call.body).toContain("время");
    expect(call.body).toContain("21.06");
    // The snapshot query must run before the UPDATE.
    expect(query.mock.calls[0][0]).toContain("from app.lessons l");
  });

  it("does not notify the teacher on a non-reschedule save (KVA-158)", async () => {
    // Only notes change; time / room / teacher are identical -> no notification.
    const { service, notifications } = createServiceWithQueryResults([
      {
        rows: [
          {
            teacher_id: "teacher-a",
            room_id: "room-a",
            scheduled_at: "2026-06-20T15:00:00.000Z",
            teacher_user_id: "teacher-user-a",
          },
        ],
      }, // pre-update snapshot
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: "teacher-a",
            branch_id: null,
            room_id: "room-a",
            scheduled_at: "2026-06-20T15:00:00.000Z",
            duration_minutes: 60,
            status: "scheduled",
            is_trial: false,
            notes: "Новая заметка",
            student_user_id: null,
            teacher_user_id: null,
            student_name: null,
            teacher_name: null,
            branch_name: null,
            room_name: null,
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      }, // UPDATE ... RETURNING
    ]);

    await service.updateLesson(actor, "lesson-a", {
      notes: "Новая заметка",
    });

    expect(notifications.notifyUser).not.toHaveBeenCalled();
  });

  it("notifies both the new and the removed teacher on a teacher swap (KVA-158)", async () => {
    // The lesson is reassigned from teacher-a (old) to teacher-b (new). The new
    // teacher gets the "Перенос занятия" push; the removed teacher must ALSO be
    // told they are detached via a distinct "Занятие переназначено" message.
    const { service, notifications } = createServiceWithQueryResults([
      {
        rows: [
          {
            teacher_id: "teacher-a",
            room_id: "room-a",
            scheduled_at: "2026-06-20T15:00:00.000Z",
            teacher_user_id: "teacher-user-a",
          },
        ],
      }, // pre-update snapshot (OLD teacher)
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: "teacher-b",
            branch_id: null,
            room_id: "room-a",
            scheduled_at: "2026-06-20T15:00:00.000Z",
            duration_minutes: 60,
            status: "scheduled",
            is_trial: false,
            notes: null,
            student_user_id: null,
            teacher_user_id: null,
            student_name: null,
            teacher_name: null,
            branch_name: null,
            room_name: null,
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      }, // UPDATE ... RETURNING (NEW teacher)
      { rows: [{ user_id: "teacher-user-b" }] }, // resolveTeacherUserId(new)
    ]);

    await service.updateLesson(actor, "lesson-a", {
      teacherId: "teacher-b",
    });

    expect(notifications.notifyUser).toHaveBeenCalledTimes(2);
    // NEW teacher keeps the existing reschedule notification.
    expect(notifications.notifyUser).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "teacher-user-b",
        title: "Перенос занятия",
        channels: ["push", "in_app"],
        data: { type: "lesson_rescheduled", lessonId: "lesson-a" },
      }),
    );
    // REMOVED teacher gets the new reassignment notification.
    expect(notifications.notifyUser).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "teacher-user-a",
        title: "Занятие переназначено",
        channels: ["push", "in_app"],
        data: { type: "lesson_reassigned", lessonId: "lesson-a" },
      }),
    );
    const removed = notifications.notifyUser.mock.calls.find(
      (c: { userId: string }[]) => c[0].userId === "teacher-user-a",
    );
    expect(removed?.[0].body).toContain("откреплены");
  });

  it("creates trial lessons linked to leads", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "lesson-lead-a",
        student_id: null,
        group_id: null,
        lead_id: "lead-a",
        teacher_id: "teacher-a",
        branch_id: null,
        room_id: "room-a",
        scheduled_at: "2026-06-13T10:00:00.000Z",
        duration_minutes: 60,
        status: "scheduled",
        is_trial: true,
        notes: "Пробное занятие",
        student_user_id: null,
        teacher_user_id: null,
        student_name: null,
        teacher_name: null,
        branch_name: null,
        room_name: null,
        group_name: null,
        group_price_per_lesson: null,
      },
    ]);

    await expect(
      service.createLesson(actor, {
        leadId: "lead-a",
        teacherId: "teacher-a",
        roomId: "room-a",
        scheduledAt: "2026-06-13T10:00:00.000Z",
        isTrial: true,
        notes: "Пробное занятие",
      }),
    ).resolves.toMatchObject({
      id: "lesson-lead-a",
      leadId: "lead-a",
      isTrial: true,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      null,
      null,
      "lead-a",
      "teacher-a",
      null,
      "room-a",
      "2026-06-13T10:00:00.000Z",
      null,
      null,
      true,
      "Пробное занятие",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lesson_created",
        entityId: "lesson-lead-a",
      }),
    );
  });

  it("soft deletes leads through CRM write policy", async () => {
    const { service, query, audit, policy } = createService([{ id: "lead-a" }]);

    await expect(service.deleteLead(actor, "lead-a")).resolves.toEqual({
      success: true,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["lead-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lead_deleted",
        entityType: "lead",
        entityId: "lead-a",
      }),
    );
  });

  it("resolves a lead chat user via an explicit crm link", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a", name: "Иван", phone: "+7 999 000-00-00" }] },
      { rows: [{ user_id: "user-x" }] },
    ]);
    const result = await service.resolveLeadChatUser(actor, "lead-a");
    expect(result).toEqual({ userId: "user-x", name: "Иван" });
  });

  it("resolves a lead chat user by matching phone when no link exists", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a", name: "Иван", phone: "+7 (999) 000-00-00" }] },
      { rows: [] },
      { rows: [{ user_id: "user-phone" }] },
    ]);
    const result = await service.resolveLeadChatUser(actor, "lead-a");
    expect(result.userId).toBe("user-phone");
  });

  it("returns null lead chat user when nothing matches", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a", name: "Иван", phone: null }] },
      { rows: [] },
    ]);
    const result = await service.resolveLeadChatUser(actor, "lead-a");
    expect(result.userId).toBeNull();
  });

  it("resolves a contact for a chat user, preferring crm links", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ entity_type: "lead", entity_id: "lead-1" }] },
      { rows: [] }, // no owned student
    ]);
    const result = await service.resolveContactForUser(actor, "user-x");
    expect(result).toEqual({ studentId: null, leadId: "lead-1" });
  });

  it("falls back to an owned student when a chat user has no crm links", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [] }, // no links
      { rows: [{ id: "student-9" }] }, // owned student via profile.user_id
    ]);
    const result = await service.resolveContactForUser(actor, "user-x");
    expect(result).toEqual({ studentId: "student-9", leadId: null });
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
    expect(query.mock.calls[0][1]).toEqual(["branch-a", null, null, 240]);
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
      createdAt: "2026-06-12T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.branches");
    expect(query.mock.calls[0][1]).toEqual(["Сокол", "Москва, Сокол", 240]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.branch_created",
        entityType: "branch",
        entityId: "branch-b",
        metadata: { utcOffsetMinutes: 240 },
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

    expect(query.mock.calls[0][1]).toEqual(["Новый", null, 180]);
  });

  it("rejects branch creation when name is blank", async () => {
    const { service, query } = createService();

    await expect(
      service.createBranch(actor, { name: "   " }),
    ).rejects.toThrow("Название филиала обязательно.");
    expect(query).not.toHaveBeenCalled();
  });

  it("returns payments with a correct server-side period total (not the page fold)", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          { id: "pay-1", student_id: "s1", amount: "500", currency: "RUB" },
          { id: "pay-2", student_id: "s1", amount: "700", currency: "RUB" },
        ],
      },
      { rows: [{ total_amount: "12345", total_count: "37" }] },
    ]);
    const result = await service.listPayments(actor, {});
    expect(result.items).toHaveLength(2);
    // The total reflects the full filtered set (37 payments / 12345), not the
    // sum of the returned page (1200).
    expect(result.totalAmount).toBe(12345);
    expect(result.totalCount).toBe(37);
  });

  it("save-from-chat returns the existing lead when already linked", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          {
            profile_id: "p1",
            user_id: "u1",
            first_name: "Иван",
            last_name: "П",
            phone: "+7 999 111-22-33",
          },
        ],
      },
      { rows: [{ entity_id: "lead-existing" }] },
    ]);
    const result = await service.saveContactFromChat(actor, {
      userId: "u1",
      as: "lead",
    });
    expect(result).toEqual({ leadId: "lead-existing", created: false });
  });

  it("save-from-chat returns the existing student for a known profile", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          {
            profile_id: "p1",
            user_id: "u1",
            first_name: "Иван",
            last_name: null,
            phone: null,
          },
        ],
      },
      { rows: [{ id: "student-existing" }] },
    ]);
    const result = await service.saveContactFromChat(actor, {
      userId: "u1",
      as: "student",
    });
    expect(result).toEqual({ studentId: "student-existing", created: false });
  });

  it("save-from-chat creates and links a new lead from a chat partner", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          {
            profile_id: "p1",
            user_id: "u1",
            first_name: "Иван",
            last_name: "П",
            phone: "+7 999 111-22-33",
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] }) // no existing link
      .mockResolvedValueOnce({ rows: [{ id: "status-new" }] }); // «Новый» status lookup (KVA-175)
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [{ id: "lead-new" }] }) // insert lead
      .mockResolvedValueOnce({ rows: [] }); // insert crm link
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = { assertCanWriteCrm: jest.fn() };
    const service = new CrmService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      {} as unknown as HolliHopMetadataService,
      {} as unknown as NotificationsService,
      {} as unknown as RealtimeBus,
    );
    const result = await service.saveContactFromChat(actor, {
      userId: "u1",
      as: "lead",
    });
    expect(result).toEqual({ leadId: "lead-new", created: true });
    expect(clientQuery).toHaveBeenCalledTimes(2);
    // KVA-175: the new lead is stamped with the «Новый» funnel status so it
    // doesn't land in «Без статуса».
    expect(clientQuery.mock.calls[0][1]).toContain("status-new");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lead_created",
        entityId: "lead-new",
      }),
    );
  });

  it("counts open phone-review-queue rows", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ count: "55" }] },
    ]);
    const result = await service.countPhoneReviewQueue(actor);
    expect(result).toEqual({ count: 55 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.phone_review_queue");
    expect(query.mock.calls[0][0]).toContain("resolved_at is null");
  });

  it("lists open phone-review-queue rows", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "q1",
            entity_type: "lead",
            entity_id: "l1",
            raw_phone: "123",
            reason: "too_short",
            created_at: "2026-06-19T00:00:00.000Z",
          },
        ],
      },
    ]);
    const result = await service.listPhoneReviewQueue(actor, 25);
    expect(result.items[0]).toEqual({
      id: "q1",
      entityType: "lead",
      entityId: "l1",
      rawPhone: "123",
      reason: "too_short",
      createdAt: "2026-06-19T00:00:00.000Z",
    });
    expect(query.mock.calls[0][1]).toEqual([25]);
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.phone_review_queue");
    expect(query.mock.calls[0][0]).toContain("resolved_at is null");
  });

  it("creates a discipline", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "d9", name: "Скрипка" }] },
    ]);
    const result = await service.createDiscipline(actor, { name: "Скрипка" });
    expect(result).toEqual({ id: "d9", name: "Скрипка" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.disciplines");
    expect(query.mock.calls[0][1]).toEqual(["Скрипка"]);
  });

  it("reorders branch disciplines by array position", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [], rowCount: 2 } as unknown as { rows: Record<string, unknown>[] },
    ]);
    const result = await service.reorderBranchDisciplines(actor, "branch-1", {
      disciplineIds: ["d2", "d1"],
    });
    expect(result).toEqual({ updated: 2 });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("with ordinality");
    expect(query.mock.calls[0][1]).toEqual(["branch-1", ["d2", "d1"]]);
  });

  it("reorders lead statuses by array position through CRM write policy", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      { rows: [], rowCount: 3 } as unknown as {
        rows: Record<string, unknown>[];
      },
    ]);
    const result = await service.reorderLeadStatuses(actor, {
      statusIds: ["status-c", "status-a", "status-b"],
    });
    expect(result).toEqual({ updated: 3 });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_statuses");
    expect(query.mock.calls[0][0]).toContain("with ordinality");
    expect(query.mock.calls[0][0]).toContain("sort_order = t.ord - 1");
    expect(query.mock.calls[0][1]).toEqual([
      ["status-c", "status-a", "status-b"],
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lead_statuses_reordered",
        entityType: "lead",
        metadata: { order: ["status-c", "status-a", "status-b"] },
      }),
    );
  });

  it("rejects lead status reorder when the id list is empty", async () => {
    const { service, query, policy } = createServiceWithQueryResults([]);
    await expect(
      service.reorderLeadStatuses(actor, { statusIds: [] }),
    ).rejects.toThrow("Список статусов воронки пуст.");
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query).not.toHaveBeenCalled();
  });

  it("assignBranchDiscipline upserts with conflict preservation and returns DTO", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "bd1", discipline_id: "d1", sort_order: 3 }] },
    ]);
    const result = await service.assignBranchDiscipline(actor, "branch-1", {
      disciplineId: "d1",
    });
    expect(result).toEqual({ id: "bd1", disciplineId: "d1", sortOrder: 3 });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
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
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.lead_loss_reasons");
    expect(query.mock.calls[0][1]).toEqual(["Тест", "lost", 0]);
  });

  it("resolveLeadChatUser phone-lookup SQL uses +7 canonical expression (regression KVA-184)", async () => {
    // Query sequence for resolveLeadChatUser when there is no explicit link
    // and we fall through to the phone-based profile lookup:
    //   [0] fetch lead row
    //   [1] check user_crm_links — returns nothing
    //   [2] look up profile by normalised phone
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [{ id: "lead-a", name: "Иван Петров", phone: "89091234567" }],
      },
      { rows: [] }, // no explicit user_crm_link
      { rows: [] }, // phone lookup – result doesn't matter for this assertion
    ]);

    await service.resolveLeadChatUser(actor, "lead-a");

    // The third query (index 2) is the phone-match SELECT.
    const phoneMatchSql: string = query.mock.calls[2][0];
    const phoneMatchParam: string = query.mock.calls[2][1][0];

    // The bound parameter must be the +7 canonical produced by normalizePhoneRu.
    expect(phoneMatchParam).toBe("+79091234567");

    // The SQL must use normalizedPhoneExpr which wraps a CASE that produces the
    // '+7' canonical, so both sides of the equality are in the same form.
    // A bare digit-only expression (regexp_replace ... '[^0-9]' ... = $1) would
    // never match a +7-prefixed param; the CASE form is required.
    expect(phoneMatchSql).toContain("'+7'");
    // The expression must appear inside a CASE block (not as a bare equality).
    expect(phoneMatchSql).toContain("case");
  });

  it("lead board branch filter prefers the branch_id column", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // statuses
      { rows: [] }, // count rows
      { rows: [] }, // board rows
    ]);
    await service.listLeadBoard(actor, { branchId: "b-1" } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("l.branch_id::text");
  });

  it("student search branch filter prefers the branch_id column", async () => {
    const { service, query } = createServiceWithQueryResults([{ rows: [] }]);
    await service.searchStudents(actor, { branchId: "b-1" } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("s.branch_id::text");
  });

  it("dual-writes branch_id column when customDataPatch carries a branchId", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ id: "lead-1" }] },
    ]);
    await service.createLead(actor, {
      firstName: "A",
      customDataPatch: { branchId: "44444444-4444-4444-4444-444444444444" },
    } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.leads"));
    expect(insert).toContain("branch_id");
    const params = query.mock.calls.find((c) => String(c[0]).includes("insert into app.leads"))?.[1] as unknown[];
    expect(params).toContain("44444444-4444-4444-4444-444444444444");
  });

  it("lists a lead's status history newest-first", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "h1",
            old_status: "Новый",
            new_status: "Пробный Урок",
            old_owner_id: null,
            new_owner_id: "u1",
            changed_by: "u1",
            changed_at: "2026-06-19T00:00:00.000Z",
            reason_id: null,
            comment: null,
          },
        ],
      },
    ]);
    const result = await service.listLeadStatusHistory(actor, "lead-1");
    expect(result.items[0]).toEqual({
      id: "h1",
      oldStatus: "Новый",
      newStatus: "Пробный Урок",
      oldOwnerId: null,
      newOwnerId: "u1",
      changedBy: "u1",
      changedAt: "2026-06-19T00:00:00.000Z",
      reasonId: null,
      comment: null,
    });
    expect(result.items).toHaveLength(1);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_status_history");
    expect(query.mock.calls[0][1]).toEqual(["lead-1"]);
  });

  it("creates a family", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ id: "fam-1", name: "Ивановы", branch_id: "b1" }] },
    ]);
    const result = await service.createFamily(actor, { name: "Ивановы", branchId: "b1" });
    expect(result).toEqual({ id: "fam-1", name: "Ивановы", branchId: "b1" });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("insert into app.families");
    expect(query.mock.calls[0][1]).toEqual(["Ивановы", "b1"]);
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
    expect(query.mock.calls[0][1]).toEqual(["student", "s1"]);
    expect(query.mock.calls[1][1]).toEqual(["fam-1"]);
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
      { rows: [], rowCount: 1 } as unknown as { rows: Record<string, unknown>[] },
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

  it("rejects customData nested beyond the depth limit", () => {
    const { service } = createServiceWithQueryResults([]);
    let deep: unknown = "x";
    for (let i = 0; i < 9; i++) deep = { nested: deep };
    expect(() =>
      (service as unknown as { sanitizeJsonObject: (v: unknown) => unknown }).sanitizeJsonObject(deep),
    ).toThrow(BadRequestException);
  });

  it("rejects customData with too many keys", () => {
    const { service } = createServiceWithQueryResults([]);
    const big: Record<string, unknown> = {};
    for (let i = 0; i < 200; i++) big["k" + i] = i;
    expect(() =>
      (service as unknown as { sanitizeJsonObject: (v: unknown) => unknown }).sanitizeJsonObject(big),
    ).toThrow(BadRequestException);
  });

  it("accepts reasonable customData", () => {
    const { service } = createServiceWithQueryResults([]);
    expect(
      (service as unknown as { sanitizeJsonObject: (v: unknown) => unknown }).sanitizeJsonObject({
        a: 1,
        b: { c: "ok" },
      }),
    ).toEqual({ a: 1, b: { c: "ok" } });
  });

  it("getMySummary includes family-linked children and dedups own students (KVA-156)", async () => {
    const clientActor = { userId: "parent-user-a", role: "client" as const };
    const { service, query } = createServiceWithQueryResults([
      // 1) own students (account-holder's own student records)
      {
        rows: [
          {
            id: "student-own",
            lead_id: null,
            status: "active",
            custom_data: null,
            profile_id: "profile-own",
            profile_user_id: "parent-user-a",
            first_name: "Иван",
            last_name: "Иванов",
            email: "parent@example.com",
            phone: null,
            teacher_user_ids: [],
            created_at: "2026-06-01T00:00:00.000Z",
          },
        ],
      },
      // 2) family-linked students: one new child + the own student again (dedup target)
      {
        rows: [
          {
            id: "student-child",
            lead_id: null,
            status: "active",
            custom_data: null,
            profile_id: "profile-child",
            profile_user_id: null,
            first_name: "Петя",
            last_name: "Иванов",
            email: null,
            phone: null,
            teacher_user_ids: [],
            created_at: "2026-06-02T00:00:00.000Z",
          },
          {
            id: "student-own",
            lead_id: null,
            status: "active",
            custom_data: null,
            profile_id: "profile-own",
            profile_user_id: "parent-user-a",
            first_name: "Иван",
            last_name: "Иванов",
            email: "parent@example.com",
            phone: null,
            teacher_user_ids: [],
            created_at: "2026-06-01T00:00:00.000Z",
          },
        ],
      },
      { rows: [] }, // 3) listLessons
      { rows: [] }, // 4) listTasks
      { rows: [] }, // 5) listPayments items
      { rows: [{ total_amount: "0", total_count: "0" }] }, // 6) listPayments total
    ]);

    const result = await service.getMySummary(clientActor);

    // Own + family-linked, deduped by student id (student-own listed once).
    expect(result.students.map((s) => s.id)).toEqual([
      "student-own",
      "student-child",
    ]);
    expect(result.students).toHaveLength(2);
    expect(result.students.find((s) => s.id === "student-child")?.firstName).toBe(
      "Петя",
    );

    // The family-discovery query gates on active families/members/students and
    // the parent/payer role of the account profile.
    const familyQuery = query.mock.calls[1][0] as string;
    expect(familyQuery).toContain("app.family_members");
    expect(familyQuery).toContain("app.families");
    expect(familyQuery).toContain("'parent', 'payer'");
    expect(familyQuery).toContain("child_m.entity_type = 'student'");
    expect(query.mock.calls[1][1]).toEqual(["parent-user-a"]);
  });

  const createMergeService = (results: { rows: Record<string, unknown>[] }[]) => {
    const query = jest.fn();
    for (const r of results) query.mockResolvedValueOnce(r);
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) => work({ query }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = { sendEmail: jest.fn().mockResolvedValue({ queued: true }) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const hollihop = {
      listDisciplines: jest.fn().mockResolvedValue({ configured: false, items: [] }),
      listLevels: jest.fn().mockResolvedValue({ configured: false, items: [] }),
      listCategories: jest.fn().mockResolvedValue({ configured: false, items: [] }),
      listLeadStatuses: jest.fn().mockResolvedValue({ configured: false, items: [] }),
    };
    const service = new CrmService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      hollihop as unknown as HolliHopMetadataService,
      notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
    );
    return { service, query, transaction, policy };
  };

  it("lists lead merge candidates by phone + name", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ loser_id: "l-lo", winner_id: "l-wi", phone: "+79091234567", name: "Иван Иванов" }] },
    ]);
    const result = await service.listMergeCandidates(actor);
    expect(result.items[0]).toEqual({ loserId: "l-lo", winnerId: "l-wi", phone: "+79091234567", name: "Иван Иванов" });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("phone_normalized");
  });

  it("mergeLeads re-points references, soft-deletes the loser, and logs", async () => {
    const { service, query, transaction, policy } = createMergeService([
      { rows: [{ id: "l-lo" }, { id: "l-wi" }] }, // validate both exist
      { rows: [{ id: "s1" }] },                    // students.lead_id
      { rows: [{ id: "le1" }] },                   // lessons.lead_id
      { rows: [{ id: "h1" }] },                    // lead_status_history.lead_id
      { rows: [] },                                // lead_comments.lead_id
      { rows: [{ id: "t1" }] },                    // tasks.entity_id
      { rows: [] },                                // entity_comments.entity_id
      { rows: [{ id: "ch1" }] },                   // chats.lead_id
      { rows: [{ id: "dc1" }] },                   // duplicate_candidates -> merged
      { rows: [] },                                // soft-delete loser
      { rows: [{ id: "ml1" }] },                   // insert merge_log
    ]);
    const result = await service.mergeLeads(actor, "l-lo", "l-wi");
    expect(result).toEqual({ mergeLogId: "ml1", winnerId: "l-wi" });
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("update app.students set lead_id");
    expect(sql).toContain("update app.chats set lead_id");
    expect(sql).toContain("update app.leads set deleted_at = now()");
    expect(sql).toContain("insert into app.merge_log");
    // merge_log insert carries the captured repointed ids
    const mlInsert = query.mock.calls.find((c) => String(c[0]).includes("insert into app.merge_log"));
    expect(JSON.stringify(mlInsert?.[1])).toContain("students.lead_id");
  });

  it("mergeLeads rejects merging a lead into itself", async () => {
    const { service } = createMergeService([]);
    await expect(service.mergeLeads(actor, "same", "same")).rejects.toThrow(BadRequestException);
  });

  it("undoMerge reverses captured rows, restores the loser, and stamps undone", async () => {
    const repointed = { "students.lead_id": ["s1"], "duplicate_candidates.status": ["dc1"] };
    const { service, query, policy } = createMergeService([
      { rows: [{ loser_id: "l-lo", repointed }] }, // select merge_log
      { rows: [] }, // reverse students.lead_id
      { rows: [] }, // reverse duplicate_candidates.status
      { rows: [] }, // restore loser deleted_at = null
      { rows: [] }, // update merge_log undone_at/undone_by
    ]);
    const result = await service.undoMerge(actor, "ml1");
    expect(result).toEqual({ success: true });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("update app.students set lead_id = $1");
    expect(sql).toContain("set deleted_at = null");
    expect(sql).toContain("update app.merge_log set undone_at = now()");
    // duplicate_candidates reverse binds [null, ids]; students reverse binds [loser_id, ids]
    const dupCall = query.mock.calls.find((c) => String(c[0]).includes("app.duplicate_candidates"));
    expect((dupCall?.[1] as unknown[])[0]).toBeNull();
    const studCall = query.mock.calls.find((c) => String(c[0]).includes("update app.students set lead_id"));
    expect((studCall?.[1] as unknown[])[0]).toBe("l-lo");
    expect((studCall?.[1] as unknown[])[1]).toEqual(["s1"]);
  });

  it("undoMerge 404s when the merge is missing or already undone", async () => {
    const { service } = createMergeService([{ rows: [] }]); // select merge_log → none
    await expect(service.undoMerge(actor, "missing")).rejects.toThrow(NotFoundException);
  });

  it("autoCreateLeadFromChat is idempotent when the user is already linked", async () => {
    // All queries now happen inside database.transaction via a client mock.
    // Sequence inside the transaction:
    //   [0] pg_advisory_xact_lock  → void
    //   [1] user_crm_links lookup  → already-linked row
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({ rows: [{ entity_type: "lead", entity_id: "lead-existing" }] }); // crm links
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const service = new CrmService(
      { transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      {} as unknown as HolliHopMetadataService,
      {} as unknown as NotificationsService,
      {} as unknown as RealtimeBus,
    );
    const result = await service.autoCreateLeadFromChat(actor, "user-1");
    expect(result).toEqual({ leadId: "lead-existing", created: false });
    // The advisory lock MUST be the first in-transaction statement.
    const lockSql = String(clientQuery.mock.calls[0][0]);
    expect(lockSql).toContain("pg_advisory_xact_lock");
    // No lead insert should have happened.
    const allSql = clientQuery.mock.calls.map((c: unknown[]) => String(c[0])).join("\n");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("autoCreateLeadFromChat creates a lead and link when user is not yet linked", async () => {
    // All queries now happen inside database.transaction via a client mock.
    // Sequence inside the transaction:
    //   [0] pg_advisory_xact_lock  → void
    //   [1] user_crm_links lookup  → empty (not linked)
    //   [2] profile lookup         → profile row
    //   [3] lead_statuses lookup   → status row
    //   [4] insert into app.leads  → new lead id
    //   [5] insert into user_crm_links → void
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({ rows: [] }) // user_crm_links → not linked
      .mockResolvedValueOnce({ rows: [{ first_name: "Иван", last_name: "Петров", phone: "+79991234567" }] }) // profile
      .mockResolvedValueOnce({ rows: [{ id: "status-new" }] }) // lead_statuses
      .mockResolvedValueOnce({ rows: [{ id: "lead-new" }] }) // insert lead
      .mockResolvedValueOnce({ rows: [] }); // insert crm link
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const service = new CrmService(
      { transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      {} as unknown as HolliHopMetadataService,
      {} as unknown as NotificationsService,
      {} as unknown as RealtimeBus,
    );
    const result = await service.autoCreateLeadFromChat(actor, "user-1");
    expect(result).toEqual({ leadId: "lead-new", created: true });
    expect(clientQuery).toHaveBeenCalledTimes(6);
    // Advisory lock is the first in-transaction statement.
    const lockSql = String(clientQuery.mock.calls[0][0]);
    expect(lockSql).toContain("pg_advisory_xact_lock");
    // Status lookup contains 'новый' — assert by content, not by position index.
    const statusCall = clientQuery.mock.calls.find((c: unknown[]) =>
      String(c[0]).includes("новый"),
    );
    expect(statusCall).toBeDefined();
    expect(String(statusCall![0])).toContain("'новый'");
    // Lead insert contains the source string.
    const insertCall = clientQuery.mock.calls.find((c: unknown[]) =>
      String(c[0]).includes("insert into app.leads"),
    );
    expect(insertCall).toBeDefined();
    expect(String(insertCall![0])).toContain("'Через приложение'");
    // Link insert contains link_source.
    const linkCall = clientQuery.mock.calls.find((c: unknown[]) =>
      String(c[0]).includes("insert into app.user_crm_links"),
    );
    expect(linkCall).toBeDefined();
    expect(String(linkCall![0])).toContain("'auto_phone'");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lead_created",
        entityType: "lead",
        entityId: "lead-new",
        metadata: expect.objectContaining({ fromApp: true, userId: "user-1" }),
      }),
    );
  });

  it("autoCreateLeadFromChat returns {leadId:null, created:false} when user has no profile", async () => {
    // Sequence inside the transaction:
    //   [0] pg_advisory_xact_lock  → void
    //   [1] user_crm_links lookup  → empty (not linked)
    //   [2] profile lookup         → empty (no profile)
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({ rows: [] }) // user_crm_links → not linked
      .mockResolvedValueOnce({ rows: [] }); // profile → missing
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const service = new CrmService(
      { transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      {} as unknown as HolliHopMetadataService,
      {} as unknown as NotificationsService,
      {} as unknown as RealtimeBus,
    );
    const result = await service.autoCreateLeadFromChat(actor, "user-no-profile");
    expect(result).toEqual({ leadId: null, created: false });
    // No lead should have been inserted.
    const allSql = clientQuery.mock.calls.map((c: unknown[]) => String(c[0])).join("\n");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("counts app-sourced leads", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ count: "7" }] },
    ]);
    const result = await service.countAppLeads(actor);
    expect(result).toEqual({ count: 7 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("'Через приложение'");
  });

  it("creates expenses through CRM write policy and audit (P5-5)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "exp-a",
        amount: "1500.00",
        category: "rent",
        description: "Аренда",
        branch_id: "branch-a",
        branch_name: null,
        created_at: "2026-06-22T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createExpense(actor, {
        amount: 1500,
        category: " rent ",
        description: " Аренда ",
        branchId: "branch-a",
      }),
    ).resolves.toEqual({
      id: "exp-a",
      amount: 1500,
      category: "rent",
      description: "Аренда",
      branchId: "branch-a",
      branchName: null,
      createdAt: "2026-06-22T00:00:00.000Z",
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([1500, "rent", "Аренда", "branch-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.expense_created",
        entityType: "expense",
        entityId: "exp-a",
      }),
    );
  });

  it("is idempotent for duplicate payment submits within the window", async () => {
    const paymentRow = {
      id: "pay-a",
      student_id: "student-a",
      student_user_id: null,
      amount: "1500.00",
      student_first_name: null,
      student_last_name: null,
      currency: "RUB",
      payment_date: "2026-06-23",
      method: "cash",
      external_id: null,
      notes: null,
      created_by: "manager-a",
      created_at: "2026-06-23T00:00:00.000Z",
    };
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // 1st: dup-check empty
      { rows: [paymentRow] }, // insert
      { rows: [paymentRow] }, // 2nd: dup-check returns existing
    ]);
    const dto = {
      studentId: "student-a",
      amount: 1500,
      paymentDate: "2026-06-23",
      method: "cash",
    } as never;

    const first = await service.createPayment(actor, dto);
    const second = await service.createPayment(actor, dto);

    expect(first.id).toBe("pay-a");
    expect(second.id).toBe("pay-a");
    // dup-check, insert, dup-check — the second submit must NOT insert again.
    expect(query).toHaveBeenCalledTimes(3);
  });

  it("lists expenses with branch/category filters and a total (P5-5)", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "exp-a",
            amount: "1500.00",
            category: "rent",
            description: null,
            branch_id: "branch-a",
            branch_name: "Центр",
            created_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
      { rows: [{ total: "1500.00" }] },
    ]);

    const result = await service.listExpenses(actor, {
      branchId: "branch-a",
      category: "rent",
      limit: 50,
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(result.total).toBe(1500);
    expect(result.items).toEqual([
      {
        id: "exp-a",
        amount: 1500,
        category: "rent",
        description: null,
        branchId: "branch-a",
        branchName: "Центр",
        createdAt: "2026-06-22T00:00:00.000Z",
      },
    ]);
    // items query: branch + category filters then the limit param last.
    expect(query.mock.calls[0][1]).toEqual(["branch-a", "rent", 50]);
    // total query reuses the filter params WITHOUT the limit.
    expect(query.mock.calls[1][1]).toEqual(["branch-a", "rent"]);
  });

  it("soft-deletes expenses and 404s when missing (P5-5)", async () => {
    const { service, query, audit } = createService([{ id: "exp-a" }]);
    await expect(service.deleteExpense(actor, "exp-a")).resolves.toEqual({
      success: true,
    });
    expect(query.mock.calls[0][0]).toContain("set deleted_at = now()");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.expense_deleted" }),
    );

    const missing = createService([]);
    await expect(
      missing.service.deleteExpense(actor, "exp-x"),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it("creates subscription packages through CRM write policy and audit (P5b)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "pkg-a",
        name: "8 уроков",
        discipline_id: null,
        branch_id: "branch-a",
        lessons_total: 8,
        price: "8000.00",
        validity_days: 60,
        is_active: true,
        sort_order: 0,
        created_at: "2026-06-22T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createSubscriptionPackage(actor, {
        name: " 8 уроков ",
        branchId: "branch-a",
        lessonsTotal: 8,
        price: 8000,
        validityDays: 60,
      }),
    ).resolves.toEqual({
      id: "pkg-a",
      name: "8 уроков",
      disciplineId: null,
      branchId: "branch-a",
      lessonsTotal: 8,
      price: 8000,
      validityDays: 60,
      isActive: true,
      sortOrder: 0,
      createdAt: "2026-06-22T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "8 уроков",
      null,
      "branch-a",
      8,
      8000,
      60,
      null,
      null,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_package_created",
        entityType: "subscription_package",
        entityId: "pkg-a",
      }),
    );
  });

  it("issues a subscription from a package atomically with audit (P5b)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "sub-a",
        lessons_total: 8,
        lessons_used: 0,
        starts_at: "2026-06-22",
        expires_at: "2026-08-21",
        status: "active",
        package_id: "pkg-a",
        payment_id: "pay-a",
      },
    ]);

    await expect(
      service.issueSubscription(actor, "student-a", { packageId: "pkg-a" }),
    ).resolves.toEqual({
      id: "sub-a",
      studentId: "student-a",
      lessonsTotal: 8,
      lessonsUsed: 0,
      startsAt: "2026-06-22",
      expiresAt: "2026-08-21",
      status: "active",
      packageId: "pkg-a",
      paymentId: "pay-a",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("insert into app.payments");
    expect(sql).toContain("insert into app.subscriptions");
    expect(query.mock.calls[0][1]).toEqual(["student-a", "pkg-a", "manager-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_issued",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("counts a subscription lesson when a student is marked present (P5b-4)", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            teacher_user_id: "teacher-user-a",
          },
        ],
      },
      {
        rows: [
          { student_id: "student-a", first_name: "Анна", last_name: "Иванова" },
        ],
      },
      { rows: [] },
      { rows: [] },
      { rows: [] },
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            teacher_user_id: "teacher-user-a",
          },
        ],
      },
      {
        rows: [
          { student_id: "student-a", first_name: "Анна", last_name: "Иванова" },
        ],
      },
      {
        rows: [
          { student_id: "student-a", status: "present", pass_reason: null },
        ],
      },
    ]);

    await service.upsertLessonAttendance(actor, "lesson-a", {
      items: [{ studentId: "student-a", status: "present" }],
    });

    // The reconciliation query (call index 3) decrements an active subscription.
    const reconcileSql = String(query.mock.calls[3][0]);
    expect(reconcileSql).toContain("lessons_used = lessons_used + 1");
    expect(query.mock.calls[3][1]).toEqual(["lesson-a", "student-a"]);
  });

  it("creates a homework through operational-data policy and audit (P5c)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "hw-a",
        lesson_id: "lesson-a",
        student_id: "student-a",
        assigned_by: "manager-a",
        title: "Гаммы",
        description: "До-мажор",
        status: "assigned",
        due_at: "2026-06-30T00:00:00.000Z",
        created_at: "2026-06-22T00:00:00.000Z",
        updated_at: "2026-06-22T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createHomework(actor, {
        studentId: "student-a",
        lessonId: "lesson-a",
        title: " Гаммы ",
        description: " До-мажор ",
        dueAt: "2026-06-30T00:00:00.000Z",
      }),
    ).resolves.toEqual({
      id: "hw-a",
      lessonId: "lesson-a",
      studentId: "student-a",
      assignedBy: "manager-a",
      title: "Гаммы",
      description: "До-мажор",
      status: "assigned",
      dueAt: "2026-06-30T00:00:00.000Z",
      createdAt: "2026-06-22T00:00:00.000Z",
      updatedAt: "2026-06-22T00:00:00.000Z",
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("insert into app.lesson_homeworks");
    expect(query.mock.calls[0][1]).toEqual([
      "lesson-a",
      "student-a",
      "manager-a",
      "Гаммы",
      "До-мажор",
      "2026-06-30T00:00:00.000Z",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_assigned",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("lists homeworks for staff with student/status filters (P5c)", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "hw-a",
            lesson_id: null,
            student_id: "student-a",
            assigned_by: "manager-a",
            title: "Гаммы",
            description: null,
            status: "assigned",
            due_at: null,
            created_at: "2026-06-22T00:00:00.000Z",
            updated_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
    ]);

    const result = await service.listHomeworks(actor, {
      studentId: "student-a",
      status: "assigned",
      limit: 50,
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toEqual(
      expect.objectContaining({ id: "hw-a", studentId: "student-a" }),
    );
    // student filter, status filter, then the limit param last.
    expect(query.mock.calls[0][1]).toEqual(["student-a", "assigned", 50]);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).not.toContain("p.user_id");
  });

  it("submits a homework as the owning client (P5c)", async () => {
    const clientActor = { userId: "client-user", role: "client" as const };
    const { service, query, audit } = createServiceWithQueryResults([
      // owner lookup
      { rows: [{ assigned_by: "manager-a", student_user_id: "client-user" }] },
      // status update
      {
        rows: [
          {
            id: "hw-a",
            lesson_id: null,
            student_id: "student-a",
            assigned_by: "manager-a",
            title: "Гаммы",
            description: null,
            status: "submitted",
            due_at: null,
            created_at: "2026-06-22T00:00:00.000Z",
            updated_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
    ]);

    const result = await service.submitHomework(clientActor, "hw-a");
    expect(result.status).toBe("submitted");
    const updateSql = String(query.mock.calls[1][0]);
    expect(updateSql).toContain("status = 'submitted'");
    expect(query.mock.calls[1][1]).toEqual(["hw-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_submitted",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("forbids submitting a homework owned by another client (P5c)", async () => {
    const clientActor = { userId: "other-user", role: "client" as const };
    const { service } = createServiceWithQueryResults([
      { rows: [{ assigned_by: "manager-a", student_user_id: "client-user" }] },
    ]);

    await expect(
      service.submitHomework(clientActor, "hw-a"),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("adds an assignment attachment through operational-data policy (P5c)", async () => {
    const { service, query, audit, policy } = createService([{ id: "att-a" }]);

    const result = await service.addHomeworkAttachment(actor, "hw-a", {
      fileId: "file-a",
      kind: "assignment",
    });

    expect(result).toEqual({
      id: "att-a",
      homeworkId: "hw-a",
      fileId: "file-a",
      kind: "assignment",
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("insert into app.homework_attachments");
    expect(query.mock.calls[0][1]).toEqual([
      "hw-a",
      "file-a",
      "manager-a",
      "assignment",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_attachment_added",
        entityType: "student",
        entityId: "hw-a",
      }),
    );
  });
});
