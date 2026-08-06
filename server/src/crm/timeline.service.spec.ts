import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { TimelineService } from "./timeline.service";

describe("TimelineService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadStudent: jest.fn(),
      assertCanWriteCrm: jest.fn(),
    };
    const service = new TimelineService(
      { query } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
      audit as unknown as AuditService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
    );
    return { service, query, audit, policy };
  };

  it("returns unified timeline events for a student", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            profile_user_id: "client-a",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            type: "comment",
            title: "Комментарий",
            body: "Позвонить родителю",
            status: null,
            amount: null,
            actor_user_id: "manager-a",
            actor_first_name: "Мария",
            actor_last_name: "Менеджер",
            occurred_at: "2026-06-15T09:00:00.000Z",
          },
          {
            id: "payment-a",
            type: "payment",
            title: "Платеж",
            body: "Абонемент",
            status: "cash",
            amount: "12000.00",
            actor_user_id: "manager-a",
            actor_first_name: "Мария",
            actor_last_name: "Менеджер",
            occurred_at: "2026-06-14T09:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listTimeline(actor, {
        entityType: "student",
        entityId: "student-a",
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        includeAudit: true,
        limit: 40,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "comment-a",
          type: "comment",
          title: "Комментарий",
          body: "Позвонить родителю",
          status: null,
          amount: null,
          actorUserId: "manager-a",
          actorName: "Мария Менеджер",
          occurredAt: "2026-06-15T09:00:00.000Z",
        },
        {
          id: "payment-a",
          type: "payment",
          title: "Платеж",
          body: "Абонемент",
          status: "cash",
          amount: 12000,
          actorUserId: "manager-a",
          actorName: "Мария Менеджер",
          occurredAt: "2026-06-14T09:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(actor, {
      profileUserId: "client-a",
      teacherUserIds: [],
    });
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      true,
      40,
      ["admin_comment", "teacher_note", "progress"],
      false,
      "manager-a",
    ]);
  });

  it("lists progress comments after student ownership check", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "student",
            entity_id: "student-a",
            author_id: "teacher-a",
            author_first_name: "Иван",
            author_last_name: "Петров",
            body: "Хорошая динамика",
            kind: "progress",
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listComments(
        { userId: "client-a", role: "client" },
        {
          entityType: "student",
          entityId: "student-a",
          progressOnly: true,
          limit: 5,
        },
      ),
    ).resolves.toEqual({
      items: [
        {
          id: "comment-a",
          entityType: "student",
          entityId: "student-a",
          authorId: "teacher-a",
          authorName: "Иван Петров",
          body: "Хорошая динамика",
          kind: "progress",
          progress: true,
          lessonAt: null,
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(
      { userId: "client-a", role: "client" },
      { profileUserId: "client-a", teacherUserIds: [] },
    );
    // A client may only ever see the progress stream.
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      ["progress"],
      5,
      false,
      false,
    ]);
  });

  it("limits teachers to teacher_note + progress (never admin comments)", async () => {
    const teacherActor = { userId: "teacher-a", role: "teacher" as const };
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: ["teacher-a"],
          },
        ],
      },
      { rows: [] },
    ]);

    await service.listComments(teacherActor, {
      entityType: "student",
      entityId: "student-a",
      limit: 5,
    });

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(teacherActor, {
      profileUserId: "client-a",
      teacherUserIds: ["teacher-a"],
    });
    // Teacher sees their notes + progress, but NOT admin_comment.
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      ["teacher_note", "progress"],
      5,
      // Комментарии к занятиям не запрашивали — флаг false.
      false,
      // Teacher projection requires the explicit per-comment share flag.
      true,
    ]);
  });

  /**
   * ✔ Требование заказчика: «в разделе комментариев админов показывались как
   * обычные комментарии к клиенту, так и комментарии к определённым занятиям
   * этого клиента».
   *
   * Комментарий живёт на ЗАНЯТИИ (решение заказчика: у группового занятия он
   * один на всех), а в ленте клиента подмешивается — одним запросом, а не
   * походом в базу на каждое занятие.
   */
  it("подмешивает комментарии к занятиям ученика, когда попросили", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            profile_user_id: "client-a",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-lesson",
            entity_type: "lesson",
            entity_id: "lesson-a",
            author_id: null,
            author_first_name: null,
            author_last_name: null,
            body: "миши не будет",
            kind: "admin_comment",
            created_at: "2026-07-11T10:00:00.000Z",
            lesson_at: "2026-07-11T10:00:00.000Z",
          },
        ],
      },
    ]);

    const result = await service.listComments(actor, {
      entityType: "student",
      entityId: "student-a",
      includeLessonComments: true,
      limit: 5,
    });

    // Флаг доехал до запроса — без него подмешивание молча не сработало бы.
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      ["admin_comment", "teacher_note", "progress"],
      5,
      true,
      false,
    ]);
    // Дата занятия доехала до карточки: по ней лента и рисует «к занятию 11.07».
    expect(result.items[0]).toMatchObject({
      entityType: "lesson",
      entityId: "lesson-a",
      lessonAt: "2026-07-11T10:00:00.000Z",
    });
  });

  it("не подмешивает занятия в карточку ЛИДА: занятий у него нет", async () => {
    const { service, query } = createServiceWithQueryResults([{ rows: [] }]);

    await service.listComments(actor, {
      entityType: "lead",
      entityId: "lead-a",
      includeLessonComments: true,
      limit: 5,
    });

    // Флаг попросили, но для лида он бессмысленен — в запрос уходит false.
    expect(query.mock.calls[0][1]?.[4]).toBe(false);
  });

  it("creates comments for CRM writers after checking target entity", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "student",
            entity_id: "student-a",
            author_id: "manager-a",
            author_first_name: null,
            author_last_name: null,
            body: "Позвонить родителю",
            kind: "admin_comment",
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.createComment(actor, {
        entityType: "student",
        entityId: "student-a",
        body: " Позвонить родителю ",
      }),
    ).resolves.toEqual({
      id: "comment-a",
      entityType: "student",
      entityId: "student-a",
      authorId: "manager-a",
      authorName: null,
      body: "Позвонить родителю",
      kind: "admin_comment",
      progress: false,
      lessonAt: null,
      createdAt: "2026-06-12T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    // Default staff comment kind is admin_comment (no [PROGRESS] prefix).
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "manager-a",
      "Позвонить родителю",
      "admin_comment",
      false,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.comment_created",
        entityType: "student",
        entityId: "student-a",
        metadata: { commentId: "comment-a" },
      }),
    );
  });

  it("lets assigned teachers create progress comments for students", async () => {
    const teacherActor = { userId: "teacher-a", role: "teacher" as const };
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: ["teacher-a"],
          },
        ],
      },
      {
        rows: [
          {
            id: "comment-a",
            entity_type: "student",
            entity_id: "student-a",
            author_id: "teacher-a",
            author_first_name: null,
            author_last_name: null,
            body: "Хорошая динамика",
            kind: "progress",
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.createComment(teacherActor, {
        entityType: "student",
        entityId: "student-a",
        body: "Хорошая динамика",
        progress: true,
      }),
    ).resolves.toMatchObject({
      id: "comment-a",
      body: "Хорошая динамика",
      kind: "progress",
    });

    expect(policy.assertCanWriteCrm).not.toHaveBeenCalled();
    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(teacherActor, {
      profileUserId: "client-a",
      teacherUserIds: ["teacher-a"],
    });
    // progress=true resolves to kind='progress'; body stored verbatim.
    expect(query.mock.calls[1][1]).toEqual([
      "student",
      "student-a",
      "teacher-a",
      "Хорошая динамика",
      "progress",
      true,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.comment_created",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  describe("listFieldAudit", () => {
    it("returns readable field changes for staff", async () => {
      const { service, query } = createServiceWithQueryResults([
        {
          rows: [
            {
              id: "audit-1",
              type: "audit",
              title: "crm.lead_updated",
              body: JSON.stringify({
                changes: [
                  { field: "phone", from: "+79161234567", to: "+79990000000" },
                ],
              }),
              status: "lead",
              amount: null,
              actor_user_id: "manager-a",
              actor_first_name: "Мария",
              actor_last_name: "Менеджер",
              occurred_at: "2026-07-16T10:00:00.000Z",
            },
          ],
        },
      ]);

      const result = await service.listFieldAudit(actor, "lead", "lead-1");

      expect(result.items).toEqual([
        expect.objectContaining({
          title: "Правка полей",
          body: "Телефон: +79161234567 → +79990000000",
          actorName: "Мария Менеджер",
        }),
      ]);
      // Only events carrying a diff — a create/delete has no 'changes' key, and
      // jsonb_array_length would throw on a non-array.
      expect(String(query.mock.calls[0][0])).toContain(
        "jsonb_typeof(audit.metadata -> 'changes') = 'array'",
      );
    });

    it("tells a client nothing about who edited their record", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.listFieldAudit(
          { userId: "client-a", role: "client" },
          "student",
          "student-a",
        ),
      ).resolves.toEqual({ items: [] });

      // Returns empty rather than throwing: the card aggregate calls this for
      // every reader, and a 403 would take the whole card down.
      expect(query).not.toHaveBeenCalled();
    });

    it("does not show a teacher who changed a client's phone", async () => {
      const { service, query } = createServiceWithQueryResults([]);

      await expect(
        service.listFieldAudit(
          { userId: "teacher-a", role: "teacher" },
          "student",
          "student-a",
        ),
      ).resolves.toEqual({ items: [] });

      expect(query).not.toHaveBeenCalled();
    });
  });
});
