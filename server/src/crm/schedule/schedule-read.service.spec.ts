import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { ScheduleReadService } from "./schedule-read.service";

describe("schedule read contract", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      canReadTeacherRates: jest.fn().mockReturnValue(false),
      canReadSchoolFinance: jest.fn().mockReturnValue(false),
      canReadStudentFinance: jest.fn().mockReturnValue(false),
    };
    const service = new ScheduleReadService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, policy };
  };

  it("depends only on database and CRM policy", () => {
    expect(
      Reflect.getMetadata("design:paramtypes", ScheduleReadService),
    ).toEqual([DatabaseService, CrmPolicy]);
  });

  it("reads exact lesson finance and frozen membership with current-role gates", async () => {
    const { service, query } = createService([{
      id: "lesson-1", reservation_state: "reserved",
      financial_decision: {
        settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
        teacherCreditedDurationMinutes: 45,
        teacherCompensationSource: "manual",
        clientDecisions: [{
          clientId: "student-1", payerStudentId: "payer-1",
          chargeDurationMinutes: 0,
        }],
      },
      group_participants: [{ clientId: "student-1", clientName: "Анна" }],
    }]);
    const result = await service.listLessons(actor, { lessonId: "lesson-1" });
    expect(result.items[0]).toMatchObject({
      reservationState: "reserved",
      financialDecision: {
        settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
        teacherCreditedDurationMinutes: 45,
        teacherCompensationSource: "manual",
        clientDecisions: [{
          clientId: "student-1", payerStudentId: "payer-1",
          chargeDurationMinutes: 0,
        }],
      },
      groupParticipants: [{ clientId: "student-1", clientName: "Анна" }],
    });
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("else null::jsonb end as financial_decision");
    expect(sql).toContain("coalesce(correction.decision, transition.financial_decision, plan.decision)");
    expect(sql).toContain("from app.users scope_actor");
    expect(sql).toContain("where participant.lesson_id = l.id");
    expect(sql).toContain("app.lesson_participant_exclusions exclusion");
  });

  describe("«оплаты по дням» (✔ владелец 17.07)", () => {
    it("sums the payments tied to each lesson", async () => {
      const { service, query, policy } = createService([]);
      policy.canReadStudentFinance.mockReturnValue(true);

      await service.listLessons(actor, { limit: 10 });

      const sql = String(query.mock.calls[0][0]);
      expect(sql).toContain("from app.commerce_ordinary_payments pay");
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

    it("gates client money with the current database role", async () => {
      const { service, query } = createService([]);

      await service.listLessons(
        { userId: "teacher-1", role: "teacher" as const },
        { limit: 10 },
      );

      const sql = String(query.mock.calls[0][0]);
      // Не «скрыто в UI»: PostgreSQL возвращает null, опираясь на актуальную
      // роль из app.users, даже если JWT с прежней ролью ещё не истёк.
      expect(sql).toContain("from app.users scope_actor");
      expect(sql).toContain("else null::numeric end as paid_amount");
      expect(sql).toContain("= 'client'");
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

    it("gates pay rates with the current database role", async () => {
      const { service, query } = createService([]);

      await service.listLessons(clientActor, { limit: 10 });

      const sql = String(query.mock.calls[0][0]);
      // listLessons serves clients too, so SQL itself must null the projection
      // according to app.users.role rather than trusting the JWT claim.
      expect(sql).toContain("from app.users scope_actor");
      expect(sql).toContain("else null::numeric end as applied_teacher_rate");
      expect(sql).toContain(
        "else null::text end as teacher_compensation_rule_key",
      );
      expect(sql).toContain(
        "else null::text end as teacher_compensation_value_minor",
      );
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
        /coalesce\(\s*l\.teacher_rate,\s*g\.teacher_rate,[\s\S]*app\.teacher_rates[\s\S]*0\s*\)\s*else null::numeric end as applied_teacher_rate/,
      );
      expect(sql).toContain(
        "coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'teacherCompensationRuleKey' else null::text end as teacher_compensation_rule_key",
      );
      expect(sql).toContain(
        "coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'teacherCompensationValueMinor' else null::text end as teacher_compensation_value_minor",
      );
    });

    it("uses the current-role per-lesson gate, not the aggregate-finance gate", async () => {
      const { service, query, policy } = createService([]);
      const managerActor = { userId: "mgr-1", role: "manager" as const };

      await service.listLessons(managerActor, { limit: 10 });

      // The owner's 16.07 decision: a per-lesson rate is not a school-wide
      // total, so admin/manager see it. Gating this on canReadSchoolFinance
      // would hide it from exactly the people who set it.
      expect(String(query.mock.calls[0][0])).toContain(
        "scope_actor.role::text",
      );
      expect(policy.canReadTeacherRates).not.toHaveBeenCalled();
      expect(policy.canReadSchoolFinance).not.toHaveBeenCalled();
    });
  });

  it("projects settlement failure only to staff who can repair it", async () => {
    const client = createService([]);
    await client.service.listLessons(
      { userId: "client-1", role: "client" },
      { limit: 10 },
    );
    const clientSql = String(client.query.mock.calls[0][0]);
    expect(clientSql).toContain(
      "then plan.failure_code else null::text end as settlement_failure_code",
    );
    expect(clientSql).toContain("app.lesson_settlement_plans plan");

    const manager = createService([]);
    await manager.service.listLessons(actor, { limit: 10 });
    expect(String(manager.query.mock.calls[0][0])).toContain(
      "then plan.failure_code else null::text end as settlement_failure_code",
    );
  });

  it("lists trial lessons with actor-scoped query", async () => {
    const { service, query } = createService([
      {
        id: "lesson-a",
        lifecycle_state: "successfully_completed",
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

    expect(String(query.mock.calls[0][0])).toContain(
      "l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')",
    );
    expect(String(query.mock.calls[0][0])).toContain(
      "from app.users scope_actor",
    );
    expect(String(query.mock.calls[0][0])).toContain(
      "scope_assignment.branch_id::text = coalesce(l.branch_id::text, g.branch_id::text, r.branch_id::text)",
    );

    expect(query.mock.calls[0][1]).toEqual([
      "manager-a",
      null,
      null,
      null,
      null,
      null,
      true,
      10,
    ]);
  });

  it("fails closed when the current database role is unknown", async () => {
    const { service, query } = createService([]);
    const unknownActor = {
      userId: "00000000-0000-4000-8000-000000000099",
      role: "unknown-role" as never,
    };

    await expect(
      service.listLessons(unknownActor, { limit: 10 }),
    ).resolves.toEqual({
      items: [],
    });

    const [rawSql, params] = query.mock.calls[0];
    const sql = String(rawSql);
    expect(params).toEqual([
      "00000000-0000-4000-8000-000000000099",
      null,
      null,
      null,
      null,
      null,
      null,
      10,
    ]);
    expect(sql).toContain("from app.users scope_actor");
    expect(sql).toContain("scope_actor.role::text");
    expect(sql).toContain("= 'teacher' and tp.user_id = $1");
    expect(sql).toContain("= 'client' and (");
    expect(sql).not.toContain("$1::text in ('manager'");
  });

  it("loads one exact terminal lesson without weakening actor scope", async () => {
    const { service, query } = createService([]);
    const lessonId = "11111111-1111-4111-8111-111111111111";

    await service.listLessons(
      { userId: "teacher-1", role: "teacher" },
      { lessonId, limit: 1 },
    );

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("$2::uuid is not null");
    expect(sql).toContain("$2::uuid is null or l.id = $2");
    expect(sql).toContain("= 'teacher' and tp.user_id = $1");
    expect(sql).toContain("from app.users scope_actor");
    expect(query.mock.calls[0][1]).toEqual([
      "teacher-1",
      lessonId,
      null,
      null,
      null,
      null,
      null,
      1,
    ]);
  });

  it("keeps terminal cancellation and reschedule sources out of month totals", async () => {
    const { service, query, policy } = createService([
      { day: "2026-06-15", count: "2", room_ids: ["room-a"] },
    ]);

    await expect(
      service.getScheduleMonthSummary(actor, {
        from: "2026-06-01T00:00:00.000+03:00",
        to: "2026-07-01T00:00:00.000+03:00",
      }),
    ).resolves.toMatchObject({
      items: [{ day: "2026-06-15", count: 2, roomIds: ["room-a"] }],
    });

    const [rawSql, params] = query.mock.calls[0];
    const sql = String(rawSql);
    expect(sql).toContain(
      "l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')",
    );
    expect(sql).toContain(
      "timezone(coalesce(b.timezone_name, 'Europe/Moscow'), l.scheduled_at)::date",
    );
    expect(params).toEqual([
      "2026-05-31T21:00:00.000Z",
      "2026-06-30T21:00:00.000Z",
      null,
      "manager-a",
    ]);
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(sql).toContain("from app.users scope_actor");
    expect(sql).toContain(
      "scope_assignment.branch_id::text = coalesce(l.branch_id::text, g.branch_id::text, r.branch_id::text)",
    );
  });

  it("keeps post-conversion lessons visible to manual-link and family clients", async () => {
    const { service, query } = createService([]);

    await service.listLessons(
      { userId: "client-parent", role: "client" },
      { studentId: "student-a", limit: 10 },
    );

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.user_crm_links student_link");
    expect(sql).toContain("student_member.entity_id = l.student_id");
    expect(sql).toContain("account_member.role in ('parent', 'payer')");
    expect(sql).toContain("app.user_crm_links group_student_link");
    expect(query.mock.calls[0][1]).toEqual([
      "client-parent",
      null,
      "student-a",
      null,
      null,
      null,
      null,
      10,
    ]);
  });

  it("returns schedule matrix grouped by room with conflicts", async () => {
    const { service, query, policy } = createService([
      {
        id: "lesson-a",
        version: 2,
        lifecycle_state: "settlement_pending",
        settlement_failure_code: "ConflictException",
        settlement_type_key: "free_lesson",
        teacher_compensation_rule_key: "fixed",
        teacher_compensation_value_minor: "150000",
        reservation_state: "reserved",
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
        group_participants: [
          { clientId: "student-a", clientName: "Анна Иванова" },
        ],
        conflict_types: ["room_overlap"],
      },
    ]);

    const matrix = await service.getScheduleMatrix(actor, {
      from: "2026-06-15T00:00:00.000Z",
      to: "2026-06-16T00:00:00.000Z",
      branchId: "branch-a",
      roomId: "room-a",
      teacherId: "teacher-a",
      studentId: "student-a",
      leadId: "lead-a",
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
      version: 2,
      lifecycleState: "settlement_pending",
      settlementFailureCode: "ConflictException",
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "fixed",
      teacherCompensationValueMinor: "150000",
      reservationState: "reserved",
      groupParticipants: [
        { clientId: "student-a", clientName: "Анна Иванова" },
      ],
      conflictTypes: ["room_overlap"],
    });
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain(
      "l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')",
    );
    expect(sql).toContain(
      "other_room.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')",
    );
    expect(sql).toContain("select l.id, l.version, l.lifecycle_state");
    expect(sql).toContain("app.lesson_settlement_plans plan");
    expect(sql).toContain("app.lesson_reservations lesson_reservation");
    expect(sql).toContain("scoped.reservation_state, scoped.financial_decision");
    expect(sql).toContain("app.lesson_snapshot_participants participant");
    expect(sql).toContain("app.lesson_participant_exclusions exclusion");
    expect(sql).toContain("then plan.failure_code else null end");

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "2026-06-15T00:00:00.000Z",
      "2026-06-16T00:00:00.000Z",
      "branch-a",
      "room-a",
      "teacher-a",
      "student-a",
      "lead-a",
      true,
      null,
      30,
      "manager-a",
    ]);
    expect(String(query.mock.calls[0][0])).toContain("scope_actor.role::text");
    expect(sql).toContain("from app.users scope_actor");
    expect(sql).toContain(
      "scope_assignment.branch_id::text = coalesce(l.branch_id::text, g.branch_id::text, r.branch_id::text)",
    );
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

  it("surfaces the lead's name in schedule feeds (no more «Не назначен»)", async () => {
    const { service, query } = createService([]);

    await service.listLessons(actor, { limit: 10 });

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("as lead_name");
    expect(sql).toContain("left join app.leads ld on ld.id = l.lead_id");
  });

  it("owns the upcoming self-view projection for direct and group students", async () => {
    const { service, query } = createService([]);

    await expect(
      service.listUpcomingLessonsForStudents(["student-a", "student-b"]),
    ).resolves.toEqual([]);

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("l.student_id = any($1::uuid[])");
    expect(sql).toContain("from app.group_students gs");
    expect(query.mock.calls[0][1]).toEqual([["student-a", "student-b"]]);
  });

  it("does not query upcoming lessons for an empty student set", async () => {
    const { service, query } = createService([]);

    await expect(service.listUpcomingLessonsForStudents([])).resolves.toEqual(
      [],
    );
    expect(query).not.toHaveBeenCalled();
  });

  it("orders the client history desc when asked (recent lessons first)", async () => {
    const { service, query } = createService([]);

    await service.listLessons(
      { userId: "client-1", role: "client" as const },
      { to: "2026-07-18T00:00:00.000Z", limit: 50, order: "desc" },
    );

    expect(String(query.mock.calls[0][0])).toContain(
      "order by l.scheduled_at desc",
    );
  });
});
