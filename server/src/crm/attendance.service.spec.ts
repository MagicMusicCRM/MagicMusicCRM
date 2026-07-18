import { BadRequestException, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { AttendanceService } from "./attendance.service";

describe("AttendanceService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) query.mockResolvedValueOnce(result);
    const transaction = jest.fn(
      (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    const database = {
      query,
      // Transactional writes share the same query mock so sequential
      // mockResolvedValueOnce chains keep working.
      transaction,
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = { notifyUser: jest.fn().mockResolvedValue(undefined) };
    const service = new AttendanceService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      notifications as unknown as NotificationsService,
    );
    return { service, query, transaction, audit, notifications };
  };

  it("refuses to complete a lesson with an empty attendance sheet", async () => {
    const { service, query, transaction, audit } =
      createServiceWithQueryResults([]);

    await expect(
      service.upsertLessonAttendance(actor, "lesson-a", { items: [] }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(query).not.toHaveBeenCalled();
    expect(transaction).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("refuses to complete a group lesson with an incomplete roster", async () => {
    const { service, transaction, audit } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-group",
            student_id: null,
            group_id: "group-a",
            teacher_user_id: "teacher-user-a",
          },
        ],
      },
      {
        rows: [
          { student_id: "student-a", first_name: "Анна", last_name: null },
          { student_id: "student-b", first_name: "Борис", last_name: null },
        ],
      },
    ]);

    await expect(
      service.upsertLessonAttendance(actor, "lesson-group", {
        items: [{ studentId: "student-a", kind: "attended" }],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(transaction).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("forbids a teacher from setting attendance/status (admin+ only)", async () => {
    const { service, query } = createServiceWithQueryResults([]);
    await expect(
      service.upsertLessonAttendance(
        { userId: "teacher-user-a", role: "teacher" as const },
        "lesson-a",
        { items: [{ studentId: "student-a", kind: "attended" }] },
      ),
    ).rejects.toThrow("только администратор и выше");
    // Rejected before any DB work — the guard runs first.
    expect(query).not.toHaveBeenCalled();
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
          { student_id: "student-a", first_name: "Анна", last_name: "Иванова" },
          { student_id: "student-b", first_name: "Олег", last_name: "Петров" },
        ],
      },
      {
        rows: [
          { student_id: "student-b", status: "absent", pass_reason: "Болеет" },
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
          kind: null,
          chargeShare: null,
          chargedHours: null,
          passReason: "",
        },
        {
          studentId: "student-b",
          studentName: "Олег Петров",
          status: "absent",
          kind: null,
          chargeShare: null,
          chargedHours: null,
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
          { student_id: "student-a", first_name: "Анна", last_name: "Иванова" },
        ],
      },
      { rows: [] },
      { rows: [] }, // reconcile advisory lock
      { rows: [] }, // reconcile state read (empty → no-op)
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
          { student_id: "student-a", first_name: "Анна", last_name: "Иванова" },
        ],
      },
      {
        rows: [
          { student_id: "student-a", status: "absent", pass_reason: "Болеет" },
        ],
      },
    ]);

    await expect(
      service.upsertLessonAttendance(actor, "lesson-a", {
        items: [{ studentId: "student-a", status: "absent", passReason: "Болеет" }],
      }),
    ).resolves.toEqual({
      lessonId: "lesson-a",
      students: [
        {
          studentId: "student-a",
          studentName: "Анна Иванова",
          status: "absent",
          kind: null,
          chargeShare: null,
          chargedHours: null,
          passReason: "Болеет",
        },
      ],
    });

    // KVA-237: легаси-absent маппится в kind unpaid_miss с полной долей.
    expect(query.mock.calls[2][1]).toEqual([
      "lesson-a",
      "student-a",
      "absent",
      "Болеет",
      "unpaid_miss",
      1,
      // subscription_id: null → reconcile falls back to the student's own
      // subscription, then a family member's, as before.
      null,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lesson_attendance_updated",
        entityType: "lesson",
        entityId: "lesson-a",
      }),
    );
  });

  it("pins an explicitly chosen subscription so a non-family client can pay", async () => {
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
      { rows: [{ id: "sub-friend" }] }, // subscription exists check
      { rows: [{ id: "participation-a" }] }, // participation upsert
      { rows: [] }, // reconcile advisory lock
      { rows: [] }, // reconcile state read
      { rows: [] }, // lesson status
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
    ]);

    await service.upsertLessonAttendance(actor, "lesson-a", {
      items: [
        { studentId: "student-a", kind: "attended", subscriptionId: "sub-friend" },
      ],
    });

    // Validated first, then stored on the participation row —
    // reconcileSubscriptionUsage reads it back and charges THAT subscription
    // instead of hunting for the student's own or a family member's.
    expect(String(query.mock.calls[2][0])).toContain("app.subscriptions");
    expect(String(query.mock.calls[2][0])).not.toContain("deleted_at");
    expect(query.mock.calls[2][1]).toEqual(["sub-friend"]);
    expect(String(query.mock.calls[3][0])).toContain("subscription_id");
    expect(query.mock.calls[3][1]).toContain("sub-friend");
  });

  it("rejects an attendance pinned to a subscription that does not exist", async () => {
    const { service } = createServiceWithQueryResults([
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
      { rows: [] }, // subscription missing
    ]);

    await expect(
      service.upsertLessonAttendance(actor, "lesson-a", {
        items: [{ studentId: "student-a", subscriptionId: "ghost" }],
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it("rejects moving an already charged participation to another subscription", async () => {
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
      { rows: [{ student_id: "student-a", first_name: "Анна", last_name: null }] },
      { rows: [{ id: "sub-b" }] },
      // ON CONFLICT WHERE rejects A -> B because charged_hours is non-zero.
      { rows: [] },
    ]);

    await expect(
      service.upsertLessonAttendance(actor, "lesson-a", {
        items: [
          {
            studentId: "student-a",
            kind: "attended",
            subscriptionId: "sub-b",
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    const upsertSql = String(query.mock.calls[3][0]);
    expect(upsertSql).toContain(
      "subscription_id is not distinct from excluded.subscription_id",
    );
    expect(upsertSql).toContain("charged_hours = 0");
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("lessons_used = lessons_used +"),
      ),
    ).toBe(false);
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("atomically rejects an inactive or exhausted pinned subscription", async () => {
    const { service, query, transaction, audit } =
      createServiceWithQueryResults([
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
        { rows: [{ student_id: "student-a", first_name: "Анна", last_name: null }] },
        { rows: [{ id: "sub-full" }] },
        { rows: [{ id: "participation-a" }] }, // participation upsert inside the transaction
        { rows: [] }, // advisory lock
        {
          rows: [
            {
              attendance_kind: "attended",
              charge_share: 1,
              charged_hours: 0,
              subscription_id: "sub-full",
              hours: 1,
              is_trial: false,
            },
          ],
        },
        { rows: [] }, // guarded charge: inactive/exhausted
      ]);

    await expect(
      service.upsertLessonAttendance(actor, "lesson-a", {
        items: [
          {
            studentId: "student-a",
            kind: "attended",
            subscriptionId: "sub-full",
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(transaction).toHaveBeenCalledTimes(1);
    const chargeSql = String(query.mock.calls[6][0]);
    expect(chargeSql).toContain("s.status = 'active'");
    expect(chargeSql).toContain(
      "s.lessons_used + $4::numeric <= s.lessons_total",
    );
    expect(chargeSql).toContain("returning lp.id");
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("set status = 'completed'"),
      ),
    ).toBe(false);
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("counts a subscription lesson when a student is marked present (P5b-4/KVA-237)", async () => {
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
      { rows: [] }, // participation insert
      { rows: [] }, // reconcile advisory lock
      // reconcile state: attended, ничего ещё не списано, урок = 1 час
      {
        rows: [
          {
            attendance_kind: "attended",
            charge_share: 1,
            charged_hours: 0,
            subscription_id: null,
            hours: 1,
            is_trial: false,
          },
        ],
      },
      { rows: [] }, // charge query (pick + dec)
      { rows: [] }, // lesson complete update
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
        rows: [{ student_id: "student-a", status: "present", pass_reason: null }],
      },
    ]);

    await service.upsertLessonAttendance(actor, "lesson-a", {
      items: [{ studentId: "student-a", status: "present" }],
    });

    // Дельта-списание: charged 0 → target 1, списывается ровно 1 час.
    const chargeSql = String(query.mock.calls[5][0]);
    expect(chargeSql).toContain("lessons_used = lessons_used + $4::numeric");
    expect(query.mock.calls[5][1]).toEqual([
      "lesson-a",
      "student-a",
      null,
      1,
      1,
    ]);
  });

  it("never charges a converted trial lesson even when attendance is present", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "trial-a",
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
      { rows: [] }, // participation upsert
      { rows: [] }, // reconcile advisory lock
      {
        rows: [
          {
            attendance_kind: "attended",
            charge_share: 1,
            charged_hours: 0,
            subscription_id: null,
            hours: 1,
            is_trial: true,
          },
        ],
      },
      { rows: [] }, // lesson complete update (no charge query in between)
      {
        rows: [
          {
            id: "trial-a",
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
        rows: [{ student_id: "student-a", status: "present", pass_reason: null }],
      },
    ]);

    await service.upsertLessonAttendance(actor, "trial-a", {
      items: [{ studentId: "student-a", kind: "attended" }],
    });

    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("lessons_used = lessons_used +"),
      ),
    ).toBe(false);
    expect(String(query.mock.calls[5][0])).toContain("update app.lessons");
  });

  it("notifies direct, linked and family client audience after attendance changes", async () => {
    const { service, query, notifications } = createServiceWithQueryResults([
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
      { rows: [] }, // participation upsert
      { rows: [] }, // reconcile lock
      { rows: [] }, // no reconcile state
      { rows: [] }, // lesson complete update (same transaction)
      { rows: [{ scheduled_at: "2026-07-18T12:00:00.000Z" }] },
      {
        rows: [
          { user_id: "client-own" },
          { user_id: "client-linked" },
          { user_id: "client-parent" },
        ],
      },
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
    ]);

    await service.upsertLessonAttendance(actor, "lesson-a", {
      items: [{ studentId: "student-a", kind: "free_lesson" }],
      notifyClient: true,
    });

    expect(String(query.mock.calls[7][0])).toContain("app.user_crm_links link");
    expect(String(query.mock.calls[7][0])).toContain(
      "account_member.role in ('parent', 'payer')",
    );
    expect(notifications.notifyUser).toHaveBeenCalledTimes(3);
    expect(
      notifications.notifyUser.mock.calls.map((call) => call[0].userId),
    ).toEqual(["client-own", "client-linked", "client-parent"]);
    expect(notifications.notifyUser).toHaveBeenCalledWith(
      expect.objectContaining({ channels: ["in_app", "push"] }),
    );
  });

  it("refunds only the delta when a charged lesson becomes partially paid (KVA-237)", async () => {
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
      { rows: [] }, // participation upsert
      { rows: [] }, // reconcile advisory lock
      // Ранее списан полный час, статус меняется задним числом на partially_paid 0.5
      {
        rows: [
          {
            attendance_kind: "partially_paid",
            charge_share: 0.5,
            charged_hours: 1,
            subscription_id: "sub-a",
            hours: 1,
          },
        ],
      },
      { rows: [] }, // refund query
      { rows: [] }, // lesson complete update
      {
        rows: [
          { id: "lesson-a", student_id: "student-a", group_id: null, teacher_user_id: "t" },
        ],
      },
      {
        rows: [
          { student_id: "student-a", first_name: "Анна", last_name: "Иванова" },
        ],
      },
      { rows: [] },
    ]);

    await service.upsertLessonAttendance(actor, "lesson-a", {
      items: [{ studentId: "student-a", kind: "partially_paid", chargeShare: 0.5 }],
    });

    // Возврат ровно дельты: −0.5 часа; charged_hours станет 0.5, связь остаётся.
    const refundSql = String(query.mock.calls[5][0]);
    expect(refundSql).toContain("greatest(lessons_used + $4::numeric, 0)");
    expect(query.mock.calls[5][1]).toEqual([
      "lesson-a",
      "student-a",
      "sub-a",
      -0.5,
      0.5,
    ]);
  });
});
