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
    const database = { query };
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
          dueAt: "2026-06-13T00:00:00.000Z",
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
          dueAt: "2026-06-13T00:00:00.000Z",
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
});
