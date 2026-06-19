import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
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
    };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
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
    };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
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

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
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

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
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

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
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

    expect(query.mock.calls[0][0]).toContain("group_student_profile.user_id");
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

  it("limits staff creation to admins", async () => {
    const { service } = createService();

    await expect(
      service.createStaff(actor, {
        firstName: "Ольга",
        lastName: "Смирнова",
        email: "staff@example.com",
        role: "manager",
      }),
    ).rejects.toThrow("Только администратор");
  });

  it("creates staff profiles for admins", async () => {
    const adminActor = { userId: "admin-a", role: "admin" as const };
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
    const { service, query } = createService([
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
        },
      ],
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
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

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
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
            body: "[PROGRESS] Хорошая динамика",
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
          body: "[PROGRESS] Хорошая динамика",
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(
      { userId: "client-a", role: "client" },
      { profileUserId: "client-a", teacherUserIds: [] },
    );
    expect(query.mock.calls[1][1]).toEqual(["student", "student-a", true, 5]);
  });

  it("forces progress-only comments for teachers even when query omits filter", async () => {
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
    expect(query.mock.calls[1][1]).toEqual(["student", "student-a", true, 5]);
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
    expect(query.mock.calls[0][1]).toEqual([
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
      createdAt: "2026-06-12T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "manager-a",
      "Позвонить родителю",
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
            body: "[PROGRESS] Хорошая динамика",
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
      body: "[PROGRESS] Хорошая динамика",
    });

    expect(policy.assertCanWriteCrm).not.toHaveBeenCalled();
    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(teacherActor, {
      profileUserId: "client-a",
      teacherUserIds: ["teacher-a"],
    });
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "teacher-a",
      "[PROGRESS] Хорошая динамика",
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
      { rows: [{ teacher_user_id: "teacher-user-a" }] },
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
      },
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
    expect(query.mock.calls[0][1]).toEqual(["lesson-a"]);
    expect(query.mock.calls[1][1]).toEqual([
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
      { rows: [{ id: "lead-1", status_id: null }] }, // update ... returning
    ]);
    await service.updateLead(actor, "lead-1", { clearStatus: true } as never);
    const sql = query.mock.calls[0][0] as string;
    expect(sql).toContain("when $11::boolean then null");
    // 11th positional param ($11) carries the clearStatus flag.
    expect((query.mock.calls[0][1] as unknown[])[10]).toBe(true);
  });

  it("preserves a lead's status when clearStatus is not set", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ id: "lead-1", status_id: "status-a" }] },
    ]);
    await service.updateLead(actor, "lead-1", {
      statusId: "11111111-1111-1111-1111-111111111111",
    } as never);
    expect((query.mock.calls[0][1] as unknown[])[10]).toBe(false);
  });

  it("clears reminder markers when a lesson is rescheduled", async () => {
    // Manager actor: assertCanUpdateLesson returns without a query, so the
    // first DB call is the UPDATE, then the marker delete.
    const { service, query } = createServiceWithQueryResults([
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
      .mockResolvedValueOnce({ rows: [] }); // no existing link
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
    );
    const result = await service.saveContactFromChat(actor, {
      userId: "u1",
      as: "lead",
    });
    expect(result).toEqual({ leadId: "lead-new", created: true });
    expect(clientQuery).toHaveBeenCalledTimes(2);
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
});
