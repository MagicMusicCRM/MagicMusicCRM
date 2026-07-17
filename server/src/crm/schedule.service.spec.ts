import { ForbiddenException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { ScheduleService } from "./schedule.service";

describe("ScheduleService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const buildDeps = () => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = {
      notifyUser: jest.fn().mockResolvedValue({ notificationId: "notif-test" }),
    };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      // Per-lesson teacher rates: staff-only (admin/manager/director), not
      // clients or teachers — the default mock says no so a leak has to be
      // opted into explicitly by a test.
      canReadTeacherRates: jest.fn().mockReturnValue(false),
      canReadSchoolFinance: jest.fn().mockReturnValue(false),
      // «Оплаты по дням»: деньги клиента — не для педагога. Мок по умолчанию
      // говорит «нет», чтобы утечку пришлось включить тестом осознанно.
      canReadStudentFinance: jest.fn().mockReturnValue(false),
    };
    return { audit, notifications, policy };
  };

  const construct = (
    query: jest.Mock,
    deps: ReturnType<typeof buildDeps>,
  ) =>
    new ScheduleService(
      {
        query,
        // Transactional writes share the same query mock so call indices in
        // the assertions below stay stable.
        transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
          work({ query }),
      } as unknown as DatabaseService,
      deps.audit as unknown as AuditService,
      deps.policy as unknown as CrmPolicy,
      deps.notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
    );

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const deps = buildDeps();
    const service = construct(query, deps);
    return { service, query, ...deps };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const deps = buildDeps();
    const service = construct(query, deps);
    return { service, query, ...deps };
  };

  describe("«оплаты по дням» (✔ владелец 17.07)", () => {
    it("sums the payments tied to each lesson", async () => {
      const { service, query, policy } = createService([]);
      policy.canReadStudentFinance.mockReturnValue(true);

      await service.listLessons(actor, { limit: 10 });

      const sql = String(query.mock.calls[0][0]);
      expect(sql).toContain("from app.payments pay");
      expect(sql).toContain("pay.lesson_id = l.id");
      // Отменённый платёж — не оплата.
      expect(sql).toContain("pay.deleted_at is null");
      expect(sql).toContain("as paid_amount");
    });

    it("does not turn «нет платежа» into a confident zero", async () => {
      // Привязывать платёж к занятию не обязательно (аванс на счёт, абонемент,
      // импорт из HolliHop — там связи нет вовсе). coalesce(…, 0) объявил бы
      // все такие дни неоплаченными.
      const { service, query, policy } = createService([]);
      policy.canReadStudentFinance.mockReturnValue(true);

      await service.listLessons(actor, { limit: 10 });

      const sql = String(query.mock.calls[0][0]);
      expect(sql).not.toMatch(/coalesce\(sum\(pay\.amount\)/);
    });

    it("never lets a teacher see the client's money", async () => {
      const { service, query, policy } = createService([]);
      policy.canReadStudentFinance.mockReturnValue(false);

      await service.listLessons(
        { userId: "teacher-1", role: "teacher" as const },
        { limit: 10 },
      );

      const sql = String(query.mock.calls[0][0]);
      // Не «скрыто в UI», а не выбрано из базы вовсе.
      expect(sql).toContain("null::numeric as paid_amount");
      expect(sql).not.toContain("app.payments");
    });

    it("shows a client the payments for their own lesson", async () => {
      // Клиенту его собственные платежи не тайна, а выборка и так отдаёт ему
      // только его занятия.
      const { service, query, policy } = createService([]);
      policy.canReadStudentFinance.mockReturnValue(false);

      await service.listLessons(
        { userId: "client-1", role: "client" as const },
        { limit: 10 },
      );

      expect(String(query.mock.calls[0][0])).toContain("pay.lesson_id = l.id");
    });
  });

  describe("applied teacher rate", () => {
    const clientActor = { userId: "client-1", role: "client" as const };

    it("never selects pay rates for an actor who may not see them", async () => {
      const { service, query, policy } = createService([]);
      policy.canReadTeacherRates.mockReturnValue(false);

      await service.listLessons(clientActor, { limit: 10 });

      const sql = String(query.mock.calls[0][0]);
      // listLessons serves clients too, so the rate must not merely be hidden
      // in the UI — it must never leave the database.
      expect(sql).toContain("null::numeric as applied_teacher_rate");
      expect(sql).not.toContain("app.teacher_rates");
    });

    it("resolves lesson → group → history → 0 for finance roles", async () => {
      const { service, query, policy } = createService([]);
      policy.canReadTeacherRates.mockReturnValue(true);

      await service.listLessons(
        { userId: "dir-1", role: "director" as const },
        { limit: 10 },
      );

      const sql = String(query.mock.calls[0][0]);
      // Same precedence as computeLessonAccrual in payroll.service.ts.
      expect(sql).toMatch(
        /coalesce\(\s*l\.teacher_rate,\s*g\.teacher_rate,[\s\S]*app\.teacher_rates[\s\S]*0\s*\)\s*as applied_teacher_rate/,
      );
    });

    it("asks the per-lesson gate, not the aggregate-finance one", async () => {
      const { service, policy } = createService([]);
      const managerActor = { userId: "mgr-1", role: "manager" as const };

      await service.listLessons(managerActor, { limit: 10 });

      // The owner's 16.07 decision: a per-lesson rate is not a school-wide
      // total, so admin/manager see it. Gating this on canReadSchoolFinance
      // would hide it from exactly the people who set it.
      expect(policy.canReadTeacherRates).toHaveBeenCalledWith(managerActor);
      expect(policy.canReadSchoolFinance).not.toHaveBeenCalled();
    });
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

  it("creates a schedule series and materializes lessons up to the horizon (KVA-236)", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [{ id: "series-a" }] }, // insert series
      { rows: [] }, // materialize insert..select
    ]);

    await expect(
      service.createScheduleSeries(actor, {
        studentId: "student-a",
        weekday: 2,
        beginTime: "15:00",
        durationMinutes: 60,
        validFrom: "2026-07-15",
        // validUntil отсутствует — «до бесконечности»
      }),
    ).resolves.toEqual({ id: "series-a", lessonsCreated: 0 });

    const materializeSql = String(query.mock.calls[1][0]);
    expect(materializeSql).toContain("generate_series");
    expect(materializeSql).toContain("extract(isodow from d) = s.weekday");
    // Идемпотентность: занятая series_date (вкл. перенесённые/отменённые) не пересоздаётся.
    expect(materializeSql).toContain("l.series_id = s.id and l.series_date = d::date");
    expect(query.mock.calls[1][1]).toEqual(["series-a", 60]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.schedule_series_created" }),
    );
  });

  it("applies a series edit from the effective date and keeps moved lessons (KVA-236)", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "series-a",
            student_id: "student-a",
            group_id: null,
            teacher_id: "teacher-a",
            room_id: "room-a",
            branch_id: "branch-a",
            weekday: 2,
            begin_time: "15:00:00",
            duration_minutes: 60,
            valid_from: "2026-07-15",
            valid_until: null,
            notes: null,
            created_at: "2026-07-10",
            updated_at: "2026-07-10",
          },
        ],
      },
      { rows: [] }, // close old series
      { rows: [] }, // remove future untouched lessons
      { rows: [{ id: "series-b" }] }, // continuation insert
      { rows: [] }, // materialize continuation
    ]);

    await expect(
      service.updateScheduleSeries(actor, "series-a", {
        teacherId: "teacher-b",
        beginTime: "16:00",
        effectiveFrom: "2026-08-01",
      }),
    ).resolves.toEqual({
      id: "series-b",
      previousId: "series-a",
      lessonsCreated: 0,
    });

    // Будущие занятия снимаются ТОЛЬКО нетронутые: scheduled и не перенесённые.
    const removeSql = String(query.mock.calls[2][0]);
    expect(removeSql).toContain("original_scheduled_at is null");
    expect(removeSql).toContain("status = 'scheduled'");
    expect(query.mock.calls[2][1]).toEqual(["series-a", "2026-08-01"]);
    // Продолжение наследует незатронутые параметры и берёт новые.
    expect(query.mock.calls[3][1]).toEqual([
      "student-a",
      null,
      "teacher-b",
      "room-a",
      "branch-a",
      2,
      "16:00",
      60,
      "2026-08-01",
      null,
      null,
      "manager-a",
    ]);
  });

  it("stamps original_scheduled_at when a series lesson is moved (KVA-236)", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // assertCanUpdateLesson lookup (manager: no query? see below)
      { rows: [{ teacher_id: null, room_id: null, scheduled_at: "2026-07-15T15:00:00Z", teacher_user_id: null }] },
      {
        rows: [
          {
            id: "lesson-a",
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: null,
            branch_id: null,
            room_id: null,
            scheduled_at: "2026-07-16T15:00:00Z",
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
      { rows: [] }, // lesson_reminders cleanup
      { rows: [] }, // reschedule notification lookup (best-effort)
    ]);

    await service.updateLesson(actor, "lesson-a", {
      scheduledAt: "2026-07-16T15:00:00Z",
    });

    // Первый перенос занятия серии фиксирует исходное время в САМОМ UPDATE.
    const updateCall = query.mock.calls.find((c) =>
      String(c[0]).includes("update app.lessons"),
    );
    expect(String(updateCall?.[0])).toContain(
      "coalesce(original_scheduled_at, scheduled_at)",
    );
    expect(String(updateCall?.[0])).toContain("series_id is not null");
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
      null,
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
      null,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lesson_created",
        entityId: "lesson-lead-a",
      }),
    );
  });

  describe("bulk teacher rate", () => {
    it("reprices every lesson in one statement and reports the count", async () => {
      const { service, query, audit } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a" }, { id: "lesson-b" }] },
      ]);

      await expect(
        service.setLessonsTeacherRate(actor, {
          lessonIds: ["lesson-a", "lesson-b"],
          teacherRate: 0,
        }),
      ).resolves.toEqual({
        updated: 2,
        lessonIds: ["lesson-a", "lesson-b"],
      });

      // One statement, not one per lesson: the client used to PATCH in a loop,
      // so a failure halfway left some lessons repriced and some not.
      expect(query).toHaveBeenCalledTimes(1);
      expect(query.mock.calls[0][1]).toEqual([["lesson-a", "lesson-b"], 0]);
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "crm.lessons_teacher_rate_bulk_set",
          metadata: expect.objectContaining({ teacherRate: 0, updated: 2 }),
        }),
      );
    });

    it("keeps a rate of 0 rather than treating it as 'no rate given'", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, {
        lessonIds: ["lesson-a"],
        teacherRate: 0,
      });

      // 0 is «входит в оклад» — the whole point of the bulk pass. A `|| null`
      // anywhere in this path would silently turn it into "clear the override".
      expect(query.mock.calls[0][1][1]).toBe(0);
    });

    it("clears the override when no rate is given", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, { lessonIds: ["lesson-a"] });

      // Sets, not coalesces: falling back to the group/history rate has to be
      // expressible, and coalesce cannot express it.
      expect(String(query.mock.calls[0][0])).toContain(
        "teacher_rate = $2::numeric",
      );
      expect(query.mock.calls[0][1][1]).toBeNull();
    });

    it("is manager-only — it writes payroll inputs across the schedule", async () => {
      const { service, policy } = createServiceWithQueryResults([{ rows: [] }]);

      await service.setLessonsTeacherRate(actor, { lessonIds: ["lesson-a"] });

      expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    });
  });

  it("stops a teacher from setting the pay rate on their own lesson", async () => {
    const teacherActor = { userId: "teacher-user-a", role: "teacher" as const };
    const { service, policy } = createServiceWithQueryResults([{ rows: [] }]);
    policy.assertCanWriteCrm.mockImplementation(() => {
      throw new ForbiddenException();
    });

    // teacher_rate is what the school PAYS: a teacher editing it on their own
    // lesson is a self-granted raise. They may still edit status/notes there.
    await expect(
      service.updateLesson(teacherActor, "lesson-a", { teacherRate: 5000 }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(teacherActor);
  });
});
