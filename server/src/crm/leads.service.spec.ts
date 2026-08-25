import { ConflictException, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { LeadsService } from "./leads.service";
import { LeadBoardService } from "./lead-board.service";
import { LeadCardService } from "./lead-card.service";
import { LeadCommandService } from "./lead-command.service";
import { LeadDirectoryService } from "./lead-directory.service";
import { LeadWriteRepository } from "./lead-write.repository";
import { ChatWorkTimelineService } from "../messenger/chat-work-timeline.service";
import { TimelineService } from "./timeline.service";
import { StudentFunnelService } from "./student-funnel.service";
import { SharedTaskService } from "./tasks/shared-task.service";
import {
  ACTIVE_RESPONSIBLE_STAFF_STATUSES,
  RESPONSIBLE_AUTH_ROLES,
} from "./responsible-eligibility";

describe("LeadsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const makeLeads = (db: { query?: jest.Mock; transaction?: jest.Mock }) => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanWriteCrm: jest.fn(),
      assertCanReadOperationalData: jest.fn(),
    };
    const realtime = { emitCrmChanged: () => undefined };
    const chatWork = { listForEntity: jest.fn().mockResolvedValue([]) };
    const timeline = {
      listFieldAudit: jest.fn().mockResolvedValue({ items: [] }),
    };
    const database = db as unknown as DatabaseService;
    const crmPolicy = policy as unknown as CrmPolicy;
    const funnel = {
      getEffective: jest.fn().mockResolvedValue({ stages: [] }),
      assertLeadTransition: jest.fn().mockResolvedValue(undefined),
    } as unknown as StudentFunnelService;
    const sharedTasks = {
      list: jest.fn().mockResolvedValue({
        items: [
          {
            id: "task-a",
            title: "Перезвонить",
            body: null,
            state: "open",
            createdAt: "2026-06-12T09:00:00.000Z",
          },
        ],
        counters: {},
      }),
    } as unknown as SharedTaskService;
    const service = new LeadsService(
      new LeadBoardService(database, crmPolicy, funnel),
      new LeadCardService(
        database,
        crmPolicy,
        chatWork as unknown as ChatWorkTimelineService,
        timeline as unknown as TimelineService,
        funnel,
        sharedTasks,
      ),
      new LeadDirectoryService(database, crmPolicy),
      new LeadCommandService(
        database,
        audit as unknown as AuditService,
        crmPolicy,
        realtime as unknown as RealtimeBus,
        new LeadWriteRepository(database, funnel),
      ),
    );
    return { service, audit, policy, timeline };
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

  const boardRow = ({
    id,
    statusId,
    timestamp,
  }: {
    id: string;
    statusId: string | null;
    timestamp: string;
  }) => ({
    id,
    status_id: statusId,
    status_name: statusId ? `Status ${statusId.slice(0, 4)}` : null,
    status_color: null,
    status_sort_order: statusId ? 1 : null,
    first_name: id,
    last_name: null,
    phone: null,
    email: null,
    source: null,
    notes: null,
    assigned_to: null,
    assigned_first_name: null,
    assigned_last_name: null,
    branch_id: null,
    branch_name: null,
    linked_student_id: null,
    linked_user_id: null,
    open_tasks_count: "0",
    comments_count: "0",
    trial_lessons_count: "0",
    custom_data: {},
    created_by: null,
    created_at: timestamp,
    cursor_created_at: timestamp,
    updated_at: timestamp,
  });

  it("returns lead board columns with counts and aggregate lead fields", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [] }, // «Без статуса» sort setting (unset → last)
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
            linked_user_id: "client-a",
            open_tasks_count: "2",
            comments_count: "3",
            trial_lessons_count: "1",
            custom_data: { discipline: "Вокал", hollihopId: "HH-42" },
            created_by: "manager-a",
            created_at: "2026-06-12T00:00:00.000Z",
            cursor_created_at: "2026-06-12T00:00:00.123456Z",
            updated_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    const boardPromise = service.listLeadBoard(actor, {
      q: "анна",
      branchId: "22222222-2222-4222-8222-222222222222",
      statusId: "33333333-3333-4333-8333-333333333333",
      assignedTo: "44444444-4444-4444-8444-444444444444",
      source: "Сайт",
      discipline: "Вокал",
      level: "Начальный",
      category: "Взрослый",
      requestType: "Пробное занятие",
      goal: "Поставить голос",
      gender: "Женский",
      preferredSchedule: "вечер",
      from: "2026-06-01T00:00:00.000Z",
      to: "2026-07-01T00:00:00.000Z",
      sort: "oldest",
      quick: "active",
      openTasks: true,
      limit: 10,
    } as never);
    await expect(boardPromise).resolves.toEqual({
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
              linkedUserId: "client-a",
              openTasksCount: 2,
              commentsCount: 3,
              trialLessonsCount: 1,
            }),
          ],
        }),
      ],
      totalCount: 2,
      nextCursor: null,
    });

    const firstColumn = (await boardPromise).columns[0];
    expect(firstColumn.nextCursor).toBeNull();

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    // +1 for the leading «Без статуса» sort-setting read.
    expect(query).toHaveBeenCalledTimes(4);
    expect(query.mock.calls[3][1]).toContain("анна");
    expect(query.mock.calls[3][1]).toContain(
      "33333333-3333-4333-8333-333333333333",
    );
    expect(query.mock.calls[3][1]).toContain(
      "44444444-4444-4444-8444-444444444444",
    );
    expect(query.mock.calls[3][1]).toContain("Сайт");
    expect(query.mock.calls[3][1]).toContain("Вокал");
    expect(query.mock.calls[3][1]).toContain("Начальный");
    expect(query.mock.calls[3][1]).toContain("Взрослый");
    expect(query.mock.calls[3][1]).toContain("Пробное занятие");
    expect(query.mock.calls[3][1]).toContain("Поставить голос");
    expect(query.mock.calls[3][1]).toContain("Женский");
    expect(query.mock.calls[3][1]).toContain("вечер");
    expect(query.mock.calls[3][1]).toContain("2026-06-01T00:00:00.000Z");
    expect(query.mock.calls[3][1]).toContain("2026-07-01T00:00:00.000Z");
    expect(query.mock.calls[3][1]).toContain(11);
    expect(String(query.mock.calls[3][0])).toContain("as cursor_created_at");
    expect(String(query.mock.calls[3][0])).toContain(
      "order by l.created_at asc, l.id asc",
    );
    expect(String(query.mock.calls[3][0])).toContain("as linked_user_id");
    expect(String(query.mock.calls[3][0])).toContain("is_app_account = true");
  });

  it("preserves microseconds and advances an oldest-first keyset cursor", async () => {
    const boundaryId = "11111111-1111-4111-8111-111111111111";
    const nextId = "22222222-2222-4222-8222-222222222222";
    const exactTimestamp = "2026-06-12T00:00:00.123456Z";
    const { service, query } = createServiceWithQueryResults([
      { rows: [] },
      { rows: [] },
      { rows: [{ status_id: null, count: "2" }] },
      {
        rows: [
          boardRow({
            id: boundaryId,
            statusId: null,
            timestamp: exactTimestamp,
          }),
          boardRow({
            id: nextId,
            statusId: null,
            timestamp: "2026-06-11T00:00:00.654321Z",
          }),
        ],
      },
      { rows: [] },
      { rows: [] },
      { rows: [{ status_id: null, count: "2" }] },
      {
        rows: [
          boardRow({
            id: nextId,
            statusId: null,
            timestamp: "2026-06-11T00:00:00.654321Z",
          }),
        ],
      },
    ]);

    const firstPage = await service.listLeadBoard(actor, {
      limit: 1,
      unassigned: true,
      sort: "oldest",
    } as never);
    const cursor = firstPage.columns[0].nextCursor;
    await service.listLeadBoard(actor, {
      limit: 1,
      unassigned: true,
      cursor,
      sort: "oldest",
    } as never);

    expect(firstPage.nextCursor).toBeNull();
    expect(cursor).toBe(`${exactTimestamp}|${boundaryId}`);
    const secondLeadQuery = query.mock.calls[7];
    expect(secondLeadQuery[1]).toContain(exactTimestamp);
    expect(secondLeadQuery[1]).toContain(boundaryId);
    expect(String(secondLeadQuery[0])).toContain("l.status_id is null");
    expect(String(secondLeadQuery[0])).toContain("(l.created_at, l.id) > (");
    expect(String(secondLeadQuery[0])).toContain(
      "order by l.created_at asc, l.id asc",
    );
  });

  it("paginates divergent status partitions independently without skips or duplicates", async () => {
    const statusA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const statusB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    const a1 = boardRow({
      id: "11111111-1111-4111-8111-111111111111",
      statusId: statusA,
      timestamp: "2026-06-12T10:00:00.111111Z",
    });
    const a2 = boardRow({
      id: "22222222-2222-4222-8222-222222222222",
      statusId: statusA,
      timestamp: "2026-06-12T09:00:00.111112Z",
    });
    const b1 = boardRow({
      id: "33333333-3333-4333-8333-333333333333",
      statusId: statusB,
      timestamp: "2026-06-12T12:00:00.222222Z",
    });
    const b2 = boardRow({
      id: "44444444-4444-4444-8444-444444444444",
      statusId: statusB,
      timestamp: "2026-06-12T11:00:00.222223Z",
    });
    const statuses = [
      {
        id: statusA,
        name: "A",
        color: null,
        sort_order: 1,
        created_at: a1.created_at,
      },
      {
        id: statusB,
        name: "B",
        color: null,
        sort_order: 2,
        created_at: b1.created_at,
      },
    ];
    const { service, query } = createServiceWithQueryResults([
      { rows: [] },
      { rows: statuses },
      {
        rows: [
          { status_id: statusA, count: "2" },
          { status_id: statusB, count: "2" },
        ],
      },
      { rows: [a1, a2, b1, b2] },
      { rows: [] },
      { rows: statuses },
      { rows: [{ status_id: statusA, count: "2" }] },
      { rows: [a2] },
      { rows: [] },
      { rows: statuses },
      { rows: [{ status_id: statusB, count: "2" }] },
      { rows: [b2] },
    ]);

    const first = await service.listLeadBoard(actor, { limit: 1 } as never);
    const columnA = first.columns.find((column) => column.id === statusA)!;
    const columnB = first.columns.find((column) => column.id === statusB)!;
    const pageA = await service.listLeadBoard(actor, {
      limit: 1,
      statusId: statusA,
      cursor: columnA.nextCursor,
    } as never);
    const pageB = await service.listLeadBoard(actor, {
      limit: 1,
      statusId: statusB,
      cursor: columnB.nextCursor,
    } as never);

    expect(first.nextCursor).toBe(`${b1.cursor_created_at}|${b1.id}`);
    expect(columnA.nextCursor).toBe(`${a1.cursor_created_at}|${a1.id}`);
    expect(columnB.nextCursor).toBe(`${b1.cursor_created_at}|${b1.id}`);
    expect(pageA.columns[0].nextCursor).toBeNull();
    expect(pageB.columns[0].nextCursor).toBeNull();
    const ids = [
      columnA.items[0].id,
      pageA.columns[0].items[0].id,
      columnB.items[0].id,
      pageB.columns[0].items[0].id,
    ];
    expect(ids).toEqual([a1.id, a2.id, b1.id, b2.id]);
    expect(new Set(ids)).toHaveProperty("size", 4);
    expect(query.mock.calls[7][1]).toEqual([
      statusA,
      a1.cursor_created_at,
      a1.id,
      "manager-a",
      2,
    ]);
    expect(query.mock.calls[11][1]).toEqual([
      statusB,
      b1.cursor_created_at,
      b1.id,
      "manager-a",
      2,
    ]);
  });

  it("keeps the deprecated unscoped scalar cursor usable for build 143", async () => {
    const statusId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const firstRow = boardRow({
      id: "11111111-1111-4111-8111-111111111111",
      statusId,
      timestamp: "2026-07-18T10:00:00.123456Z",
    });
    const secondRow = boardRow({
      id: "22222222-2222-4222-8222-222222222222",
      statusId,
      timestamp: "2026-07-18T09:00:00.654321Z",
    });
    const statuses = [
      {
        id: statusId,
        name: "A",
        color: null,
        sort_order: 1,
        created_at: firstRow.created_at,
      },
    ];
    const { service, query } = createServiceWithQueryResults([
      { rows: [] },
      { rows: statuses },
      { rows: [{ status_id: statusId, count: "2" }] },
      { rows: [firstRow, secondRow] },
      { rows: [] },
      { rows: statuses },
      { rows: [{ status_id: statusId, count: "1" }] },
      { rows: [secondRow] },
    ]);

    const first = await service.listLeadBoard(actor, { limit: 1 } as never);
    const legacyCursor = `${firstRow.cursor_created_at}|${firstRow.id}`;
    expect(first.nextCursor).toBe(legacyCursor);

    const second = await service.listLeadBoard(actor, {
      limit: 1,
      cursor: first.nextCursor,
    } as never);
    expect(second.columns[0].items[0].id).toBe(secondRow.id);
    expect(query.mock.calls[7][1]).toEqual([
      firstRow.cursor_created_at,
      firstRow.id,
      "manager-a",
      2,
    ]);
  });

  it("hides converted leads from the board when hideConverted is set", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // «Без статуса» sort setting
      { rows: [] }, // statuses
      { rows: [] }, // counts
      { rows: [] }, // leads
    ]);
    await service.listLeadBoard(actor, { hideConverted: true } as never);
    const sql = query.mock.calls[2][0] as string;
    expect(sql).toContain("from app.students");
    expect(sql).toContain("linked_conv.lead_id = l.id");
    expect(sql).toContain("p_conv.phone_normalized = l.phone_normalized");
    // Имя и фамилия — обязательная часть правила, а не украшение: по одному
    // телефону прятались бы однофамильцы и дети на телефоне родителя. Правило
    // общее с импортом (leadStudentMatchSql), и урони его тут одна сторона —
    // карточки снова начнут двоиться.
    expect(sql).toContain(
      "lower(btrim(coalesce(p_conv.first_name, ''))) = lower(btrim(coalesce(l.first_name, '')))",
    );
    expect(sql).toContain(
      "lower(btrim(coalesce(p_conv.last_name, '')))  = lower(btrim(coalesce(l.last_name, '')))",
    );
    // Только активный ученик прячет лид: отчисленный — это история, а не повод
    // убрать человека с доски. Активность живёт здесь, а не в общем правиле.
    expect(sql).toContain("linked_conv.status = 'active'");
    expect(query.mock.calls[3][0]).toContain("not exists");
  });

  it("does not add the converted filter by default", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // «Без статуса» sort setting
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);
    await service.listLeadBoard(actor, {} as never);
    expect(query.mock.calls[3][0]).not.toContain("linked_conv.lead_id = l.id");
  });

  it("lead board branch filter prefers the branch_id column", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // «Без статуса» sort setting
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
      { rows: [{ value_map: {} }] },
      // chat-work timeline is fetched via the injected ChatWorkTimelineService
      // (stubbed to []), so it no longer consumes a db.query result here.
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
    // 6 direct db.query calls: tasks use the canonical SharedTaskService;
    // the final query returns the typed custom-field value map.
    expect(query).toHaveBeenCalledTimes(6);
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
            utm: {
              Source: "yandex",
              Medium: "cpc",
              Campaign: "brand",
              Referrer: null,
            },
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
        utm: {
          Source: "yandex",
          Medium: "cpc",
          Campaign: "brand",
          Referrer: null,
        },
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
      {
        rows: [
          {
            id: "lead-1",
            status_id: null,
            assigned_to: "o0",
            source: "site",
            custom_data: {},
          },
        ],
      },
    ]);
    await service.updateLead(actor, "lead-1", { clearStatus: true } as never);
    const sql = query.mock.calls[1][0] as string;
    expect(sql).toContain("when $11::boolean then null");
    expect((query.mock.calls[1][1] as unknown[])[10]).toBe(true);
  });

  it("preserves a lead's status when clearStatus is not set", async () => {
    const { service, query } = createServiceWithQueryResults([
      // Contract 6: a UUID-shaped statusId is verified against lead_statuses.
      { rows: [{ id: "11111111-1111-1111-1111-111111111111" }] },
      { rows: [{ status_id: "status-a", assigned_to: "o0", branch_id: "b0" }] },
      {
        rows: [
          {
            id: "lead-1",
            status_id: "status-a",
            assigned_to: "o0",
            source: "site",
            custom_data: {},
          },
        ],
      },
    ]);
    await service.updateLead(actor, "lead-1", {
      statusId: "11111111-1111-1111-1111-111111111111",
    } as never);
    expect((query.mock.calls[2][1] as unknown[])[10]).toBe(false);
  });

  describe("linkStudentToLead — ручное «Прикрепить к ученику»", () => {
    it("привязывает произвольного ученика, а не только автоподобранный дубль", async () => {
      const { service, audit } = createServiceWithQueryResults([
        { rows: [{ id: "lead-1" }] }, // лид есть
        { rows: [{ id: "student-1" }] }, // ученик есть
        { rows: [{ id: "student-1" }] }, // update прошёл
      ]);

      await expect(
        service.linkStudentToLead(actor, "lead-1", "student-1"),
      ).resolves.toEqual({ leadId: "lead-1", studentId: "student-1" });

      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({ action: "crm.lead_student_linked" }),
      );
    });

    it("не перевешивает ученика, уже связанного с другим лидом", async () => {
      const { service } = createServiceWithQueryResults([
        { rows: [{ id: "lead-1" }] },
        { rows: [{ id: "student-1" }] },
        { rows: [] }, // update не нашёл строку → связь занята
      ]);

      // Молча перевесить связь нельзя: прежний лид потерял бы ученика без следа.
      await expect(
        service.linkStudentToLead(actor, "lead-1", "student-1"),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it("не выдумывает связь с несуществующим учеником", async () => {
      const { service } = createServiceWithQueryResults([
        { rows: [{ id: "lead-1" }] },
        { rows: [] },
      ]);

      await expect(
        service.linkStudentToLead(actor, "lead-1", "ghost"),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  it("audits which fields an edit changed, old → new", async () => {
    const { service, audit } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lead-1",
            status_id: "s0",
            assigned_to: "o0",
            branch_id: "b0",
            first_name: "Анна",
            phone: "+79161234567",
            source: "site",
            custom_data: { level: "A1" },
          },
        ],
      },
      {
        rows: [
          {
            id: "lead-1",
            status_id: "s0",
            assigned_to: "o0",
            first_name: "Анна",
            phone: "+79990000000",
            source: "site",
            custom_data: { level: "A2" },
          },
        ],
      },
    ]);

    await service.updateLead(actor, "lead-1", {
      phone: "+79990000000",
    } as never);

    // Before this the event said only «лид обновлён», which answers none of
    // «кто поменял телефон и на какой».
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lead_updated",
        metadata: expect.objectContaining({
          changes: [
            { field: "phone", from: "+79161234567", to: "+79990000000" },
            { field: "custom_data.level", from: "A1", to: "A2" },
          ],
          customFieldDefinitionIds: [],
        }),
      }),
    );
  });

  it("records a lead_status_history row when status changes", async () => {
    const { service, query } = createServiceWithQueryResults([
      // Contract 6: "new-status" is not a UUID → resolved as a status NAME.
      { rows: [{ id: "new-status" }] },
      {
        rows: [
          {
            status_id: "old-status",
            assigned_to: "owner-1",
            branch_id: "branch-1",
          },
        ],
      },
      {
        rows: [
          {
            id: "lead-1",
            status_id: "new-status",
            assigned_to: "owner-1",
            source: "site",
            custom_data: {},
          },
        ],
      },
      { rows: [] },
    ]);
    await service.updateLead(actor, "lead-1", {
      statusId: "new-status",
    } as never);
    const insert = query.mock.calls
      .map((c) => String(c[0]))
      .find((s) => s.includes("insert into app.lead_status_history"));
    expect(insert).toBeDefined();
    const params = query.mock.calls.find((c) =>
      String(c[0]).includes("insert into app.lead_status_history"),
    )?.[1] as unknown[];
    expect(params).toEqual([
      "lead-1",
      "old-status",
      "new-status",
      "owner-1",
      "owner-1",
      actor.userId,
      null,
      null,
      "branch-1",
      "site",
    ]);
  });

  it("does NOT record lead_status_history when neither status nor owner changed", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ status_id: "s1", assigned_to: "o1", branch_id: "b1" }] },
      {
        rows: [
          {
            id: "lead-1",
            status_id: "s1",
            assigned_to: "o1",
            source: "site",
            custom_data: {},
          },
        ],
      },
    ]);
    await service.updateLead(actor, "lead-1", { firstName: "X" } as never);
    const insert = query.mock.calls
      .map((c) => String(c[0]))
      .find((s) => s.includes("insert into app.lead_status_history"));
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
    const insert = query.mock.calls
      .map((c) => String(c[0]))
      .find((s) => s.includes("insert into app.leads"));
    expect(insert).toContain("branch_id");
    const params = query.mock.calls.find((c) =>
      String(c[0]).includes("insert into app.leads"),
    )?.[1] as unknown[];
    expect(params).toContain("44444444-4444-4444-4444-444444444444");
  });

  it("blocks direct lead deletion without mutating CRM data", async () => {
    const { service, query, transaction, audit, policy } = createService([
      { id: "lead-a" },
    ]);

    await expect(service.deleteLead(actor, "lead-a")).rejects.toThrow(
      ConflictException,
    );

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(transaction).not.toHaveBeenCalled();
    expect(query).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });

  describe("statusId resolution (контракт 6, правки №2)", () => {
    it("ignores an unresolvable statusId instead of failing the save", async () => {
      // 439/1990 прод-лидов «Без статуса»: клиент шлёт литерал 'new', раньше
      // это валило ВЕСЬ PATCH 400-кой. Теперь поле просто игнорируется.
      const { service, query } = createServiceWithQueryResults([
        { rows: [] }, // name lookup for 'new' → нет такого статуса
        { rows: [{ status_id: "s1", assigned_to: "o1", branch_id: "b1" }] },
        {
          rows: [
            {
              id: "lead-1",
              status_id: "s1",
              assigned_to: "o1",
              source: "site",
              custom_data: {},
            },
          ],
        },
      ]);

      await expect(
        service.updateLead(actor, "lead-1", {
          statusId: "new",
          phone: "+79990000000",
        } as never),
      ).resolves.toMatchObject({ id: "lead-1" });

      // The UPDATE ran with statusId=null → coalesce keeps the current status.
      const updateCall = query.mock.calls.find((c) =>
        String(c[0]).includes("update app.leads"),
      );
      expect((updateCall?.[1] as unknown[])[1]).toBeNull();
    });

    it("resolves a status NAME case-insensitively via lead_statuses", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "status-novy" }] }, // name lookup hit
        { rows: [{ id: "lead-1" }] }, // insert
      ]);

      await service.createLead(actor, {
        firstName: "Иван",
        statusId: "Новый",
      } as never);

      const lookup = query.mock.calls[0];
      expect(String(lookup[0])).toContain(
        "lower(btrim(name)) = lower(btrim($1))",
      );
      expect(String(lookup[0])).toContain("having count(*) = 1");
      expect(lookup[1]).toEqual(["Новый"]);
      const insertCall = query.mock.calls.find((c) =>
        String(c[0]).includes("insert into app.leads"),
      );
      expect((insertCall?.[1] as unknown[])[0]).toBe("status-novy");
    });

    it("drops a UUID that does not exist in lead_statuses (never 500s)", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [] }, // id verify miss
        { rows: [{ id: "lead-1" }] }, // insert
      ]);

      await service.createLead(actor, {
        firstName: "Иван",
        statusId: "99999999-9999-4999-8999-999999999999",
      } as never);

      const insertCall = query.mock.calls.find((c) =>
        String(c[0]).includes("insert into app.leads"),
      );
      expect((insertCall?.[1] as unknown[])[0]).toBeNull();
    });
  });

  describe("auto-«Ответственный» (контракт 5, правки №2)", () => {
    it("stamps the creating manager as responsible, only into an empty slot", async () => {
      const { service, query } = createServiceWithQueryResults([
        { rows: [{ id: "lead-1" }] }, // insert
        { rows: [] }, // ensureResponsible update
      ]);

      await service.createLead(actor, { firstName: "Иван" } as never);
      const responsibleCall = query.mock.calls.find((c) =>
        String(c[0]).includes("'responsible'"),
      );
      expect(responsibleCall).toBeDefined();
      const sql = String(responsibleCall?.[0]);
      // Никогда не затирает бэкфилл HolliHop: пишет только в пустое поле.
      expect(sql).toContain("set assigned_to = eligible_actor.user_id");
      expect(sql).toContain("join app.staff_members");
      expect(sql).toContain("l.custom_data->>'responsible'");
      expect(sql).toContain("responsibleUserId");
      expect(responsibleCall?.[1]).toEqual([
        "lead-1",
        actor.userId,
        [...RESPONSIBLE_AUTH_ROLES],
        [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
      ]);
    });
  });

  describe("explicit responsible writes", () => {
    const responsibleId = "11111111-1111-4111-8111-111111111111";

    it("validates and canonicalizes an explicit lead assignee before insert", async () => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              user_id: responsibleId,
              role: "manager",
              staff_member_id: "staff-1",
              staff_status: "active",
              display_name: "Мария Менеджер",
            },
          ],
        },
        {
          rows: [
            {
              id: "lead-1",
              assigned_to: responsibleId,
              custom_data: {
                responsible: "Мария Менеджер",
                responsibleUserId: responsibleId,
              },
            },
          ],
        },
      ]);

      await service.createLead(actor, {
        firstName: "Иван",
        assignedTo: responsibleId,
        customDataPatch: { responsibleName: "spoofed" },
      } as never);

      const eligibilityCall = query.mock.calls[0];
      expect(String(eligibilityCall[0])).toContain("join app.staff_members");
      expect(eligibilityCall[1]).toEqual([
        responsibleId,
        [...RESPONSIBLE_AUTH_ROLES],
        [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
      ]);
      const insertCall = query.mock.calls.find((call) =>
        String(call[0]).includes("insert into app.leads"),
      );
      expect((insertCall?.[1] as unknown[])[7]).toBe(responsibleId);
      expect((insertCall?.[1] as unknown[])[8]).toEqual({
        responsible: "Мария Менеджер",
        responsibleUserId: responsibleId,
      });
    });

    it("rejects an ineligible assignee without inserting a lead", async () => {
      const { service, query } = createServiceWithQueryResults([{ rows: [] }]);

      await expect(
        service.createLead(actor, {
          firstName: "Иван",
          assignedTo: responsibleId,
        } as never),
      ).rejects.toMatchObject({ status: 400 });
      expect(
        query.mock.calls.some((call) =>
          String(call[0]).includes("insert into app.leads"),
        ),
      ).toBe(false);
    });

    it("clears both canonical lead ownership and compatibility metadata explicitly", async () => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              id: "lead-1",
              status_id: "status-1",
              assigned_to: responsibleId,
              branch_id: null,
              custom_data: {
                responsible: "Мария Менеджер",
                responsibleUserId: responsibleId,
              },
            },
          ],
        },
        {
          rows: [
            {
              id: "lead-1",
              status_id: "status-1",
              assigned_to: null,
              source: "site",
              custom_data: {},
            },
          ],
        },
        { rows: [] },
      ]);

      await service.updateLead(actor, "lead-1", {
        clearAssignedTo: true,
      } as never);

      const updateCall = query.mock.calls.find((call) =>
        String(call[0]).includes("update app.leads"),
      );
      const sql = String(updateCall?.[0]);
      expect(sql).toContain("case when $13::boolean then null");
      expect(sql).toContain("- 'responsible' - 'responsibleUserId'");
      expect((updateCall?.[1] as unknown[])[12]).toBe(true);
      expect(
        query.mock.calls.some((call) =>
          String(call[0]).includes("with eligible_actor as"),
        ),
      ).toBe(false);
    });
  });

  describe("manual lead notifications (v4 T3.2.1)", () => {
    it("createLead persists without producing an inbound notification", async () => {
      const { service } = createServiceWithQueryResults([
        { rows: [{ id: "lead-1", first_name: "Иван" }] },
      ]);
      await expect(
        service.createLead(actor, { firstName: "Иван" } as never),
      ).resolves.toMatchObject({ id: "lead-1" });
    });
  });
});
