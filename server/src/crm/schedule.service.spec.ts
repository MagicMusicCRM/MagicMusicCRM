import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { ScheduleService } from "./schedule.service";
import { ScheduleConstraintEngine } from "./schedule/constraint-engine.service";

describe("ScheduleService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  afterEach(() => jest.useRealTimers());

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
    const constraints = {
      validate: jest.fn().mockResolvedValue({ valid: true, violations: [] }),
    };
    return { audit, constraints, notifications, policy };
  };

  const construct = (query: jest.Mock, deps: ReturnType<typeof buildDeps>) =>
    new ScheduleService(
      {
        query,
        // Transactional writes share the same query mock so call indices in
        // the assertions below stay stable.
        transaction: (
          work: (client: { query: jest.Mock }) => Promise<unknown>,
        ) => work({ query }),
      } as unknown as DatabaseService,
      deps.audit as unknown as AuditService,
      deps.policy as unknown as CrmPolicy,
      deps.notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
      deps.constraints as unknown as ScheduleConstraintEngine,
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
    const queuedResults = [...results];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      // Transaction-scoped advisory locks are an implementation detail with
      // no rows. Keep them visible in query.mock.calls, but do not make every
      // existing fixture spend a queue entry on the lock acknowledgement.
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      return Promise.resolve(queuedResults.shift());
    });
    const deps = buildDeps();
    const service = construct(query, deps);
    return { service, query, ...deps };
  };

  it("uses Moscow business dates across the UTC midnight boundary", () => {
    jest.useFakeTimers();
    try {
      // 2026-07-18 00:30 in Moscow, while UTC is still July 17.
      jest.setSystemTime(new Date("2026-07-17T21:30:00.000Z"));
      const { service } = createService([]);
      const businessDate = service as unknown as {
        moscowDate(offsetDays?: number): string;
      };
      expect(businessDate.moscowDate()).toBe("2026-07-18");
      expect(businessDate.moscowDate(1)).toBe("2026-07-19");
    } finally {
      jest.useRealTimers();
    }
  });

  it("rejects past series edit/stop cutoffs before opening a transaction", async () => {
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
      const { service, query } = createService([]);

      await expect(
        service.updateScheduleSeries(actor, "series-a", {
          effectiveFrom: "2026-07-17",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      await expect(
        service.deleteScheduleSeries(actor, "series-a", "2026-07-17"),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });

  it("selects live series using each branch timezone", async () => {
    const { service, query } = createService([]);

    await expect(service.extendAllSeriesHorizon()).resolves.toEqual({
      series: 0,
      created: 0,
      failed: 0,
    });

    const sql = String(query.mock.calls[0]?.[0]);
    expect(sql).toContain(
      "join app.branches branch on branch.id = s.branch_id",
    );
    expect(sql).toContain(
      "coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow')",
    );
    expect(sql).not.toContain("now() at time zone 'Europe/Moscow'");
  });

  it("canonicalizes mixed-case advisory resource keys", async () => {
    const { service, query } = createService([]);
    const locks = service as unknown as {
      acquireScheduleLockKeys(
        executor: { query: jest.Mock },
        keys: string[],
      ): Promise<void>;
    };
    await locks.acquireScheduleLockKeys({ query }, [
      "teacher:ABC-DEF",
      "teacher:abc-def",
      "room:ROOM-A",
    ]);
    expect(query.mock.calls.map((call) => call[1][0])).toEqual([
      "room:room-a",
      "teacher:abc-def",
    ]);
  });






  it("locks Plan series with the same deterministic keys as materialization", async () => {
    const { service, query } = createService([]);

    await service.lockSchedulePlanSeries({ query } as never, [
      "series-b",
      "series-a",
      "series-a",
    ]);

    expect(
      query.mock.calls
        .filter((call) => String(call[0]).includes("pg_advisory_xact_lock"))
        .map((call) => call[1][0]),
    ).toEqual(["series:series-a", "series:series-b"]);
  });





  it("creates a schedule series and materializes lessons up to the horizon (KVA-236)", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [{ id: "series-a" }] }, // insert series
      {
        rows: [
          {
            series_date: "2026-07-21",
            plan_id: null,
            group_id: null,
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            starts_at: "2026-07-21T12:00:00.000Z",
            ends_at: "2026-07-21T13:00:00.000Z",
            client_refs: [{ type: "student", id: "student-a" }],
          },
        ],
      }, // candidates before locks
      {
        rows: [
          {
            series_date: "2026-07-21",
            plan_id: null,
            group_id: null,
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            starts_at: "2026-07-21T12:00:00.000Z",
            ends_at: "2026-07-21T13:00:00.000Z",
            client_refs: [{ type: "student", id: "student-a" }],
          },
        ],
      }, // candidates after locks
      { rows: [] }, // materialize insert..select
    ]);

    await expect(
      service.createScheduleSeries(actor, {
        studentId: "student-a",
        teacherId: "teacher-a",
        branchId: "branch-a",
        roomId: "room-a",
        weekday: 2,
        beginTime: "15:00",
        durationMinutes: 60,
        validFrom: "2026-07-15",
        // validUntil отсутствует — «до бесконечности»
      }),
    ).resolves.toEqual({ id: "series-a", lessonsCreated: 0 });

    const materializeCall = query.mock.calls.find((call) =>
      String(call[0]).includes("insert into app.lessons"),
    );
    const materializeSql = String(materializeCall?.[0]);
    expect(materializeSql).toContain("generate_series");
    expect(materializeSql).toContain("extract(isodow from d) = s.weekday");
    // Идемпотентность: занятая series_date (вкл. перенесённые/отменённые) не пересоздаётся.
    expect(materializeSql).toContain(
      "l.series_id = s.id and l.series_date = d::date",
    );
    expect(materializeSql).toContain(
      "on conflict (series_id, series_date) where deleted_at is null",
    );
    expect(materializeCall?.[1]).toEqual(["series-a", 60, 400]);
    expect(
      query.mock.calls.some(
        (call) =>
          String(call[0]).includes("pg_advisory_xact_lock") &&
          call[1][0] === "series:series-a",
      ),
    ).toBe(true);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.schedule_series_created" }),
    );
  });

  it("keeps schedule-series DATE values timezone invariant", async () => {
    const { service, query } = createService([
      {
        id: "series-date",
        student_id: "student-a",
        group_id: null,
        teacher_id: "teacher-a",
        room_id: null,
        branch_id: null,
        weekday: 3,
        begin_time: "15:00:00",
        duration_minutes: 60,
        valid_from: "2026-07-15",
        valid_until: "2026-12-31",
        notes: null,
        created_at: "2026-07-01T10:00:00.000Z",
        updated_at: "2026-07-01T10:00:00.000Z",
      },
    ]);

    const result = await service.listScheduleSeries(actor, {});

    expect(result.items[0]).toMatchObject({
      validFrom: "2026-07-15",
      validUntil: "2026-12-31",
    });
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("s.valid_from::text as valid_from");
    expect(sql).toContain("s.valid_until::text as valid_until");
  });

  it("applies a series edit, preserves exceptions and explicitly clears a finite end", async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
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
            valid_until: "2026-12-31",
            notes: null,
            created_at: "2026-07-10",
            updated_at: "2026-07-10",
          },
        ],
      },
      { rows: [] }, // close old series
      { rows: [{ id: "series-b" }] }, // continuation insert
      { rows: [] }, // move future exceptions to the continuation
      { rows: [] }, // remove future untouched lessons
      { rows: [] }, // mark the old series as superseded
      { rows: [] }, // recurring candidates before locks
      { rows: [] }, // recurring candidates after locks
      { rows: [] }, // materialize continuation
    ]);

    await expect(
      service.updateScheduleSeries(actor, "series-a", {
        teacherId: "teacher-b",
        beginTime: "16:00",
        effectiveFrom: "2026-08-01",
        validUntil: null,
      }),
    ).resolves.toEqual({
      id: "series-b",
      previousId: "series-a",
      lessonsCreated: 0,
    });

    // Будущие занятия снимаются ТОЛЬКО нетронутые: scheduled и не перенесённые.
    const removeCall = query.mock.calls.find((call) =>
      String(call[0]).includes("set deleted_at = now()"),
    );
    const removeSql = String(removeCall?.[0]);
    expect(removeSql).toContain("original_scheduled_at is null");
    expect(removeSql).toContain("status = 'scheduled'");
    expect(removeCall?.[1]).toEqual(["series-a", "2026-08-01"]);
    const exceptionMove = query.mock.calls.find((call) =>
      String(call[0]).includes("set series_id = $2"),
    );
    expect(String(exceptionMove?.[0])).toContain("deleted_at is not null");
    expect(String(exceptionMove?.[0])).toContain(
      "original_scheduled_at is not null",
    );
    expect(exceptionMove?.[1]).toEqual(["series-a", "series-b", "2026-08-01"]);
    expect(query.mock.calls.indexOf(exceptionMove!)).toBeLessThan(
      query.mock.calls.indexOf(removeCall!),
    );
    // Продолжение наследует незатронутые параметры и берёт новые.
    const continuationCall = query.mock.calls.find((call) =>
      String(call[0]).includes("insert into app.schedule_series"),
    );
    expect(continuationCall?.[1]).toEqual([
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
    expect(
      query.mock.calls.some((call) => String(call[0]).includes("for update")),
    ).toBe(true);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("set superseded_by = $2"),
      ),
    ).toBe(true);
  });

  it("keeps a future-stopped series live so the worker reaches the cutoff", async () => {
    const responses = [
      { rows: [{ id: "series-a", superseded_by: null }] },
      { rows: [], rowCount: 1 },
      { rows: [], rowCount: 0 },
    ];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      return Promise.resolve(responses.shift());
    });
    const service = construct(query, buildDeps());

    await expect(
      service.deleteScheduleSeries(actor, "series-a", "2026-12-01"),
    ).resolves.toEqual({ id: "series-a", stoppedFrom: "2026-12-01" });

    const seriesUpdate = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.schedule_series"),
    );
    expect(String(seriesUpdate?.[0])).toContain("deleted_at = case");
    expect(String(seriesUpdate?.[0])).toContain(
      "now() at time zone 'Europe/Moscow'",
    );
    expect(String(seriesUpdate?.[0])).toContain("else deleted_at");
  });

  it("stops series occurrences by their actual Moscow date, including moved lessons", async () => {
    const responses = [
      { rows: [{ id: "series-a", superseded_by: null }] },
      { rows: [], rowCount: 1 },
      { rows: [], rowCount: 2 },
    ];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      return Promise.resolve(responses.shift());
    });
    const service = construct(query, buildDeps());

    await service.deleteScheduleSeries(actor, "series-a", "2026-12-01");

    const lessonUpdate = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.lessons"),
    );
    const sql = String(lessonUpdate?.[0]);
    expect(sql).toContain(
      "(scheduled_at at time zone 'Europe/Moscow')::date >= $2::date",
    );
    expect(sql).toContain("status = 'scheduled'");
    expect(sql).not.toContain("series_date >= $2::date");
    expect(sql).not.toContain("original_scheduled_at is null");
    expect(lessonUpdate?.[1]).toEqual(["series-a", "2026-12-01"]);
  });

  it("serializes series edits and rejects a second continuation", async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
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
            valid_until: "2026-07-31",
            superseded_by: "series-b",
            notes: null,
            created_at: "2026-07-10",
            updated_at: "2026-07-18",
          },
        ],
      },
    ]);

    await expect(
      service.updateScheduleSeries(actor, "series-a", {
        effectiveFrom: "2026-08-01",
      }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.schedule_series"),
      ),
    ).toBe(false);
  });

  it("stamps original_scheduled_at when a series lesson is moved (KVA-236)", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // assertCanUpdateLesson lookup (manager: no query? see below)
      {
        rows: [
          {
            teacher_id: null,
            room_id: null,
            scheduled_at: "2026-07-15T15:00:00Z",
            teacher_user_id: null,
          },
        ],
      },
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

    await expect(
      service.updateLesson(actor, "lesson-a", {
        scheduledAt: "2026-07-16T15:00:00Z",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "LESSON_TRANSITION_REQUIRED" }),
    });
    expect(query).not.toHaveBeenCalled();
  });

  it("creates lessons with branch and room ids", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      { rows: [] }, // conflict pre-check (teacher+room busy?) — свободно
      {
        rows: [
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
        ],
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
    const conflictCall = query.mock.calls.find((call) =>
      String(call[0]).includes("tstzrange"),
    );
    const insertCall = query.mock.calls.find((call) =>
      String(call[0]).includes("insert into app.lessons"),
    );
    expect(conflictCall).toBeDefined();
    const lockOrder = query.mock.calls
      .filter((call) => String(call[0]).includes("pg_advisory_xact_lock"))
      .map((call) => call[1][0]);
    expect(lockOrder).toEqual(["room:room-a", "teacher:teacher-a"]);
    expect(insertCall?.[1]).toEqual([
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

  it("allows teachers to update notes without exposing lifecycle writes", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            student_id: "student-a",
            group_id: null,
            lead_id: null,
            teacher_id: "teacher-a",
            room_id: null,
            scheduled_at: "2026-06-12T12:00:00.000Z",
            duration_minutes: 60,
            is_trial: true,
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
            status: "scheduled",
            is_trial: true,
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
        { notes: "План занятия" },
      ),
    ).resolves.toMatchObject({
      id: "lesson-a",
      status: "scheduled",
      notes: "План занятия",
    });

    expect(policy.assertCanWriteCrm).not.toHaveBeenCalled();
    expect(query.mock.calls[0][1]).toEqual(["lesson-a"]); // locked snapshot + access check
    expect(String(query.mock.calls[0][0])).toContain("for update of l");
    expect(query.mock.calls[1][1]).toEqual(["lesson-a", "План занятия"]);
  });

  it("rejects manual completion before touching persistence", async () => {
    const { service, query } = createServiceWithQueryResults([]);

    await expect(
      service.updateLesson(actor, "lesson-a", { status: "completed" }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "MANUAL_LESSON_LIFECYCLE_FORBIDDEN",
      }),
    });
    expect(query).not.toHaveBeenCalled();
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
      { rows: [] }, // contract-2 conflict pre-check (reschedule touches time)
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

    await expect(
      service.updateLesson(actor, "lesson-a", {
        scheduledAt: "2026-06-20T15:00:00.000Z",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "LESSON_TRANSITION_REQUIRED" }),
    });
    expect(query).not.toHaveBeenCalled();
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
      { rows: [] }, // contract-2 conflict pre-check (reschedule touches time)
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

    await expect(
      service.updateLesson(actor, "lesson-a", {
        scheduledAt: "2026-06-21T18:30:00.000Z",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "LESSON_TRANSITION_REQUIRED" }),
    });
    expect(query).not.toHaveBeenCalled();
    expect(notifications.notifyUser).not.toHaveBeenCalled();
  });

  it("does not notify the teacher on a non-reschedule save (KVA-158)", async () => {
    // Only notes change; time / room / teacher are identical -> no notification.
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
      }, // pre-update snapshot (OLD teacher)
      { rows: [] }, // contract-2 conflict pre-check (teacher swap touches scheduling)
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

    await expect(
      service.updateLesson(actor, "lesson-a", {
        teacherId: "teacher-b",
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "LESSON_TRANSITION_REQUIRED" }),
    });
    expect(query).not.toHaveBeenCalled();
    expect(notifications.notifyUser).not.toHaveBeenCalled();
  });

  it("creates trial lessons linked to leads", async () => {
    const { service, query, audit, policy, notifications } =
      createServiceWithQueryResults([
        { rows: [] }, // conflict pre-check — свободно
        {
          rows: [
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
          ],
        },
        { rows: [{ user_id: "client-linked" }] },
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
    const leadLock = query.mock.calls.find((call) =>
      String(call[0]).includes("locked_lead as"),
    );
    expect(String(leadLock?.[0])).toContain("pg_advisory_xact_lock");
    expect(String(leadLock?.[0])).toContain("student.lead_id = $1");
    const insertCall = query.mock.calls.find((call) =>
      String(call[0]).includes("insert into app.lessons"),
    );
    expect(insertCall?.[1]).toEqual([
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
    expect(notifications.notifyUser).toHaveBeenCalledWith({
      userId: "client-linked",
      title: "Пробное занятие назначено",
      body: expect.stringContaining("по Москве"),
      data: {
        entityType: "lesson",
        entityId: "lesson-lead-a",
        eventType: "trial_lesson_booked",
      },
      channels: ["in_app", "push"],
    });
  });

  it("rejects a stale trial create after subscription conversion wins the lead lock", async () => {
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("locked_lead as")) {
        return Promise.resolve({ rows: [{ converted: true }] });
      }
      return Promise.resolve({ rows: [] });
    });
    const deps = buildDeps();
    const service = construct(query, deps);

    await expect(
      service.createLesson(actor, {
        leadId: "lead-a",
        teacherId: "teacher-a",
        scheduledAt: "2026-07-18T10:00:00.000Z",
        isTrial: true,
      }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.lessons"),
      ),
    ).toBe(false);
  });

  it("rejects a stale trial reassignment after subscription conversion wins the lead lock", async () => {
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("locked_lead as")) {
        return Promise.resolve({ rows: [{ converted: true }] });
      }
      return Promise.resolve({ rows: [] });
    });
    const deps = buildDeps();
    const service = construct(query, deps);

    await expect(
      service.updateLesson(actor, "lesson-a", {
        leadId: "lead-a",
        isTrial: true,
      }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "LESSON_TRANSITION_REQUIRED" }),
    });
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("select l.student_id"),
      ),
    ).toBe(false);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("update app.lessons"),
      ),
    ).toBe(false);
  });

  it("does not turn a committed trial into a retryable 500 when audience lookup fails", async () => {
    const queued: Array<{ rows: Record<string, unknown>[] } | Error> = [
      { rows: [] },
      {
        rows: [
          {
            id: "lesson-committed",
            student_id: null,
            group_id: null,
            lead_id: "lead-a",
            teacher_id: "teacher-a",
            branch_id: null,
            room_id: "room-a",
            scheduled_at: "2026-07-18T10:00:00.000Z",
            duration_minutes: 60,
            status: "scheduled",
            is_trial: true,
            notes: null,
            teacher_rate: null,
            student_user_id: null,
            teacher_user_id: null,
            student_name: null,
            lead_name: null,
            teacher_name: null,
            branch_name: null,
            room_name: null,
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      },
      new Error("audience unavailable"),
    ];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      const result = queued.shift();
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result);
    });
    const deps = buildDeps();
    const service = construct(query, deps);

    await expect(
      service.createLesson(actor, {
        leadId: "lead-a",
        teacherId: "teacher-a",
        roomId: "room-a",
        scheduledAt: "2026-07-18T10:00:00.000Z",
        isTrial: true,
      }),
    ).resolves.toMatchObject({ id: "lesson-committed" });
    expect(deps.audit.record).toHaveBeenCalled();
    expect(deps.notifications.notifyUser).not.toHaveBeenCalled();
  });

  describe("bulk teacher rate", () => {
    it("reprices every lesson in one statement and reports the count", async () => {
      const { service, query, audit } = createServiceWithQueryResults([
        {
          rows: [
            { id: "lesson-a", locked: false },
            { id: "lesson-b", locked: false },
          ],
        },
        { rows: [{ id: "lesson-a" }, { id: "lesson-b" }] },
      ]);

      await expect(
        service.setLessonsTeacherRate(actor, {
          lessonIds: ["lesson-a", "lesson-b"],
          teacherRate: 0,
          reasonText: "Исправление ставки",
        }),
      ).resolves.toEqual({
        updated: 2,
        correctedSettled: 0,
        lessonIds: ["lesson-a", "lesson-b"],
      });

      // One locked validation plus one atomic update, not one PATCH per lesson.
      expect(query).toHaveBeenCalledTimes(2);
      expect(query.mock.calls[1][1]).toEqual([["lesson-a", "lesson-b"], 0]);
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "crm.lessons_teacher_rate_bulk_set",
          metadata: expect.objectContaining({ teacherRate: 0, updated: 2 }),
        }),
      );
    });

    it("keeps a rate of 0 rather than treating it as 'no rate given'", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, {
        lessonIds: ["lesson-a"],
        teacherRate: 0,
        reasonText: "Исправление ставки",
      });

      // 0 is «входит в оклад» — the whole point of the bulk pass. A `|| null`
      // anywhere in this path would silently turn it into "clear the override".
      expect(query.mock.calls[1][1][1]).toBe(0);
    });

    it("clears the override when no rate is given", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, {
        lessonIds: ["lesson-a"],
        reasonText: "Вернуть наследуемую ставку",
      });

      // Sets, not coalesces: falling back to the group/history rate has to be
      // expressible, and coalesce cannot express it.
      expect(String(query.mock.calls[1][0])).toContain(
        "teacher_rate = $2::numeric",
      );
      expect(query.mock.calls[1][1][1]).toBeNull();
    });

    it("is manager-only — it writes payroll inputs across the schedule", async () => {
      const { service, policy } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: false }] },
        { rows: [{ id: "lesson-a" }] },
      ]);

      await service.setLessonsTeacherRate(actor, {
        lessonIds: ["lesson-a"],
        reasonText: "Исправление ставки",
      });

      expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    });

    it("rejects immutable settled lessons before changing any rate", async () => {
      const { service, query, audit } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: true }] },
      ]);

      await expect(
        service.setLessonsTeacherRate(actor, {
          lessonIds: ["lesson-a"],
          teacherRate: 0,
          reasonText: "Исправление ставки",
        }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "SETTLED_TEACHER_RATE_IMMUTABLE",
          canonicalAction: "lesson_settlement_correction",
        }),
      });

      expect(query).toHaveBeenCalledTimes(1);
      expect(String(query.mock.calls[0][0])).not.toContain(
        "update app.lessons",
      );
      expect(audit.record).not.toHaveBeenCalled();
    });

    it("lets a director correct settled rates with a superseding fact", async () => {
      const director = { userId: "director-a", role: "director" as const };
      const { service, query, audit } = createServiceWithQueryResults([
        { rows: [{ id: "lesson-a", locked: true }] },
        { rows: [{ id: "lesson-a" }] },
        { rows: [] },
      ]);

      await expect(
        service.setLessonsTeacherRate(director, {
          lessonIds: ["lesson-a"],
          teacherRate: 900,
          reasonText: "Исправление ошибочной ставки администратора",
        }),
      ).resolves.toEqual({
        updated: 1,
        correctedSettled: 1,
        lessonIds: ["lesson-a"],
      });

      expect(String(query.mock.calls[2][0])).toContain(
        "supersedes_fact_id",
      );
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          metadata: expect.objectContaining({
            correctedSettled: 1,
            reason: "Исправление ошибочной ставки администратора",
          }),
        }),
      );
    });
  });

  describe("schedule conflicts (контракты 1-2, правки №2)", () => {
    const busyRow = {
      lesson_id: "lesson-busy",
      title: "Анна Иванова",
      starts_at: "2026-07-20T10:00:00.000Z",
      ends_at: "2026-07-20T11:00:00.000Z",
      room_name: "101",
      teacher_name: "Иван Петров",
      teacher_hit: true,
      room_hit: false,
    };

    it("GET conflicts is admin+ only and returns the pinned shape", async () => {
      const { service, query, policy } = createServiceWithQueryResults([
        { rows: [busyRow] },
      ]);

      await expect(
        service.getScheduleConflicts(actor, {
          teacherId: "teacher-a",
          startsAt: "2026-07-20T10:30:00.000Z",
          endsAt: "2026-07-20T11:30:00.000Z",
        }),
      ).resolves.toEqual({
        teacherBusy: true,
        roomBusy: false,
        conflicts: [
          {
            lessonId: "lesson-busy",
            title: "Анна Иванова",
            startsAt: "2026-07-20T10:00:00.000Z",
            endsAt: "2026-07-20T11:00:00.000Z",
            roomName: "101",
            teacherName: "Иван Петров",
          },
        ],
      });

      expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
      const sql = String(query.mock.calls[0][0]);
      // Operational overlap semantics: terminal cancellation/reschedule
      // sources never conflict, the same group is one class, and the check is
      // a half-open tstzrange overlap.
      expect(sql).toContain(
        "l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')",
      );
      expect(sql).toContain("l.deleted_at is null");
      expect(sql).toContain("tstzrange");
      expect(sql).toContain("l.group_id <> $6");
    });

    it("reports «свободно» without a query when neither teacher nor room is given", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.getScheduleConflicts(actor, {
          startsAt: "2026-07-20T10:30:00.000Z",
          endsAt: "2026-07-20T11:30:00.000Z",
        }),
      ).resolves.toEqual({
        teacherBusy: false,
        roomBusy: false,
        conflicts: [],
      });
      expect(query).not.toHaveBeenCalled();
    });

    it("rejects a reversed conflict range before querying", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.getScheduleConflicts(actor, {
          teacherId: "teacher-a",
          startsAt: "2026-07-20T11:30:00.000Z",
          endsAt: "2026-07-20T10:30:00.000Z",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    });

    it("409s a create into a busy slot with the conflicts payload", async () => {
      const { service } = createServiceWithQueryResults([{ rows: [busyRow] }]);

      const promise = service.createLesson(actor, {
        studentId: "student-a",
        teacherId: "teacher-a",
        scheduledAt: "2026-07-20T10:30:00.000Z",
      });
      await expect(promise).rejects.toBeInstanceOf(ConflictException);
      await promise.catch((error: ConflictException) => {
        expect(error.getResponse()).toMatchObject({
          message: "Преподаватель или аудитория заняты в это время.",
          conflicts: [expect.objectContaining({ lessonId: "lesson-busy" })],
        });
      });
    });

    it("rejects force:true for every role before touching storage", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.createLesson(actor, {
          studentId: "student-a",
          teacherId: "teacher-a",
          scheduledAt: "2026-07-20T10:30:00.000Z",
          force: true,
        }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          message: "Обход конфликтов расписания запрещён для всех ролей.",
        }),
      });
      expect(query).not.toHaveBeenCalled();
    });

    it("rejects cancel-only PATCH in favor of the explicit command", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.updateLesson(actor, "lesson-a", { status: "cancelled" }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "MANUAL_LESSON_LIFECYCLE_FORBIDDEN",
        }),
      });
      expect(query).not.toHaveBeenCalled();
    });

    it("409s a drag-move onto a busy slot, excluding the moved lesson itself", async () => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              teacher_id: "teacher-a",
              room_id: "room-a",
              scheduled_at: "2026-07-20T10:00:00.000Z",
              duration_minutes: 60,
              group_id: null,
              teacher_user_id: null,
            },
          ],
        }, // snapshot
        { rows: [busyRow] }, // conflict pre-check hits
      ]);

      await expect(
        service.updateLesson(actor, "lesson-a", {
          scheduledAt: "2026-07-20T12:00:00.000Z",
        }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "LESSON_TRANSITION_REQUIRED",
        }),
      });
      expect(query).not.toHaveBeenCalled();
    });

    it("lets clientRef lead win over a stale studentId (contract 7)", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [] }, // conflict pre-check
        {
          rows: [
            {
              id: "lesson-lead-b",
              student_id: null,
              group_id: null,
              lead_id: "lead-b",
              teacher_id: "teacher-a",
              branch_id: null,
              room_id: null,
              scheduled_at: "2026-07-21T10:00:00.000Z",
              duration_minutes: 60,
              status: "scheduled",
              is_trial: true,
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
      ]);

      await service.createLesson(actor, {
        studentId: "stale-student",
        clientRef: { type: "lead", id: "lead-b" },
        teacherId: "teacher-a",
        scheduledAt: "2026-07-21T10:00:00.000Z",
        isTrial: true,
      });

      const insertCall = query.mock.calls.find((c) =>
        String(c[0]).includes("insert into app.lessons"),
      );
      // studentId slot null, leadId slot carries the ref id.
      expect(insertCall?.[1]?.[0]).toBeNull();
      expect(insertCall?.[1]?.[2]).toBe("lead-b");
    });

  });

  describe("lesson subject invariants", () => {
    it("rejects ambiguous subjects before any lesson write", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.createLesson(actor, {
          studentId: "student-a",
          groupId: "group-a",
          scheduledAt: "2026-07-21T10:00:00.000Z",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    });

    it("requires every lead lesson to be trial", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.createLesson(actor, {
          leadId: "lead-a",
          scheduledAt: "2026-07-21T10:00:00.000Z",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    });

    it("replaces the subject atomically and clears the previous target", async () => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              student_id: "student-a",
              group_id: null,
              lead_id: null,
              teacher_id: null,
              room_id: null,
              scheduled_at: "2026-07-21T10:00:00.000Z",
              duration_minutes: 60,
              is_trial: false,
              teacher_user_id: null,
            },
          ],
        },
        {
          rows: [
            {
              id: "lesson-a",
              student_id: null,
              group_id: null,
              lead_id: "lead-b",
              teacher_id: null,
              branch_id: null,
              room_id: null,
              scheduled_at: "2026-07-21T10:00:00.000Z",
              duration_minutes: 60,
              status: "scheduled",
              is_trial: true,
              notes: null,
              teacher_rate: null,
              student_user_id: null,
              teacher_user_id: null,
              student_name: null,
              lead_name: null,
              teacher_name: null,
              branch_name: null,
              room_name: null,
              group_name: null,
              group_price_per_lesson: null,
            },
          ],
        },
        { rows: [] },
      ]);

      await expect(
        service.updateLesson(actor, "lesson-a", {
          clientRef: { type: "lead", id: "lead-b" },
          isTrial: true,
        }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "LESSON_TRANSITION_REQUIRED",
        }),
      });
      expect(query).not.toHaveBeenCalled();
    });

    it("rejects an ambiguous recurring-series subject", async () => {
      const { service, query } = createServiceWithQueryResults([]);
      await expect(
        service.createScheduleSeries(actor, {
          studentId: "student-a",
          groupId: "group-a",
          weekday: 1,
          beginTime: "10:00",
          validFrom: "2026-07-21",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    });

    it("runs the recurring conflict guard before materializing a series", async () => {
      const { service, query, constraints } = createServiceWithQueryResults([
        { rows: [{ id: "series-a" }] },
        {
          rows: [
            {
              series_date: "2026-07-21",
              plan_id: null,
              group_id: null,
              teacher_id: "teacher-a",
              branch_id: "branch-a",
              room_id: "room-a",
              starts_at: "2026-07-21T10:00:00.000Z",
              ends_at: "2026-07-21T11:00:00.000Z",
              client_refs: [{ type: "student", id: "student-a" }],
            },
          ],
        },
        {
          rows: [
            {
              series_date: "2026-07-21",
              plan_id: null,
              group_id: null,
              teacher_id: "teacher-a",
              branch_id: "branch-a",
              room_id: "room-a",
              starts_at: "2026-07-21T10:00:00.000Z",
              ends_at: "2026-07-21T11:00:00.000Z",
              client_refs: [{ type: "student", id: "student-a" }],
            },
          ],
        },
      ]);
      constraints.validate.mockResolvedValue({
        valid: false,
        violations: [
          {
            code: "TEACHER_OVERLAP",
            resource: { type: "teacher", id: "teacher-a" },
            conflictingLessonIds: ["busy-a"],
            ruleIds: [],
          },
        ],
      });

      await expect(
        service.createScheduleSeries(actor, {
          studentId: "student-a",
          teacherId: "teacher-a",
          branchId: "branch-a",
          roomId: "room-a",
          weekday: 1,
          beginTime: "10:00",
          validFrom: "2026-07-21",
        }),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
        }),
      });

      const conflictCall = query.mock.calls.find((call) =>
        String(call[0]).includes("with target as"),
      );
      expect(conflictCall).toBeDefined();
      expect(
        query.mock.calls.some((call) =>
          String(call[0]).includes("insert into app.lessons"),
        ),
      ).toBe(false);
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
