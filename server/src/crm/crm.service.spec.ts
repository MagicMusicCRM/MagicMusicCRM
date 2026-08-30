import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { StudentFunnelService } from "./student-funnel.service";
import { SharedTaskService } from "./tasks/shared-task.service";
import { CrmPolicy } from "./crm.policy";
import { ChatWorkTimelineService } from "../messenger/chat-work-timeline.service";
import { ScheduleReadService } from "./schedule/schedule-read.service";
import { TimelineService } from "./timeline.service";
import { CrmService } from "./crm.service";
import { StudentDirectoryService } from "./students/student-directory.service";
import { StudentSelfSummaryService } from "./students/student-self-summary.service";
import { StudentCardTimelineService } from "./students/student-card-timeline.service";
import { StudentMutationExecutor } from "./students/student-mutation.executor";
import { StudentCommandService } from "./students/student-command.service";
import {
  ACTIVE_RESPONSIBLE_STAFF_STATUSES,
  RESPONSIBLE_AUTH_ROLES,
} from "./responsible-eligibility";

describe("CrmService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = {
      query,
      transaction: jest.fn(
        async (fn: (client: { query: typeof query }) => unknown) =>
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
    const tasks = {
      list: jest.fn().mockResolvedValue({ items: [], counters: {} }),
    };
    const scheduleRead = {
      listUpcomingLessonsForStudents: jest.fn().mockResolvedValue([]),
      listLessons: jest.fn().mockResolvedValue({ items: [] }),
    };
    const timeline = {
      listComments: jest.fn().mockResolvedValue({ items: [] }),
      // Field-edit audit for the card history; empty for non-staff readers.
      listFieldAudit: jest.fn().mockResolvedValue({ items: [] }),
    };

    const directory = new StudentDirectoryService(
      database as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    const chatWork = {
      listForEntity: jest.fn().mockResolvedValue([]),
    } as unknown as ChatWorkTimelineService;
    const selfSummary = new StudentSelfSummaryService(
      database as unknown as DatabaseService,
      tasks as unknown as SharedTaskService,
      scheduleRead as unknown as ScheduleReadService,
    );
    const cardTimeline = new StudentCardTimelineService(
      database as unknown as DatabaseService,
      directory,
      scheduleRead as unknown as ScheduleReadService,
      tasks as unknown as SharedTaskService,
      timeline as unknown as TimelineService,
      chatWork,
    );
    const studentFunnel = {
      assertCreateStatus: jest.fn(),
      assertTransition: jest.fn(),
    } as unknown as StudentFunnelService;
    const studentMutations = new StudentMutationExecutor(
      database as unknown as DatabaseService,
      studentFunnel,
    );
    const realtime = {
      emitCrmChanged: () => undefined,
    } as unknown as RealtimeBus;
    const commands = new StudentCommandService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      notifications as unknown as NotificationsService,
      realtime,
      studentMutations,
    );
    const service = new CrmService(
      directory,
      selfSummary,
      cardTimeline,
      commands,
    );

    return {
      service,
      query,
      audit,
      policy,
      tasks,
      notifications,
      database,
      scheduleRead,
    };
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
      transaction: jest.fn(
        async (fn: (client: { query: typeof query }) => unknown) =>
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
    const tasks = {
      list: jest.fn().mockResolvedValue({ items: [], counters: {} }),
    };
    const scheduleRead = {
      listUpcomingLessonsForStudents: jest.fn().mockResolvedValue([]),
      listLessons: jest.fn().mockResolvedValue({ items: [] }),
    };
    const timeline = {
      listComments: jest.fn().mockResolvedValue({ items: [] }),
      // Field-edit audit for the card history; empty for non-staff readers.
      listFieldAudit: jest.fn().mockResolvedValue({ items: [] }),
    };

    const directory = new StudentDirectoryService(
      database as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    const chatWork = {
      listForEntity: jest.fn().mockResolvedValue([]),
    } as unknown as ChatWorkTimelineService;
    const selfSummary = new StudentSelfSummaryService(
      database as unknown as DatabaseService,
      tasks as unknown as SharedTaskService,
      scheduleRead as unknown as ScheduleReadService,
    );
    const cardTimeline = new StudentCardTimelineService(
      database as unknown as DatabaseService,
      directory,
      scheduleRead as unknown as ScheduleReadService,
      tasks as unknown as SharedTaskService,
      timeline as unknown as TimelineService,
      chatWork,
    );
    const studentFunnel = {
      assertCreateStatus: jest.fn(),
      assertTransition: jest.fn(),
    } as unknown as StudentFunnelService;
    const studentMutations = new StudentMutationExecutor(
      database as unknown as DatabaseService,
      studentFunnel,
    );
    const realtime = {
      emitCrmChanged: () => undefined,
    } as unknown as RealtimeBus;
    const commands = new StudentCommandService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      notifications as unknown as NotificationsService,
      realtime,
      studentMutations,
    );
    const service = new CrmService(
      directory,
      selfSummary,
      cardTimeline,
      commands,
    );

    return { service, query, audit, policy, tasks, notifications, database };
  };

  it("creates students through v3 identity/profile contract and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "student-a",
        version: 1,
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
      null, // source_id: legacy internal call has no validated source
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
      { rows: [] }, // advisory transaction lock
      { rows: [] }, // guarded duplicate check after acquiring the lock
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
    expect(query.mock.calls[4][1]).toEqual([
      "Анна",
      "Иванова",
      "anna@example.com",
      "Анна Иванова",
      "+79990000000",
      "active",
      "lead-a",
      JSON.stringify({ discipline: "Вокал", sourceLeadId: "lead-a" }),
      null, // branch_id: no branchId UUID in customDataPatch
      null, // source_id: legacy internal conversion path
    ]);
    const conversionSql = String(query.mock.calls[4][0]);
    expect(conversionSql).toContain("inserted_student_link as");
    expect(conversionSql).toContain("insert into app.user_crm_links");
    expect(conversionSql).toContain("on conflict do nothing");
    expect(String(query.mock.calls[2][0])).toContain("pg_advisory_xact_lock");
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

  it("rechecks conversion under an advisory transaction lock", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lead-a",
            custom_data: {},
            created_at: "2026-07-18T00:00:00.000Z",
          },
        ],
      },
      { rows: [] },
      { rows: [] },
      { rows: [{ id: "student-winner" }] },
    ]);

    await expect(
      service.createStudent(actor, {
        firstName: "Анна",
        leadId: "lead-a",
      }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(String(query.mock.calls[2][0])).toContain("pg_advisory_xact_lock");
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.users"),
      ),
    ).toBe(false);
  });

  it("lists group students through v3 contract", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ branch_id: "branch-a" }] },
      { rows: [{ branch_id: "branch-a" }] },
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
    expect(query.mock.calls[2][1]).toEqual([
      "group-a",
      "manager",
      "manager-a",
      10,
    ]);
    expect(query.mock.calls[2][0]).toContain(
      "group_teacher_profile.user_id = $3",
    );
  });

  it("keeps the teacher student card free of embedded commerce sections", async () => {
    // findStudent is now a shared db read (student-read.ts) — seed its row via
    // the query mock instead of spying a method.
    const { service, scheduleRead } = createService([
      {
        id: "student-a",
        profile_user_id: "user-a",
        teacher_user_ids: ["teacher-a"],
      },
    ]);
    const lesson = {
      id: "lesson-from-schedule-read",
      version: 4,
      lifecycleState: "scheduled",
      studentId: "student-a",
      groupId: null,
      leadId: null,
      teacherId: "teacher-a",
      branchId: "branch-a",
      roomId: "room-a",
      scheduledAt: "2026-06-16T09:00:00.000Z",
      durationMinutes: 60,
      status: "scheduled",
      isTrial: true,
      notes: "Distinctive card lesson",
      teacherRate: null,
      appliedTeacherRate: null,
      paidAmount: null,
      studentName: "Анна Иванова",
      leadName: null,
      teacherName: "Иван Петров",
      branchName: "Центральный",
      roomName: "Класс A",
      groupName: null,
      groupPricePerLesson: null,
      completionType: null,
      clientChargeType: null,
      clientChargeValue: null,
      teacherCompensationType: null,
      teacherCompensationValue: null,
      settlementTypeKey: null,
      teacherCompensationRuleKey: null,
      teacherCompensationValueMinor: null,
      subscriptionId: null,
      snapshotTrial: true,
      snapshotValidationState: null,
      reservationState: null,
      settlementFailureCode: null,
    };
    scheduleRead.listLessons.mockResolvedValue({ items: [lesson] });

    const card = await service.getStudentCard(
      { userId: "teacher-a", role: "teacher" },
      "student-a",
    );

    expect(card.lessons).toEqual([lesson]);
    expect(scheduleRead.listLessons).toHaveBeenCalledWith(
      { userId: "teacher-a", role: "teacher" },
      { studentId: "student-a", limit: 100 },
    );
    expect(card).not.toHaveProperty("balance");
    expect(card).not.toHaveProperty("payments");
    expect(card).not.toHaveProperty("expectedPayments");
    expect(card).not.toHaveProperty("subscriptions");
  });

  it("keeps the admin student card free of embedded commerce sections", async () => {
    const { service } = createService([
      { id: "student-a", profile_user_id: "user-a", teacher_user_ids: [] },
    ]);

    const card = await service.getStudentCard(
      { userId: "admin-a", role: "admin" },
      "student-a",
    );

    expect(card).not.toHaveProperty("balance");
    expect(card).not.toHaveProperty("payments");
    expect(card).not.toHaveProperty("expectedPayments");
    expect(card).not.toHaveProperty("subscriptions");
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
        version: 1,
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
        expectedVersion: 1,
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
      false,
      null, // source_id unchanged
      false, // clear_email: omission preserves the current contact email
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_updated",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  describe("explicit student responsible writes", () => {
    const responsibleId = "11111111-1111-4111-8111-111111111111";

    it("validates and canonicalizes a nested responsibleUserId before create", async () => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              user_id: responsibleId,
              role: "director",
              staff_member_id: "staff-1",
              staff_status: "working",
              display_name: "Дарья Директор",
            },
          ],
        },
        {
          rows: [
            {
              id: "student-a",
              version: 1,
              status: "active",
              profile_id: "profile-a",
              profile_user_id: "client-a",
              lead_id: null,
              custom_data: {
                responsible: "Дарья Директор",
                responsibleUserId: responsibleId,
              },
              first_name: "Анна",
              last_name: null,
              email: "student@example.com",
              phone: null,
              teacher_user_ids: [],
              created_at: "2026-06-13T00:00:00.000Z",
            },
          ],
        },
      ]);

      await service.createStudent(actor, {
        firstName: "Анна",
        customDataPatch: {
          responsibleUserId: responsibleId,
          responsibleName: "spoofed",
        },
      });

      expect(String(query.mock.calls[0][0])).toContain(
        "join app.staff_members",
      );
      expect(query.mock.calls[0][1]).toEqual([
        responsibleId,
        [...RESPONSIBLE_AUTH_ROLES],
        [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
      ]);
      const insertCall = query.mock.calls.find((call) =>
        String(call[0]).includes("insert into app.students"),
      );
      expect((insertCall?.[1] as unknown[])[7]).toBe(
        JSON.stringify({
          responsibleUserId: responsibleId,
          responsible: "Дарья Директор",
        }),
      );
    });

    it("rejects an ineligible nested owner without inserting a student", async () => {
      const { service, query } = createServiceWithQueryResults([{ rows: [] }]);

      await expect(
        service.createStudent(actor, {
          firstName: "Анна",
          customDataPatch: { responsibleUserId: responsibleId },
        }),
      ).rejects.toMatchObject({ status: 400 });
      expect(
        query.mock.calls.some((call) =>
          String(call[0]).includes("insert into app.students"),
        ),
      ).toBe(false);
    });

    it("clears all student compatibility owner keys only with the explicit flag", async () => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              id: "student-a",
              version: 1,
              status: "active",
              branch_id: null,
              custom_data: {
                responsible: "Дарья Директор",
                responsibleUserId: responsibleId,
              },
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
              custom_data: {},
              first_name: "Анна",
              last_name: null,
              email: "student@example.com",
              phone: null,
              teacher_user_ids: [],
              created_at: "2026-06-13T00:00:00.000Z",
            },
          ],
        },
      ]);

      await service.updateStudent(actor, "student-a", {
        expectedVersion: 1,
        clearResponsible: true,
      });

      const updateCall = query.mock.calls.find((call) =>
        String(call[0]).includes("update app.students s"),
      );
      const sql = String(updateCall?.[0]);
      expect(sql).toContain("case when $9::boolean then");
      expect(sql).toContain("- 'responsible' - 'responsibleUserId'");
      expect((updateCall?.[1] as unknown[])[8]).toBe(true);
      expect(
        query.mock.calls.some((call) =>
          String(call[0]).includes("with eligible_actor as"),
        ),
      ).toBe(false);
    });
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
      nextCursor: null,
    });

    expect(policy.assertCanListStudents).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain(
      "scope_assignment.branch_id::text",
    );
    expect(query.mock.calls[0][1]).toContain("анна");
    expect(query.mock.calls[0][1]).toContain("Вокал");
    expect(query.mock.calls[0][1]).toContain(21);
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
    await service.updateStudent(actor, "student-1", {
      status: "paused",
    } as never);
    const insert = query.mock.calls
      .map((c) => String(c[0]))
      .find((s) => s.includes("insert into app.student_status_history"));
    expect(insert).toBeDefined();
    const params = query.mock.calls.find((c) =>
      String(c[0]).includes("insert into app.student_status_history"),
    )?.[1] as unknown[];
    expect(params).toEqual(["student-1", "paused", "b1"]);
  });

  it("blocks direct student deletion without mutating CRM data", async () => {
    const { service, query, audit, policy, database } = createService([
      { id: "student-a" },
    ]);

    await expect(service.deleteStudent(actor, "student-a")).rejects.toThrow(
      ConflictException,
    );

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(database.transaction).not.toHaveBeenCalled();
    expect(query).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("blocks returning a student to leads without mutating CRM data", async () => {
    const { service, query, audit, policy, database } = createService([
      { id: "student-a" },
    ]);

    await expect(
      service.returnStudentToLead(actor, "student-a"),
    ).rejects.toThrow(ConflictException);

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(database.transaction).not.toHaveBeenCalled();
    expect(query).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("searchStudents filters branchless students when noBranch is set", async () => {
    const { service, query } = createServiceWithQueryResults([{ rows: [] }]);
    await service.searchStudents(actor, { noBranch: true } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain(
      "coalesce(s.branch_id::text, s.custom_data->>'branchId', s.custom_data->>'branch_id') is null",
    );
  });

  it("student search branch filter prefers the branch_id column", async () => {
    const { service, query } = createServiceWithQueryResults([{ rows: [] }]);
    await service.searchStudents(actor, { branchId: "b-1" } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("s.branch_id::text");
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
    expect(
      result.students.find((s) => s.id === "student-child")?.firstName,
    ).toBe("Петя");

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
    const summary = await service.getMySummary(clientActor);
    expect(summary).toEqual(
      expect.objectContaining({
        students: [expect.objectContaining({ id: "student-a" })],
        upcomingLessons: [],
        tasks: [],
      }),
    );
    expect(summary).not.toHaveProperty("recentPayments");
  });

  describe("student boundary characterization", () => {
    const studentRow = {
      id: "student-boundary-a",
      version: 1,
      lead_id: "lead-boundary-a",
      source_id: "source-boundary-a",
      source_name: "Рекомендация",
      status: "active",
      custom_data: { age: 12 },
      profile_id: "profile-boundary-a",
      profile_user_id: "user-boundary-a",
      first_name: "Алина",
      last_name: "Иванова",
      email: "alina@example.com",
      phone: "+79990000000",
      teacher_user_ids: ["teacher-boundary-a"],
      blacklisted: true,
      blacklist_reason: "Нарушение правил",
      created_at: "2026-08-01T10:00:00.000Z",
    };
    const expectedStudentDto = {
      id: "student-boundary-a",
      version: 1,
      leadId: "lead-boundary-a",
      sourceId: "source-boundary-a",
      sourceName: "Рекомендация",
      status: "active",
      customData: { age: 12 },
      profileId: "profile-boundary-a",
      profileUserId: "user-boundary-a",
      firstName: "Алина",
      lastName: "Иванова",
      email: "alina@example.com",
      phone: "+79990000000",
      teacherUserIds: ["teacher-boundary-a"],
      createdAt: "2026-08-01T10:00:00.000Z",
      appealAt: "2026-08-01T10:00:00.000Z",
      appealAtSource: "app",
      age: 12,
      ageMonths: null,
      ageSource: "manual",
      blacklisted: true,
      blacklistReason: "Нарушение правил",
    };
    const expectedListStudentDto = {
      ...expectedStudentDto,
      // listStudents deliberately does not join lead_sources.
      sourceId: null,
      sourceName: null,
    };
    const {
      source_id: _listSourceId,
      source_name: _listSourceName,
      ...listStudentRow
    } = studentRow;
    const teacherActor = {
      userId: "teacher-boundary-a",
      role: "teacher" as const,
    };

    it("lists students through list policy, bounded query, and canonical DTO", async () => {
      const { service, database, policy } = createService();
      const events: string[] = [];
      policy.assertCanListStudents.mockImplementation(() => events.push("policy"));
      database.query.mockImplementation(async () => {
        events.push("query");
        return { rows: [listStudentRow] };
      });

      await expect(
        service.listStudents(actor, { q: "  Алина  ", limit: 999 }),
      ).resolves.toEqual({ items: [expectedListStudentDto] });

      expect(policy.assertCanListStudents).toHaveBeenCalledWith(actor);
      expect(database.query).toHaveBeenCalledTimes(1);
      expect(events).toEqual(["policy", "query"]);
      expect(database.query.mock.calls[0]![1]).toEqual([
        actor.role,
        actor.userId,
        "Алина",
        100,
      ]);
    });

    it("reads one student only after row-level authorization", async () => {
      const { service, database, policy } = createService();
      const events: string[] = [];
      database.query.mockImplementation(async () => {
        events.push("authorization lookup");
        return { rows: [studentRow] };
      });
      policy.assertCanReadStudent.mockImplementation(() =>
        events.push("authorization"),
      );

      await expect(
        service.getStudent(teacherActor, studentRow.id),
      ).resolves.toEqual(expectedStudentDto);

      expect(policy.assertCanReadStudent).toHaveBeenCalledWith(teacherActor, {
        profileUserId: studentRow.profile_user_id,
        teacherUserIds: studentRow.teacher_user_ids,
      });
      expect(database.query).toHaveBeenCalledTimes(1);
      expect(events).toEqual(["authorization lookup", "authorization"]);
    });

    it("reports the exact not-found message for a missing student", async () => {
      const { service } = createService();

      await expect(service.getStudent(actor, "student-missing")).rejects.toThrow(
        "Ученик не найден.",
      );
    });

    it("returns a cursor for the visible first page of a student search", async () => {
      const olderStudent = {
        ...studentRow,
        id: "student-boundary-b",
        created_at: "2026-07-01T10:00:00.000Z",
        total_count: "2",
      };
      const newestStudent = {
        ...studentRow,
        total_count: "2",
      };
      const { service, database, policy } = createService();
      const events: string[] = [];
      policy.assertCanListStudents.mockImplementation(() => events.push("policy"));
      database.query.mockImplementation(async () => {
        events.push("query");
        return { rows: [newestStudent, olderStudent] };
      });

      const result = await service.searchStudents(actor, { limit: 1 });

      expect(result.items).toHaveLength(1);
      expect(result.items[0]).toMatchObject({ id: newestStudent.id });
      expect(result.totalCount).toBe(2);
      expect(result.nextCursor).toBe(
        "2026-08-01T10:00:00.000Z|student-boundary-a",
      );
      expect(database.query).toHaveBeenCalledTimes(1);
      expect(events).toEqual(["policy", "query"]);
    });

    it("checks group scope before querying the student roster", async () => {
      const { service, database, policy } = createService();
      const events: string[] = [];
      policy.assertCanReadOperationalData.mockImplementation(() =>
        events.push("policy"),
      );
      database.query.mockImplementation(async (sql: string) => {
        if (sql.includes("from app.groups")) {
          events.push("group scope");
          return { rows: [{ branch_id: "branch-boundary-a" }] };
        }
        if (sql.includes("app.staff_branch_assignments")) {
          events.push("branch scope");
          return { rows: [{ branch_id: "branch-boundary-a" }] };
        }
        events.push("roster");
        return { rows: [studentRow] };
      });

      await expect(
        service.listGroupStudents(actor, "group-boundary-a", { limit: 10 }),
      ).resolves.toEqual({ items: [expectedStudentDto] });

      expect(database.query).toHaveBeenCalledTimes(3);
      expect(events).toEqual(["policy", "group scope", "branch scope", "roster"]);
    });

    const createPublicationHarness = () => {
      const events: string[] = [];
      const realtime = { emitCrmChanged: jest.fn(() => events.push("realtime")) };
      const query = jest.fn(async (sql: string) => {
        if (
          sql.includes("with eligible_actor as") &&
          sql.includes("update app.students")
        ) {
          events.push("responsible");
          return { rows: [] };
        }
        if (sql.includes("insert into app.students")) {
          return { rows: [studentRow] };
        }
        if (sql.includes("select status, custom_data, branch_id")) {
          return {
            rows: [
              {
                status: "active",
                custom_data: {},
                branch_id: null,
              },
            ],
          };
        }
        if (sql.includes("update app.students s")) {
          return { rows: [studentRow] };
        }
        return { rows: [] };
      });
      const database = {
        query,
        transaction: jest.fn(async (fn: (client: { query: typeof query }) => unknown) => {
          const result = await fn({ query });
          events.push("transaction");
          return result;
        }),
      };
      const audit = { record: jest.fn(async () => events.push("audit")) };
      const policy = {
        assertCanReadOperationalData: jest.fn(),
        assertCanWriteCrm: jest.fn(),
        assertManagerOnly: jest.fn(),
        assertCanReadStudentFinance: jest.fn(),
        canReadStudentFinance: jest.fn().mockReturnValue(true),
        assertCanReadSchoolFinance: jest.fn(),
        canReadSchoolFinance: jest.fn().mockReturnValue(true),
        assertCanListStudents: jest.fn(),
        assertCanReadPayroll: jest.fn(),
        assertCanReadStudent: jest.fn(),
      };
      const directory = new StudentDirectoryService(
        database as unknown as DatabaseService,
        policy as unknown as CrmPolicy,
      );
      const tasks = {
        list: jest.fn().mockResolvedValue({ items: [], counters: {} }),
      } as unknown as SharedTaskService;
      const scheduleRead = {
        listUpcomingLessonsForStudents: jest.fn().mockResolvedValue([]),
        listLessons: jest.fn().mockResolvedValue({ items: [] }),
      } as unknown as ScheduleReadService;
      const timeline = {
        listComments: jest.fn().mockResolvedValue({ items: [] }),
        listFieldAudit: jest.fn().mockResolvedValue({ items: [] }),
      } as unknown as TimelineService;
      const chatWork = {
        listForEntity: jest.fn().mockResolvedValue([]),
      } as unknown as ChatWorkTimelineService;
      const studentFunnel = {
        assertCreateStatus: jest.fn(),
        assertTransition: jest.fn(),
      } as unknown as StudentFunnelService;
      const studentMutations = new StudentMutationExecutor(
        database as unknown as DatabaseService,
        studentFunnel,
      );
      const commands = new StudentCommandService(
        database as unknown as DatabaseService,
        audit as unknown as AuditService,
        policy as unknown as CrmPolicy,
        {
          sendEmail: jest.fn(),
          notifyUser: jest.fn(),
          notifyNewLead: jest.fn(),
        } as unknown as NotificationsService,
        realtime as unknown as RealtimeBus,
        studentMutations,
      );
      const service = new CrmService(
        directory,
        new StudentSelfSummaryService(
          database as unknown as DatabaseService,
          tasks,
          scheduleRead,
        ),
        new StudentCardTimelineService(
          database as unknown as DatabaseService,
          directory,
          scheduleRead,
          tasks,
          timeline,
          chatWork,
        ),
        commands,
      );
      return { events, service, realtime };
    };

    it.each([
      ["create", (service: CrmService) => service.createStudent(actor, { firstName: "Алина" })],
      ["update", (service: CrmService) => service.updateStudent(actor, studentRow.id, { expectedVersion: 1, firstName: "Алина" })],
    ])("publishes %s only after transaction and responsible fallback", async (_, run) => {
      const { events, realtime, service } = createPublicationHarness();

      await run(service);

      expect(events).toEqual(["transaction", "responsible", "audit", "realtime"]);
      expect(realtime.emitCrmChanged).toHaveBeenCalledTimes(1);
    });
  });
});
