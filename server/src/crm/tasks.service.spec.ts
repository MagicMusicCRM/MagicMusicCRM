import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { TasksService } from "./tasks.service";

describe("TasksService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = {
      query,
      // Transactional writes share the same query mock so sequential
      // mockResolvedValueOnce chains keep working.
      transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertManagerOnly: jest.fn(),
    };
    const notifications = { notifyUser: jest.fn().mockResolvedValue(undefined) };
    const realtime = { emitCrmChanged: jest.fn() };
    const service = new TasksService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      notifications as unknown as NotificationsService,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, audit, policy, notifications, realtime };
  };

  it("lists tasks with status and student filters plus display names", async () => {
    const { service, query, policy } = createService([
      {
        id: "task-a",
        entity_type: "student",
        entity_id: "student-a",
        assigned_to: "manager-a",
        assigned_first_name: "Мария",
        assigned_last_name: "Менеджер",
        entity_first_name: "Анна",
        entity_last_name: "Иванова",
        entity_name: null,
        title: "Позвонить",
        description: null,
        status: "open",
        due_at: "2026-06-13T00:00:00.000Z",
        created_by: "admin-a",
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listTasks(actor, {
        studentId: "student-a",
        status: "open",
        limit: 15,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "task-a",
          entityType: "student",
          entityId: "student-a",
          assignedTo: "manager-a",
          assignedName: "Мария Менеджер",
          assignedProfileId: null,
          creatorProfileId: null,
          entityName: "Анна Иванова",
          title: "Позвонить",
          description: null,
          status: "open",
          priority: "medium",
          dueAt: "2026-06-13T00:00:00.000Z",
          dueAllDay: false,
          createdBy: "admin-a",
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      15,
      "student-a",
      "open",
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
    ]);
    // Reading tasks is operational (shown in client cards to admin/teacher),
    // not a manager-only management op.
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(policy.assertManagerOnly).not.toHaveBeenCalled();
  });

  it("lists task board with operational filters and branch context", async () => {
    const { service, query } = createService([
      {
        id: "task-a",
        entity_type: "lead",
        entity_id: "lead-a",
        assigned_to: "manager-a",
        assigned_first_name: "Мария",
        assigned_last_name: "Менеджер",
        creator_first_name: "Ольга",
        creator_last_name: "Админ",
        entity_first_name: null,
        entity_last_name: null,
        entity_name: "Анна Иванова",
        branch_id: "branch-a",
        branch_name: "Центр",
        title: "Позвонить",
        description: "Приоритет высокий, WhatsApp",
        status: "open",
        due_at: "2026-06-13T00:00:00.000Z",
        created_by: "admin-a",
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listTasks(actor, {
        q: "анна",
        entityType: "lead",
        entityId: "lead-a",
        assignedTo: "manager-a",
        createdBy: "admin-a",
        branchId: "branch-a",
        status: "open",
        priority: "высокий",
        taskType: "звонок",
        communicationMethod: "WhatsApp",
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        limit: 25,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "task-a",
          entityType: "lead",
          entityId: "lead-a",
          assignedTo: "manager-a",
          assignedName: "Мария Менеджер",
          assignedProfileId: null,
          creatorProfileId: null,
          entityName: "Анна Иванова",
          title: "Позвонить",
          description: "Приоритет высокий, WhatsApp",
          status: "open",
          priority: "medium",
          dueAt: "2026-06-13T00:00:00.000Z",
          dueAllDay: false,
          createdBy: "admin-a",
          createdAt: "2026-06-12T00:00:00.000Z",
          creatorName: "Ольга Админ",
          branchId: "branch-a",
          branchName: "Центр",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      25,
      null,
      "open",
      "анна",
      "lead",
      "lead-a",
      "manager-a",
      "admin-a",
      "branch-a",
      "высокий",
      "звонок",
      "WhatsApp",
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
    ]);
  });

  const taskRow = (overrides: Record<string, unknown> = {}) => ({
    id: "task-a",
    entity_type: "student",
    entity_id: "student-a",
    assigned_to: "manager-a",
    title: "Позвонить",
    description: null,
    status: "open",
    due_at: "2026-06-13T10:00:00.000Z",
    created_by: "admin-a",
    created_at: "2026-06-12T00:00:00.000Z",
    ...overrides,
  });

  it("logs a due-date move with the author, so supervisors can see who moved it", async () => {
    const { service, query } = createService();
    query
      .mockResolvedValueOnce({ rows: [taskRow()] }) // select ... for update
      .mockResolvedValueOnce({
        rows: [taskRow({ due_at: "2026-06-20T10:00:00.000Z" })],
      }) // update
      .mockResolvedValueOnce({ rows: [] }); // history insert

    await service.updateTask(actor, "task-a", {
      dueAt: "2026-06-20T10:00:00.000Z",
    } as never);

    // The "before" read must lock the row: two concurrent PATCHes would
    // otherwise both log the same old value.
    expect(String(query.mock.calls[0][0])).toContain("for update");

    const historySql = String(query.mock.calls[2][0]);
    expect(historySql).toContain("app.task_history");
    expect(query.mock.calls[2][1]).toEqual([
      "task-a",
      "due_at",
      "2026-06-13T10:00:00.000Z",
      "2026-06-20T10:00:00.000Z",
      null,
      null,
      "manager-a",
    ]);
  });

  it("logs one row per changed field and leaves untouched fields alone", async () => {
    const { service, query } = createService();
    query
      .mockResolvedValueOnce({ rows: [taskRow()] })
      .mockResolvedValueOnce({
        rows: [taskRow({ status: "done", assigned_to: "manager-b" })],
      })
      .mockResolvedValue({ rows: [] });

    await service.updateTask(actor, "task-a", {
      status: "done",
      assignedTo: "manager-b",
    } as never);

    const inserts = query.mock.calls
      .slice(2)
      .map((call) => call[1] as unknown[]);
    expect(inserts.map((params) => params[1])).toEqual([
      "status",
      "assigned_to",
    ]);
    // Reassignment carries user ids, not names: the feed joins profiles at read
    // time so a later rename reads correctly in old events.
    const assignment = inserts[1];
    expect(assignment[2]).toBeNull();
    expect(assignment[3]).toBeNull();
    expect(assignment[4]).toBe("manager-a");
    expect(assignment[5]).toBe("manager-b");
  });

  it("writes no history when a PATCH changes nothing", async () => {
    const { service, query } = createService();
    query
      .mockResolvedValueOnce({ rows: [taskRow()] })
      .mockResolvedValueOnce({ rows: [taskRow()] });

    await service.updateTask(actor, "task-a", { status: "open" } as never);

    // Two calls only — select + update. A coalesce-update turns an unmentioned
    // field into null, and logging that as «изменено на пусто» would be a lie.
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("does not log a phantom reschedule when the driver returns a Date", async () => {
    const { service, query } = createService();
    // Same instant, different representations: a naive string compare would
    // record a reschedule that never happened.
    query
      .mockResolvedValueOnce({
        rows: [taskRow({ due_at: new Date("2026-06-13T10:00:00.000Z") })],
      })
      .mockResolvedValueOnce({
        rows: [taskRow({ due_at: "2026-06-13T10:00:00.000Z" })],
      });

    await service.updateTask(actor, "task-a", {
      dueAt: "2026-06-13T10:00:00.000Z",
    } as never);

    expect(query).toHaveBeenCalledTimes(2);
  });

  it("anchors the feed with a 'created' event", async () => {
    const { service, query } = createService();
    query
      .mockResolvedValueOnce({ rows: [taskRow()] })
      .mockResolvedValueOnce({ rows: [] });

    await service.createTask(actor, {
      entityType: "student",
      entityId: "student-a",
      title: "Позвонить",
      dueAt: "2026-06-13T10:00:00.000Z",
    } as never);

    expect(String(query.mock.calls[1][0])).toContain("'created'");
    expect(query.mock.calls[1][1]).toEqual([
      "task-a",
      "Позвонить",
      "manager-a",
      "manager-a",
    ]);
  });

  it("defaults the supervisor feed to due-date moves", async () => {
    const { service, query, policy } = createService([]);

    await service.listTaskHistoryFeed(actor, {});

    expect(query.mock.calls[0][1][0]).toBe("due_at");
    // Cross-task oversight, not shop-floor operational data.
    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
  });

  it("counts tasks per Moscow day for the calendar, filtered like the board", async () => {
    const { service, query, policy } = createService([
      { day: "2026-07-10", count: 3 },
      { day: "2026-07-12", count: 1 },
    ]);

    await expect(
      service.taskCalendar(actor, {
        from: "2026-07-01T00:00:00.000Z",
        to: "2026-08-01T00:00:00.000Z",
        priority: "high",
      } as never),
    ).resolves.toEqual({
      items: [
        { day: "2026-07-10", count: 3 },
        { day: "2026-07-12", count: 1 },
      ],
    });

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("at time zone 'Europe/Moscow'");
    expect(sql).toContain("group by 1");
    expect(sql).toContain("task.due_at is not null");
    // Same filter params as the board list — priority at position 12, range at
    // 15/16 — so a day's count matches the list you get by opening it.
    expect(query.mock.calls[0][1][11]).toBe("high");
    expect(query.mock.calls[0][1][14]).toBe("2026-07-01T00:00:00.000Z");
    expect(query.mock.calls[0][1][15]).toBe("2026-08-01T00:00:00.000Z");
    // Reading, not a management op.
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
  });

  it("refuses to create a task with no due date (owner rule)", async () => {
    const { service } = createService();
    await expect(
      service.createTask(actor, {
        entityType: "student",
        entityId: "student-a",
        title: "Позвонить",
      } as never),
    ).rejects.toThrow("срок выполнения");
  });

  it("persists priority and the all-day flag on create", async () => {
    const { service, query } = createService();
    query
      .mockResolvedValueOnce({ rows: [taskRow({ priority: "high" })] })
      .mockResolvedValueOnce({ rows: [] });

    await service.createTask(actor, {
      entityType: "student",
      entityId: "student-a",
      title: "Позвонить",
      dueAt: "2026-06-13T10:00:00.000Z",
      priority: "high",
      dueAllDay: true,
    } as never);

    const insert = query.mock.calls[0][1];
    // …title, description, status, priority, dueAt, dueAllDay, createdBy
    expect(insert).toEqual([
      "student",
      "student-a",
      null,
      "Позвонить",
      null,
      null,
      "high",
      "2026-06-13T10:00:00.000Z",
      true,
      "manager-a",
    ]);
  });

  it("filters the board by real priority, not a title substring", async () => {
    const { service, query } = createService([]);

    await service.listTasks(actor, { priority: "high" } as never);

    // Priority is bound at position 12; the SQL must compare the column.
    expect(query.mock.calls[0][1][11]).toBe("high");
    expect(String(query.mock.calls[0][0])).toContain("task.priority = $12");
  });

  it("soft-deletes a task and emits a delete event", async () => {
    const { service, query, audit, realtime } = createService([
      { id: "task-a" },
    ]);

    await expect(service.deleteTask(actor, "task-a")).resolves.toEqual({
      id: "task-a",
      deleted: true,
    });

    expect(String(query.mock.calls[0][0])).toContain("set deleted_at = now()");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.task_deleted" }),
    );
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith(
      expect.objectContaining({ entity: "task", action: "deleted" }),
    );
  });

  it("404s deleting a task that is already gone", async () => {
    const { service } = createService([]);
    await expect(service.deleteTask(actor, "task-x")).rejects.toThrow(
      "не найдена",
    );
  });
});
