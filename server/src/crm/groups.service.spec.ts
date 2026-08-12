import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { GroupsService } from "./groups.service";

describe("GroupsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const build = (query: jest.Mock) => {
    const database = {
      query,
      transaction: jest.fn(
        (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
          work({ query }),
      ),
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanManageSystemSettings: jest.fn(),
    };
    const realtime = { emitCrmChanged: jest.fn() };
    const service = new GroupsService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, audit, policy, realtime };
  };

  const createService = (rows: Record<string, unknown>[] = []) =>
    build(jest.fn().mockResolvedValue({ rows }));

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) query.mockResolvedValueOnce(result);
    return build(query);
  };

  describe("getGroup", () => {
    it("returns a single group by id", async () => {
      const { service, query, policy } = createService([
        {
          id: "group-a",
          teacher_id: "teacher-a",
          branch_id: "branch-a",
          room_id: "room-a",
          name: "Гитара",
          price_per_lesson: "1500",
          teacher_rate: null,
          teacher_name: "Иван Петров",
          branch_name: "Сокол",
          room_name: "Room 4",
          created_at: new Date().toISOString(),
        },
      ]);

      const group = await service.getGroup(actor, "group-a");

      expect(group.id).toBe("group-a");
      expect(group.name).toBe("Гитара");
      expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
      expect(String(query.mock.calls[0][0])).toContain("g.id = $1");
      expect(query.mock.calls[0][1]).toEqual(["group-a"]);
    });

    it("throws when the group does not exist", async () => {
      const { service } = createService([]);

      await expect(service.getGroup(actor, "missing")).rejects.toThrow(
        "Группа не найдена.",
      );
    });
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
        students_count: "7",
        lifecycle_state: "active",
        version: "3",
        archived_at: null,
        archive_reason: null,
        archive_effective_date: null,
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
          teacherRate: null, // KVA-238: переопределение не задано
          teacherName: "Иван Петров",
          branchName: "Центр",
          roomName: "101",
          studentsCount: 7,
          lifecycleState: "active",
          version: 3,
          archivedAt: null,
          archiveReason: null,
          archiveEffectiveDate: null,
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });
  });

  it("includes archived groups only when explicitly requested", async () => {
    const { service, query } = createService([]);
    await service.listGroups(actor, { limit: 100, includeArchived: true });
    expect(query.mock.calls[0][0]).toContain("$6::boolean");
    expect(query.mock.calls[0][1]).toEqual([
      null,
      null,
      100,
      "manager",
      "manager-a",
      true,
    ]);
  });

  it("blocks assignment changes until the group's live schedule is resolved", async () => {
    const { service, query } = createService([
      {
        teacher_id: "teacher-a",
        branch_id: "branch-a",
        room_id: "room-a",
        future_lessons: 2,
        active_series: 1,
        active_plans: 1,
      },
    ]);
    await expect(
      service.updateGroup(
        { userId: "director-a", role: "director" },
        "group-a",
        { roomId: "room-b" },
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "GROUP_ASSIGNMENT_CHANGE_BLOCKED",
        blockers: expect.arrayContaining([
          expect.objectContaining({ code: "FUTURE_LESSONS", count: 2 }),
          expect.objectContaining({
            code: "ACTIVE_RECURRING_SERIES",
            count: 1,
          }),
          expect.objectContaining({ code: "ACTIVE_SCHEDULE_PLANS", count: 1 }),
        ]),
      }),
    });
    expect(query).toHaveBeenCalledTimes(1);
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
      service.createGroup(
        { userId: "director-a", role: "director" },
        {
          name: " Фортепиано ",
          teacherId: "teacher-a",
          branchId: "branch-a",
          roomId: "room-a",
          pricePerLesson: 3000,
        },
      ),
    ).resolves.toMatchObject({
      id: "group-b",
      name: "Фортепиано",
      pricePerLesson: 3000,
      teacherName: "Мария Петрова",
    });

    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledWith({
      userId: "director-a",
      role: "director",
    });
    expect(query.mock.calls[0][1]).toEqual([
      "teacher-a",
      "branch-a",
      "room-a",
      "Фортепиано",
      3000,
      null, // KVA-238: teacherRate не передан
    ]);
    expect(query.mock.calls[0][0]).toContain("tb.active_from <= current_date");
    expect(query.mock.calls[0][0]).toContain("tb.active_until >= current_date");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.group_created",
        entityType: "group",
        entityId: "group-b",
      }),
    );
  });

  it("keeps rate-only updates available for imported incomplete groups", async () => {
    const { service, query } = createService([
      {
        id: "legacy-group",
        teacher_id: null,
        branch_id: null,
        room_id: null,
        name: "Архивная группа",
        price_per_lesson: null,
        teacher_rate: "1200",
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await service.updateGroup(
      { userId: "director-a", role: "director" },
      "legacy-group",
      { teacherRate: 1200 },
    );

    expect(query.mock.calls[1][1]).toEqual([
      "legacy-group",
      null,
      null,
      null,
      null,
      null,
      true,
      1200,
      false,
    ]);
    expect(query.mock.calls[1][0]).toContain("where not $9::boolean");
  });

  it("rejects manager updates for imported groups without a branch", async () => {
    const { service, query } = createService([
      {
        teacher_id: null,
        branch_id: null,
        room_id: null,
        future_lessons: 0,
        active_series: 0,
        active_plans: 0,
      },
    ]);

    await expect(
      service.updateGroup(actor, "legacy-group", { name: "Чужая группа" }),
    ).rejects.toThrow("Группа не относится к доступному филиалу.");
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("adds and removes group students through v3 contract", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      // addGroupStudent: group branch + actor branches + insert + audiences
      { rows: [{ branch_id: "branch-a" }] },
      { rows: [{ branch_id: "branch-a" }] },
      { rows: [{ id: "group-student-a", student_id: "student-a" }] },
      { rows: [] },
      { rows: [] },
      // removeGroupStudent: scope + group lock + blocker check + update + audiences
      { rows: [{ branch_id: "branch-a" }] },
      { rows: [{ branch_id: "branch-a" }] },
      { rows: [] },
      { rows: [] },
      { rows: [{ id: "group-student-a" }] },
      { rows: [] },
      { rows: [] },
    ]);

    await expect(
      service.addGroupStudent(actor, "group-a", "student-a"),
    ).resolves.toEqual({ success: true });
    await expect(
      service.removeGroupStudent(actor, "group-a", "student-a"),
    ).resolves.toEqual({ success: true });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledTimes(2);
    expect(query.mock.calls[2][1]).toEqual([
      "group-a",
      "student-a",
      "manager",
      "manager-a",
    ]);
    expect(query.mock.calls[2][0]).toContain(
      "scope_assignment.branch_id::text",
    );
    expect(query.mock.calls[7][1]).toEqual(["group:group-a"]);
    expect(query.mock.calls[8][1]).toEqual(["group-a", "student-a"]);
    expect(query.mock.calls[9][1]).toEqual(["group-a", "student-a"]);
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

  it("blocks removing a student who remains in an active group plan", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [{ branch_id: "branch-a" }] },
      { rows: [{ branch_id: "branch-a" }] },
      { rows: [] },
      { rows: [{ id: "plan-a", title: "Вокальная группа" }] },
    ]);

    await expect(
      service.removeGroupStudent(actor, "group-a", "student-a"),
    ).rejects.toMatchObject({
      response: {
        code: "GROUP_STUDENT_ACTIVE_SCHEDULE_PLAN",
        plans: [{ id: "plan-a", title: "Вокальная группа" }],
      },
    });

    expect(query).toHaveBeenCalledTimes(4);
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("denies direct membership mutation outside manager branch scope", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [{ branch_id: "branch-b" }] },
      { rows: [{ branch_id: "branch-a" }] },
    ]);

    await expect(
      service.addGroupStudent(actor, "group-b", "student-a"),
    ).rejects.toThrow("Группа не входит в область доступа.");
    expect(query).toHaveBeenCalledTimes(2);
    expect(audit.record).not.toHaveBeenCalled();
  });
});
