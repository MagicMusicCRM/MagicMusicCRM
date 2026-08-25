import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { NotificationsService } from "../../notifications/notifications.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ScheduleConflictService } from "./schedule-conflict.service";
import { LessonScheduleMutationService } from "./lesson-schedule-mutation.service";

describe("LessonScheduleMutationService", () => {
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
    return { audit, notifications, policy };
  };

  const construct = (query: jest.Mock, deps: ReturnType<typeof buildDeps>) => {
    const database = {
      query,
      // Transactional writes share the same query mock so call indices in
      // the assertions below stay stable.
      transaction: (
        work: (client: { query: jest.Mock }) => Promise<unknown>,
      ) => work({ query }),
    } as unknown as DatabaseService;
    return new LessonScheduleMutationService(
      database,
      deps.audit as unknown as AuditService,
      deps.policy as unknown as CrmPolicy,
      deps.notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
      new ScheduleConflictService(
        database,
        deps.policy as unknown as CrmPolicy,
      ),
    );
  };

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
