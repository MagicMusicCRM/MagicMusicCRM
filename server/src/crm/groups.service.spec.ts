import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { GroupsService } from "./groups.service";

describe("GroupsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const build = (query: jest.Mock) => {
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
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
          teacherRate: null, // KVA-238: переопределение не задано
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
      null, // KVA-238: teacherRate не передан
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.group_created",
        entityType: "group",
        entityId: "group-b",
      }),
    );
  });

  it("adds and removes group students through v3 contract", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      // addGroupStudent: insert + affectedUserIdsForGroup + affectedUserIdsForStudent
      { rows: [{ id: "group-student-a", student_id: "student-a" }] },
      { rows: [] },
      { rows: [] },
      // removeGroupStudent: update + affectedUserIdsForGroup + affectedUserIdsForStudent
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
    expect(query.mock.calls[0][1]).toEqual(["group-a", "student-a"]);
    expect(query.mock.calls[3][1]).toEqual(["group-a", "student-a"]);
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
});
