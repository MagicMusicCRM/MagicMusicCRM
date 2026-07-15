import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { TasksService } from "./tasks.service";
import { CrmPolicy } from "./crm.policy";
import { ScheduleService } from "./schedule.service";
import { TimelineService } from "./timeline.service";
import { CrmService } from "./crm.service";

describe("CrmService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = {
      query,
      transaction: jest.fn(async (fn: (client: { query: typeof query }) => unknown) =>
        fn({ query }),
      ),
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = {
      sendEmail: jest.fn().mockResolvedValue({ queued: true }),
      notifyUser: jest.fn().mockResolvedValue({ notificationId: "notif-test" }),
      notifyNewLead: jest.fn().mockResolvedValue(undefined),
    };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanReadStudentFinance: jest.fn(),
      canReadStudentFinance: jest.fn().mockReturnValue(true),
      // KVA-239: общешкольные финансы (director/system_admin)
      assertCanReadSchoolFinance: jest.fn(),
      canReadSchoolFinance: jest.fn().mockReturnValue(true),
      assertCanListStudents: jest.fn(),
      assertCanReadPayroll: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const subscriptions = {
      listSubscriptions: jest.fn().mockResolvedValue({ items: [] }),
    };
    const finance = {
      listPayments: jest
        .fn()
        .mockResolvedValue({ items: [], totalAmount: 0, totalCount: 0 }),
      listExpectedPayments: jest.fn().mockResolvedValue({ items: [] }),
      listStudentBalances: jest.fn().mockResolvedValue({ items: [] }),
    };
    const tasks = {
      listTasks: jest.fn().mockResolvedValue({ items: [] }),
    };
    const schedule = {
      listLessons: jest.fn().mockResolvedValue({ items: [] }),
    };
    const timeline = {
      listComments: jest.fn().mockResolvedValue({ items: [] }),
    };

    const service = new CrmService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      subscriptions as unknown as SubscriptionsService,
      finance as unknown as FinanceService,
      tasks as unknown as TasksService,
      schedule as unknown as ScheduleService,
      timeline as unknown as TimelineService,
      notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
    );

    return { service, query, audit, policy, subscriptions, finance, tasks, notifications, database };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const database = {
      query,
      transaction: jest.fn(async (fn: (client: { query: typeof query }) => unknown) =>
        fn({ query }),
      ),
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = {
      sendEmail: jest.fn().mockResolvedValue({ queued: true }),
      notifyUser: jest.fn().mockResolvedValue({ notificationId: "notif-test" }),
      notifyNewLead: jest.fn().mockResolvedValue(undefined),
    };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanReadStudentFinance: jest.fn(),
      canReadStudentFinance: jest.fn().mockReturnValue(true),
      // KVA-239: общешкольные финансы (director/system_admin)
      assertCanReadSchoolFinance: jest.fn(),
      canReadSchoolFinance: jest.fn().mockReturnValue(true),
      assertCanListStudents: jest.fn(),
      assertCanReadPayroll: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const subscriptions = {
      listSubscriptions: jest.fn().mockResolvedValue({ items: [] }),
    };
    const finance = {
      listPayments: jest
        .fn()
        .mockResolvedValue({ items: [], totalAmount: 0, totalCount: 0 }),
      listExpectedPayments: jest.fn().mockResolvedValue({ items: [] }),
      listStudentBalances: jest.fn().mockResolvedValue({ items: [] }),
    };
    const tasks = {
      listTasks: jest.fn().mockResolvedValue({ items: [] }),
    };
    const schedule = {
      listLessons: jest.fn().mockResolvedValue({ items: [] }),
    };
    const timeline = {
      listComments: jest.fn().mockResolvedValue({ items: [] }),
    };

    const service = new CrmService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      subscriptions as unknown as SubscriptionsService,
      finance as unknown as FinanceService,
      tasks as unknown as TasksService,
      schedule as unknown as ScheduleService,
      timeline as unknown as TimelineService,
      notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
    );

    return { service, query, audit, policy, subscriptions, finance, tasks, notifications, database };
  };

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

  it("lists group students through v3 contract", async () => {
    const { service, query, policy } = createService([
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

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["group-a", 10]);
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
      { rows: [] },
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
    expect(query).toHaveBeenCalledTimes(7);
  });

  const stubCardSections = (service: CrmService) => {
    jest.spyOn(service as unknown as { toStudentDto: () => unknown }, "toStudentDto").mockReturnValue({ id: "student-a" });
    jest.spyOn(service, "listStudentGroups").mockResolvedValue({ items: [] } as never);
    jest.spyOn(service as unknown as { listUserCrmLinks: () => Promise<unknown> }, "listUserCrmLinks").mockResolvedValue([]);
  };

  it("opens the student card for a non-finance role (teacher) without finance and never crashes", async () => {
    // findStudent is now a shared db read (student-read.ts) — seed its row via
    // the query mock instead of spying a method.
    const { service, policy, finance } = createService([
      { id: "student-a", profile_user_id: "user-a", teacher_user_ids: ["teacher-a"] },
    ]);
    (policy.canReadStudentFinance as jest.Mock).mockReturnValue(false);
    stubCardSections(service);

    const card = await service.getStudentCard(
      { userId: "teacher-a", role: "teacher" },
      "student-a",
    );

    expect(card.balance).toBeNull();
    expect(card.payments).toEqual([]);
    // Finance sections (now on FinanceService) are never queried for a non-finance role.
    expect(finance.listStudentBalances).not.toHaveBeenCalled();
    expect(finance.listPayments).not.toHaveBeenCalled();
    expect(finance.listExpectedPayments).not.toHaveBeenCalled();
  });

  it("never lets a forbidden/failed balance crash the student card for a finance reader (admin)", async () => {
    const { service, policy, finance } = createService([
      { id: "student-a", profile_user_id: "user-a", teacher_user_ids: [] },
    ]);
    (policy.canReadStudentFinance as jest.Mock).mockReturnValue(true);
    stubCardSections(service);
    (finance.listStudentBalances as jest.Mock).mockRejectedValue(
      new Error("balance forbidden"),
    );

    const card = await service.getStudentCard(
      { userId: "admin-a", role: "admin" },
      "student-a",
    );

    // Card still resolves; the failed balance degrades to null instead of 404.
    expect(card.balance).toBeNull();
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

  it("soft deletes students through CRM write policy (real undo)", async () => {
    const { service, query, audit, policy } = createService([
      { id: "student-a" },
    ]);

    await expect(service.deleteStudent(actor, "student-a")).resolves.toEqual({
      success: true,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["student-a"]);
    expect(String(query.mock.calls[0][0])).toContain("update app.students");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_deleted",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("deleteStudent throws when the student does not exist", async () => {
    const { service } = createService([]);
    await expect(service.deleteStudent(actor, "missing")).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it("returns a linked student back to its existing lead", async () => {
    const { service, query, audit, policy, database } =
      createServiceWithQueryResults([
        {
          rows: [
            {
              id: "student-a",
              lead_id: "lead-a",
              branch_id: "branch-a",
              custom_data: { sourceLeadId: "lead-a" },
              first_name: "Анна",
              last_name: "Иванова",
              email: "anna@example.com",
              phone: "+79990000000",
            },
          ],
        },
        { rows: [{ id: "lead-a" }] },
        { rows: [] },
      ]);

    await expect(
      service.returnStudentToLead(actor, "student-a"),
    ).resolves.toEqual({
      success: true,
      studentId: "student-a",
      leadId: "lead-a",
      createdLead: false,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(String(query.mock.calls[2][0])).toContain("update app.students");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_returned_to_lead",
        entityType: "student",
        entityId: "student-a",
        metadata: { leadId: "lead-a", createdLead: false },
      }),
    );
  });

  it("creates a lead when returning an unlinked student", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            lead_id: null,
            branch_id: "branch-a",
            custom_data: { discipline: "Вокал" },
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
          },
        ],
      },
      { rows: [{ id: "status-new" }] },
      { rows: [{ id: "lead-new" }] },
      { rows: [] },
    ]);

    await expect(
      service.returnStudentToLead(actor, "student-a"),
    ).resolves.toEqual({
      success: true,
      studentId: "student-a",
      leadId: "lead-new",
      createdLead: true,
    });

    expect(String(query.mock.calls[2][0])).toContain("insert into app.leads");
    expect(query.mock.calls[2][1]).toEqual([
      "status-new",
      "Анна",
      "Иванова",
      "+79990000000",
      "anna@example.com",
      JSON.stringify({ discipline: "Вокал", sourceStudentId: "student-a" }),
      "manager-a",
      "branch-a",
    ]);
  });

  it("searchStudents filters branchless students when noBranch is set", async () => {
    const { service, query } = createServiceWithQueryResults([{ rows: [] }]);
    await service.searchStudents(actor, { noBranch: true } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain(
      "coalesce(s.branch_id::text, s.custom_data->>'branchId', s.custom_data->>'branch_id') is null",
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
      {} as unknown as SubscriptionsService,
      {} as unknown as FinanceService,
      {} as unknown as TasksService,
      {} as unknown as ScheduleService,
      {} as unknown as TimelineService,
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

  it("lists a lead's applications newest-first (KVA-234)", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "app-1",
            applied_at: "2026-06-20T10:00:00.000Z",
            channel: "Заявка с сайта",
            office: "Сокол",
            discipline: "Вокал",
            status: "Новая",
            utm: { Source: "yandex", Medium: "cpc", Campaign: "brand", Referrer: null },
          },
        ],
      },
    ]);
    const result = await service.listLeadApplications(actor, "lead-1");
    expect(result.items).toEqual([
      {
        id: "app-1",
        appliedAt: "2026-06-20T10:00:00.000Z",
        channel: "Заявка с сайта",
        office: "Сокол",
        discipline: "Вокал",
        status: "Новая",
        utm: { Source: "yandex", Medium: "cpc", Campaign: "brand", Referrer: null },
      },
    ]);
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_applications");
    expect(query.mock.calls[0][0]).toContain("order by applied_at desc");
    expect(query.mock.calls[0][1]).toEqual(["lead-1"]);
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
      { rows: [] }, // 3) manually linked students
      { rows: [] }, // 4) listLessons
      { rows: [] }, // 5) listTasks
      { rows: [] }, // 6) listPayments items
      { rows: [{ total_amount: "0", total_count: "0" }] }, // 7) listPayments total
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

  it("getMySummary includes manually linked students", async () => {
    const clientActor = { userId: "client-linked", role: "client" as const };
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // 1) own students
      { rows: [] }, // 2) family-linked students
      {
        rows: [
          {
            id: "student-linked",
            lead_id: null,
            status: "active",
            custom_data: null,
            profile_id: "profile-student",
            profile_user_id: null,
            first_name: "Анна",
            last_name: "Связанная",
            email: null,
            phone: "+79990000001",
            teacher_user_ids: [],
            created_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
      { rows: [] }, // 4) listLessons
      { rows: [] }, // 5) listTasks
      { rows: [] }, // 6) listPayments items
      { rows: [{ total_amount: "0", total_count: "0" }] }, // 7) listPayments total
    ]);

    const result = await service.getMySummary(clientActor);

    expect(result.students.map((s) => s.id)).toEqual(["student-linked"]);
    const linkedQuery = String(query.mock.calls[2][0]);
    expect(linkedQuery).toContain("app.user_crm_links");
    expect(linkedQuery).toContain("link.user_id = $1");
    expect(linkedQuery).toContain("link.entity_type = 'student'");
    expect(query.mock.calls[2][1]).toEqual(["client-linked"]);
  });

  it("getMySummary still returns students when optional summary sections are forbidden", async () => {
    const clientActor = { userId: "client-a", role: "client" as const };
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            lead_id: null,
            status: "active",
            custom_data: null,
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Клиент",
            email: null,
            phone: null,
            teacher_user_ids: [],
            created_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
      { rows: [] }, // family-linked students
      { rows: [] }, // manually linked students
    ]);
    // recentPayments come from the (unspied) listClientSummaryPayments query,
    // which errors on the exhausted mock and degrades to [] via getMySummary's catch.

    await expect(service.getMySummary(clientActor)).resolves.toEqual(
      expect.objectContaining({
        students: [expect.objectContaining({ id: "student-a" })],
        upcomingLessons: [],
        tasks: [],
        recentPayments: [],
      }),
    );
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
      assertCanReadStudentFinance: jest.fn(),
      canReadStudentFinance: jest.fn().mockReturnValue(true),
      // KVA-239: общешкольные финансы (director/system_admin)
      assertCanReadSchoolFinance: jest.fn(),
      canReadSchoolFinance: jest.fn().mockReturnValue(true),
      assertCanListStudents: jest.fn(),
      assertCanReadPayroll: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const subscriptions = {
      listSubscriptions: jest.fn().mockResolvedValue({ items: [] }),
    };
    const finance = {
      listPayments: jest
        .fn()
        .mockResolvedValue({ items: [], totalAmount: 0, totalCount: 0 }),
      listExpectedPayments: jest.fn().mockResolvedValue({ items: [] }),
      listStudentBalances: jest.fn().mockResolvedValue({ items: [] }),
    };
    const tasks = {
      listTasks: jest.fn().mockResolvedValue({ items: [] }),
    };
    const schedule = {
      listLessons: jest.fn().mockResolvedValue({ items: [] }),
    };
    const timeline = {
      listComments: jest.fn().mockResolvedValue({ items: [] }),
    };
    const service = new CrmService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      subscriptions as unknown as SubscriptionsService,
      finance as unknown as FinanceService,
      tasks as unknown as TasksService,
      schedule as unknown as ScheduleService,
      timeline as unknown as TimelineService,
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
      assertCanReadStudentFinance: jest.fn(),
      canReadStudentFinance: jest.fn().mockReturnValue(true),
      // KVA-239: общешкольные финансы (director/system_admin)
      assertCanReadSchoolFinance: jest.fn(),
      canReadSchoolFinance: jest.fn().mockReturnValue(true),
      assertCanListStudents: jest.fn(),
      assertCanReadPayroll: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const service = new CrmService(
      { transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      {} as unknown as SubscriptionsService,
      {} as unknown as FinanceService,
      {} as unknown as TasksService,
      {} as unknown as ScheduleService,
      {} as unknown as TimelineService,
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
      assertCanReadStudentFinance: jest.fn(),
      canReadStudentFinance: jest.fn().mockReturnValue(true),
      // KVA-239: общешкольные финансы (director/system_admin)
      assertCanReadSchoolFinance: jest.fn(),
      canReadSchoolFinance: jest.fn().mockReturnValue(true),
      assertCanListStudents: jest.fn(),
      assertCanReadPayroll: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const service = new CrmService(
      { transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      {} as unknown as SubscriptionsService,
      {} as unknown as FinanceService,
      {} as unknown as TasksService,
      {} as unknown as ScheduleService,
      {} as unknown as TimelineService,
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
      assertCanReadStudentFinance: jest.fn(),
      canReadStudentFinance: jest.fn().mockReturnValue(true),
      // KVA-239: общешкольные финансы (director/system_admin)
      assertCanReadSchoolFinance: jest.fn(),
      canReadSchoolFinance: jest.fn().mockReturnValue(true),
      assertCanListStudents: jest.fn(),
      assertCanReadPayroll: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const service = new CrmService(
      { transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      {} as unknown as SubscriptionsService,
      {} as unknown as FinanceService,
      {} as unknown as TasksService,
      {} as unknown as ScheduleService,
      {} as unknown as TimelineService,
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

  describe("new lead notifications (KVA-240)", () => {
    it("createLead notifies staff about the new lead", async () => {
      const { service, notifications } = createServiceWithQueryResults([
        {
          rows: [
            { id: "lead-1", first_name: "Иван", last_name: "Петров", source: "site" },
          ],
        },
      ]);
      await service.createLead(actor, { firstName: "Иван" } as never);
      expect(notifications.notifyNewLead).toHaveBeenCalledWith({
        leadId: "lead-1",
        name: "Иван Петров",
        source: "site",
      });
    });

    it("createLead succeeds even when the notification fails", async () => {
      const { service, notifications } = createServiceWithQueryResults([
        { rows: [{ id: "lead-1", first_name: "Иван" }] },
      ]);
      notifications.notifyNewLead.mockRejectedValueOnce(new Error("boom"));
      await expect(
        service.createLead(actor, { firstName: "Иван" } as never),
      ).resolves.toMatchObject({ id: "lead-1" });
      expect(notifications.notifyNewLead).toHaveBeenCalledTimes(1);
    });

    it("webhook lead normalizes phone, stamps «Новый» and notifies staff", async () => {
      const { service, query, notifications, audit } = createServiceWithQueryResults([
        { rows: [{ id: "status-new" }] }, // lead_statuses «Новый»
        { rows: [{ id: "lead-web" }] }, // insert into app.leads
      ]);
      const result = await service.createLeadFromSiteWebhook({
        name: "Мария",
        phone: "8 (999) 123-45-67",
        discipline: "Вокал",
        comment: "Хочу пробное занятие",
      });
      expect(result).toEqual({ leadId: "lead-web" });
      const insert = query.mock.calls.find((c) =>
        String(c[0]).includes("insert into app.leads"),
      );
      expect(insert![1]).toEqual([
        "Мария",
        "+79991234567",
        null,
        "site",
        "Дисциплина: Вокал\nХочу пробное занятие",
        "status-new",
      ]);
      expect(notifications.notifyNewLead).toHaveBeenCalledWith({
        leadId: "lead-web",
        name: "Мария",
        source: "site",
      });
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "crm.lead_created",
          entityType: "lead",
          entityId: "lead-web",
          metadata: expect.objectContaining({ fromSiteWebhook: true }),
        }),
      );
    });
  });
});
