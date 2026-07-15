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
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const notifications = { notifyUser: jest.fn().mockResolvedValue(undefined) };
    const service = new AttendanceService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      notifications as unknown as NotificationsService,
    );
    return { service, query, audit, notifications };
  };

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
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lesson_attendance_updated",
        entityType: "lesson",
        entityId: "lesson-a",
      }),
    );
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
      // reconcile state: attended, ничего ещё не списано, урок = 1 час
      {
        rows: [
          {
            attendance_kind: "attended",
            charge_share: 1,
            charged_hours: 0,
            subscription_id: null,
            hours: 1,
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
    const chargeSql = String(query.mock.calls[4][0]);
    expect(chargeSql).toContain("lessons_used = lessons_used + $4::numeric");
    expect(query.mock.calls[4][1]).toEqual([
      "lesson-a",
      "student-a",
      null,
      1,
      1,
    ]);
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
    const refundSql = String(query.mock.calls[4][0]);
    expect(refundSql).toContain("greatest(lessons_used + $4::numeric, 0)");
    expect(query.mock.calls[4][1]).toEqual([
      "lesson-a",
      "student-a",
      "sub-a",
      -0.5,
      0.5,
    ]);
  });
});
