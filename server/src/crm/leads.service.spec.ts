import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { LeadsService } from "./leads.service";

describe("LeadsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const makeLeads = (db: { query?: jest.Mock; transaction?: jest.Mock }) => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanWriteCrm: jest.fn(),
      assertCanReadOperationalData: jest.fn(),
    };
    const notifications = {
      notifyNewLead: jest.fn().mockResolvedValue(undefined),
    };
    const realtime = { emitCrmChanged: () => undefined };
    const service = new LeadsService(
      db as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      notifications as unknown as NotificationsService,
      realtime as unknown as RealtimeBus,
    );
    return { service, audit, policy, notifications };
  };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    return { query, transaction, ...makeLeads({ query, transaction }) };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    return { query, transaction, ...makeLeads({ query, transaction }) };
  };

  it("returns lead board columns with counts and aggregate lead fields", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "status-a",
            name: "Новый",
            color: "#C5A059",
            sort_order: 1,
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
      { rows: [{ status_id: "status-a", count: "2" }] },
      {
        rows: [
          {
            id: "11111111-1111-4111-8111-111111111111",
            status_id: "status-a",
            status_name: "Новый",
            status_color: "#C5A059",
            status_sort_order: 1,
            first_name: "Анна",
            last_name: "Иванова",
            phone: "+79990000000",
            email: "anna@example.com",
            source: "site",
            notes: null,
            assigned_to: "manager-a",
            assigned_first_name: "Мария",
            assigned_last_name: "Менеджер",
            branch_id: "branch-a",
            branch_name: "Центр",
            linked_student_id: "student-a",
            open_tasks_count: "2",
            comments_count: "3",
            trial_lessons_count: "1",
            custom_data: { discipline: "Вокал", hollihopId: "HH-42" },
            created_by: "manager-a",
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listLeadBoard(actor, {
        q: "анна",
        branchId: "22222222-2222-4222-8222-222222222222",
        discipline: "Вокал",
        quick: "active",
        openTasks: true,
        limit: 10,
      } as never),
    ).resolves.toEqual({
      columns: [
        expect.objectContaining({
          id: "status-a",
          name: "Новый",
          totalCount: 2,
          items: [
            expect.objectContaining({
              id: "11111111-1111-4111-8111-111111111111",
              assignedName: "Мария Менеджер",
              branchName: "Центр",
              linkedStudentId: "student-a",
              openTasksCount: 2,
              commentsCount: 3,
              trialLessonsCount: 1,
            }),
          ],
        }),
      ],
      totalCount: 2,
      nextCursor:
        "2026-06-12T00:00:00.000Z|11111111-1111-4111-8111-111111111111",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(3);
    expect(query.mock.calls[2][1]).toContain("анна");
    expect(query.mock.calls[2][1]).toContain("Вокал");
    expect(query.mock.calls[2][1]).toContain(10);
  });

  it("hides converted leads from the board when hideConverted is set", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // statuses
      { rows: [] }, // counts
      { rows: [] }, // leads
    ]);
    await service.listLeadBoard(actor, { hideConverted: true } as never);
    expect(query.mock.calls[1][0]).toContain("from app.students");
    expect(query.mock.calls[1][0]).toContain("linked_conv.lead_id = l.id");
    expect(query.mock.calls[1][0]).toContain(
      "p_conv.phone_normalized = l.phone_normalized",
    );
    expect(query.mock.calls[2][0]).toContain("not exists");
  });

  it("does not add the converted filter by default", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);
    await service.listLeadBoard(actor, {} as never);
    expect(query.mock.calls[2][0]).not.toContain("linked_conv.lead_id = l.id");
  });

  it("lead board branch filter prefers the branch_id column", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);
    await service.listLeadBoard(actor, { branchId: "b-1" } as never);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("l.branch_id::text");
  });

  it("returns lead card aggregate with linked records and timeline", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lead-a",
            status_id: "status-a",
            status_name: "Новый",
            status_color: "#C5A059",
            status_sort_order: 1,
            first_name: "Анна",
            last_name: "Иванова",
            phone: "+79990000000",
            email: "anna@example.com",
            source: "site",
            notes: null,
            assigned_to: "manager-a",
            assigned_first_name: "Мария",
            assigned_last_name: "Менеджер",
            branch_id: "branch-a",
            branch_name: "Центр",
            linked_student_id: "student-a",
            open_tasks_count: "1",
            comments_count: "1",
            trial_lessons_count: "1",
            custom_data: { discipline: "Вокал" },
            created_by: "manager-a",
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            profile_id: "profile-a",
            profile_user_id: "client-a",
            lead_id: "lead-a",
            custom_data: {},
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: "+79990000000",
            created_at: "2026-06-12T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      { rows: [] },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "lead",
            entity_id: "lead-a",
            author_id: "manager-a",
            author_first_name: "Мария",
            author_last_name: "Менеджер",
            body: "Позвонить",
            created_at: "2026-06-12T10:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          {
            id: "task-a",
            entity_type: "lead",
            entity_id: "lead-a",
            assigned_to: "manager-a",
            assigned_first_name: "Мария",
            assigned_last_name: "Менеджер",
            entity_first_name: null,
            entity_last_name: null,
            entity_name: null,
            title: "Перезвонить",
            description: null,
            status: "open",
            due_at: null,
            created_by: "manager-a",
            created_at: "2026-06-12T09:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          {
            id: "lesson-a",
            student_id: null,
            group_id: null,
            lead_id: "lead-a",
            teacher_id: "teacher-a",
            branch_id: "branch-a",
            room_id: "room-a",
            scheduled_at: "2026-06-15T09:00:00.000Z",
            duration_minutes: 60,
            status: "scheduled",
            is_trial: true,
            notes: null,
            student_user_id: null,
            teacher_user_id: "teacher-user-a",
            student_name: null,
            teacher_name: "Иван Петров",
            branch_name: "Центр",
            room_name: "101",
            group_name: null,
            group_price_per_lesson: null,
          },
        ],
      },
      { rows: [] },
    ]);

    await expect(service.getLeadCard(actor, "lead-a")).resolves.toEqual(
      expect.objectContaining({
        lead: expect.objectContaining({
          id: "lead-a",
          assignedName: "Мария Менеджер",
          openTasksCount: 1,
        }),
        linkedStudents: [
          expect.objectContaining({ id: "student-a", firstName: "Анна" }),
        ],
        comments: [expect.objectContaining({ body: "Позвонить" })],
        tasks: [expect.objectContaining({ title: "Перезвонить" })],
        trials: [expect.objectContaining({ teacherName: "Иван Петров" })],
        timeline: expect.arrayContaining([
          expect.objectContaining({ type: "comment" }),
          expect.objectContaining({ type: "task" }),
          expect.objectContaining({ type: "trial" }),
        ]),
      }),
    );

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query).toHaveBeenCalledTimes(7);
  });

  it("lists a lead's status history newest-first", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "h1",
            old_status: "Новый",
            new_status: "Пробный Урок",
            old_owner_id: null,
            new_owner_id: "u1",
            changed_by: "u1",
            changed_at: "2026-06-19T00:00:00.000Z",
            reason_id: null,
            comment: null,
          },
        ],
      },
    ]);
    const result = await service.listLeadStatusHistory(actor, "lead-1");
    expect(result.items[0]).toEqual({
      id: "h1",
      oldStatus: "Новый",
      newStatus: "Пробный Урок",
      oldOwnerId: null,
      newOwnerId: "u1",
      changedBy: "u1",
      changedAt: "2026-06-19T00:00:00.000Z",
      reasonId: null,
      comment: null,
    });
    expect(result.items).toHaveLength(1);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_status_history");
    expect(query.mock.calls[0][1]).toEqual(["lead-1"]);
  });

  it("lists a lead's applications newest-first (KVA-234)", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "app-1",
            applied_at: "2026-06-20T10:00:00.000Z",
            channel: "Заявка с сайта",
            office: "Сокол",
            discipline: "Вокал",
            status: "Новая",
            utm: { Source: "yandex", Medium: "cpc", Campaign: "brand", Referrer: null },
          },
        ],
      },
    ]);
    const result = await service.listLeadApplications(actor, "lead-1");
    expect(result.items).toEqual([
      {
        id: "app-1",
        appliedAt: "2026-06-20T10:00:00.000Z",
        channel: "Заявка с сайта",
        office: "Сокол",
        discipline: "Вокал",
        status: "Новая",
        utm: { Source: "yandex", Medium: "cpc", Campaign: "brand", Referrer: null },
      },
    ]);
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("app.lead_applications");
    expect(query.mock.calls[0][0]).toContain("order by applied_at desc");
    expect(query.mock.calls[0][1]).toEqual(["lead-1"]);
  });

  it("clears a lead's status when clearStatus is set (move to Без статуса)", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "s0", assigned_to: "o0", branch_id: "b0" }] },
      { rows: [{ id: "lead-1", status_id: null, assigned_to: "o0", source: "site", custom_data: {} }] },
    ]);
    await service.updateLead(actor, "lead-1", { clearStatus: true } as never);
    const sql = query.mock.calls[1][0] as string;
    expect(sql).toContain("when $11::boolean then null");
    expect((query.mock.calls[1][1] as unknown[])[10]).toBe(true);
  });

  it("preserves a lead's status when clearStatus is not set", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "status-a", assigned_to: "o0", branch_id: "b0" }] },
      { rows: [{ id: "lead-1", status_id: "status-a", assigned_to: "o0", source: "site", custom_data: {} }] },
    ]);
    await service.updateLead(actor, "lead-1", {
      statusId: "11111111-1111-1111-1111-111111111111",
    } as never);
    expect((query.mock.calls[1][1] as unknown[])[10]).toBe(false);
  });

  it("records a lead_status_history row when status changes", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "old-status", assigned_to: "owner-1", branch_id: "branch-1" }] },
      { rows: [{ id: "lead-1", status_id: "new-status", assigned_to: "owner-1", source: "site", custom_data: {} }] },
      { rows: [] },
    ]);
    await service.updateLead(actor, "lead-1", { statusId: "new-status" } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.lead_status_history"));
    expect(insert).toBeDefined();
    const params = query.mock.calls.find((c) => String(c[0]).includes("insert into app.lead_status_history"))?.[1] as unknown[];
    expect(params).toEqual([
      "lead-1", "old-status", "new-status", "owner-1", "owner-1",
      actor.userId, null, null, "branch-1", "site",
    ]);
  });

  it("does NOT record lead_status_history when neither status nor owner changed", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "s1", assigned_to: "o1", branch_id: "b1" }] },
      { rows: [{ id: "lead-1", status_id: "s1", assigned_to: "o1", source: "site", custom_data: {} }] },
    ]);
    await service.updateLead(actor, "lead-1", { firstName: "X" } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.lead_status_history"));
    expect(insert).toBeUndefined();
  });

  it("dual-writes branch_id column when customDataPatch carries a branchId", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ id: "lead-1" }] },
    ]);
    await service.createLead(actor, {
      firstName: "A",
      customDataPatch: { branchId: "44444444-4444-4444-4444-444444444444" },
    } as never);
    const insert = query.mock.calls.map((c) => String(c[0])).find((s) => s.includes("insert into app.leads"));
    expect(insert).toContain("branch_id");
    const params = query.mock.calls.find((c) => String(c[0]).includes("insert into app.leads"))?.[1] as unknown[];
    expect(params).toContain("44444444-4444-4444-4444-444444444444");
  });

  it("soft deletes leads through CRM write policy", async () => {
    const { service, query, audit, policy } = createService([{ id: "lead-a" }]);

    await expect(service.deleteLead(actor, "lead-a")).resolves.toEqual({
      success: true,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["lead-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lead_deleted",
        entityType: "lead",
        entityId: "lead-a",
      }),
    );
  });

  describe("new lead notifications (KVA-240)", () => {
    it("createLead notifies staff about the new lead", async () => {
      const { service, notifications } = createServiceWithQueryResults([
        {
          rows: [
            { id: "lead-1", first_name: "Иван", last_name: "Петров", source: "site" },
          ],
        },
      ]);
      await service.createLead(actor, { firstName: "Иван" } as never);
      expect(notifications.notifyNewLead).toHaveBeenCalledWith({
        leadId: "lead-1",
        name: "Иван Петров",
        source: "site",
      });
    });

    it("createLead succeeds even when the notification fails", async () => {
      const { service, notifications } = createServiceWithQueryResults([
        { rows: [{ id: "lead-1", first_name: "Иван" }] },
      ]);
      notifications.notifyNewLead.mockRejectedValueOnce(new Error("boom"));
      await expect(
        service.createLead(actor, { firstName: "Иван" } as never),
      ).resolves.toMatchObject({ id: "lead-1" });
      expect(notifications.notifyNewLead).toHaveBeenCalledTimes(1);
    });

  });
});
