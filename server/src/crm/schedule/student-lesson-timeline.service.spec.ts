import type { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import type { StudentLessonTimelineQuery } from "../dto/student-lesson-timeline.query";
import {
  StudentLessonTimelineRepository,
  type StudentLessonTimelineRow,
} from "./student-lesson-timeline.repository";
import { StudentLessonTimelineService } from "./student-lesson-timeline.service";

const STUDENT_ID = "10000000-0000-4000-8000-000000000001";
const PLAN_A_ID = "20000000-0000-4000-8000-000000000001";
const PLAN_B_ID = "20000000-0000-4000-8000-000000000002";
const actor: ActorContext = {
  userId: "30000000-0000-4000-8000-000000000001",
  role: "manager",
};

function row(
  input: Partial<StudentLessonTimelineRow> & Pick<StudentLessonTimelineRow, "id">,
): StudentLessonTimelineRow {
  return {
    version: 1,
    scheduled_at: "2026-09-04T09:00:00.000Z",
    duration_minutes: 60,
    lifecycle_state: "scheduled",
    student_id: STUDENT_ID,
    student_name: "Анна Иванова",
    group_id: null,
    group_name: null,
    teacher_id: "40000000-0000-4000-8000-000000000001",
    teacher_name: "Мария Петрова",
    room_id: "50000000-0000-4000-8000-000000000001",
    room_name: "Класс 1",
    branch_id: "60000000-0000-4000-8000-000000000001",
    branch_name: "Центр",
    origin_kind: "manual",
    plan_id: null,
    series_id: null,
    covered_by_subscription: false,
    settlement_type_key: null,
    predecessor_id: null,
    successor_id: null,
    actionable_lesson_id: input.id,
    ...input,
  };
}

function repositoryMock() {
  return {
    listPage: jest.fn(),
  } as unknown as jest.Mocked<StudentLessonTimelineRepository>;
}

describe("StudentLessonTimelineService", () => {
  afterEach(() => {
    jest.useRealTimers();
  });

  it("returns manual, plan, cancelled, and rescheduled lessons once", async () => {
    const repository = repositoryMock();
    repository.listPage.mockImplementation(async (_actor, _studentId, direction) =>
      direction === "previous"
        ? []
        : [
            row({ id: "manual", origin_kind: "manual" }),
            row({
              id: "plan-a",
              plan_id: PLAN_A_ID,
              series_id: "70000000-0000-4000-8000-000000000001",
              origin_kind: "generated",
            }),
            row({
              id: "plan-b",
              plan_id: PLAN_B_ID,
              series_id: "70000000-0000-4000-8000-000000000002",
              origin_kind: "generated",
              lifecycle_state: "cancelled",
            }),
            row({
              id: "moved-from",
              successor_id: "moved-to",
              lifecycle_state: "rescheduled",
              actionable_lesson_id: "moved-to",
            }),
            row({
              id: "moved-to",
              predecessor_id: "moved-from",
              origin_kind: "one_off_exception",
              actionable_lesson_id: "moved-to",
            }),
          ],
    );
    const service = new StudentLessonTimelineService(repository);

    const page = await service.list(actor, STUDENT_ID, { limit: 24 });

    expect(page.items.map((item) => item.id)).toEqual([
      "manual",
      "plan-a",
      "plan-b",
      "moved-from",
      "moved-to",
    ]);
    expect(page.items.map((item) => item.origin.kind)).toEqual([
      "manual",
      "generated",
      "generated",
      "manual",
      "one_off_exception",
    ]);
    expect(page.items[3].reschedule).toEqual({
      predecessorId: null,
      successorId: "moved-to",
      actionableLessonId: "moved-to",
    });
  });

  it("passes the actor and student scope to both sides of the centered page", async () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-09-04T08:30:00.000Z"));
    const repository = repositoryMock();
    repository.listPage.mockResolvedValue([]);
    const service = new StudentLessonTimelineService(repository);

    await service.list(actor, STUDENT_ID, { limit: 24 });

    const anchor = {
      scheduledAt: "2026-09-04T08:30:00.000Z",
      id: "00000000-0000-0000-0000-000000000000",
    };
    expect(repository.listPage).toHaveBeenNthCalledWith(
      1,
      actor,
      STUDENT_ID,
      "previous",
      anchor,
      24,
    );
    expect(repository.listPage).toHaveBeenNthCalledWith(
      2,
      actor,
      STUDENT_ID,
      "next",
      anchor,
      24,
      true,
    );
  });

  it.each([
    [0, 13, 0, 13],
    [13, 0, 13, 0],
    [3, 30, 3, 21],
    [30, 3, 21, 3],
    [30, 30, 12, 12],
  ])(
    "balances an initial page with %i past and %i future lessons",
    async (past, future, expectedPast, expectedFuture) => {
      const previous = Array.from({ length: past }, (_, index) =>
        row({
          id: `past-${index}`,
          scheduled_at: new Date(
            Date.UTC(2026, 8, 3 - index, 12),
          ).toISOString(),
        }),
      );
      const next = Array.from({ length: future }, (_, index) =>
        row({
          id: `next-${index}`,
          scheduled_at: new Date(
            Date.UTC(2026, 8, 4 + index, 12),
          ).toISOString(),
        }),
      );
      const repository = repositoryMock();
      repository.listPage.mockImplementation(
        async (_actor, _studentId, direction, _cursor, limit) =>
          (direction === "previous" ? previous : next).slice(0, limit + 1),
      );
      const service = new StudentLessonTimelineService(repository);

      const page = await service.list(actor, STUDENT_ID, { limit: 24 });

      expect(page.items.map((item) => item.id)).toEqual([
        ...previous.slice(0, expectedPast).reverse(),
        ...next.slice(0, expectedFuture),
      ].map((item) => item.id));
      expect(page.hasPrevious).toBe(past > expectedPast);
      expect(page.hasNext).toBe(future > expectedFuture);
      expect(page.previousCursor === null).toBe(!page.hasPrevious);
      expect(page.nextCursor === null).toBe(!page.hasNext);
    },
  );

  it("uses a strict composite cursor and restores ascending output for previous pages", async () => {
    const repository = repositoryMock();
    repository.listPage.mockResolvedValue([
      row({
        id: "00000000-0000-4000-8000-000000000003",
        scheduled_at: "2026-09-04T11:00:00.000Z",
      }),
      row({
        id: "00000000-0000-4000-8000-000000000002",
        scheduled_at: "2026-09-04T10:00:00.000Z",
      }),
      row({
        id: "00000000-0000-4000-8000-000000000001",
        scheduled_at: "2026-09-04T09:00:00.000Z",
      }),
    ]);
    const service = new StudentLessonTimelineService(repository);
    const cursor = Buffer.from(
      JSON.stringify({
        scheduledAt: "2026-09-04T12:00:00.000Z",
        id: "00000000-0000-4000-8000-000000000004",
      }),
      "utf8",
    ).toString("base64url");

    const page = await service.list(actor, STUDENT_ID, {
      cursor,
      direction: "previous",
      limit: 2,
    });

    expect(repository.listPage).toHaveBeenCalledWith(
      actor,
      STUDENT_ID,
      "previous",
      {
        scheduledAt: "2026-09-04T12:00:00.000Z",
        id: "00000000-0000-4000-8000-000000000004",
      },
      2,
    );
    expect(page.items.map((item) => item.id)).toEqual([
      "00000000-0000-4000-8000-000000000002",
      "00000000-0000-4000-8000-000000000003",
    ]);
    expect(page).toMatchObject({ hasPrevious: true, hasNext: true });
  });

  it.each([
    "broken",
    Buffer.from("{}", "utf8").toString("base64url"),
    Buffer.from(
      JSON.stringify({ scheduledAt: "not-a-date", id: STUDENT_ID }),
      "utf8",
    ).toString("base64url"),
    Buffer.from(
      JSON.stringify({
        scheduledAt: "2026-02-30T09:00:00.000Z",
        id: STUDENT_ID,
      }),
      "utf8",
    ).toString("base64url"),
    Buffer.from(
      JSON.stringify({
        scheduledAt: "2026-09-04T09:00:00Z",
        id: STUDENT_ID,
      }),
      "utf8",
    ).toString("base64url"),
    Buffer.from(
      JSON.stringify({
        scheduledAt: "2026-09-04T09:00:00.000Z",
        id: "not-a-uuid",
      }),
      "utf8",
    ).toString("base64url"),
  ])("rejects malformed opaque cursor %s with a typed 422", async (cursor) => {
    const repository = repositoryMock();
    const service = new StudentLessonTimelineService(repository);

    await expect(
      service.list(
        actor,
        STUDENT_ID,
        {
          cursor,
          direction: "next" as const,
          limit: 24,
        },
      ),
    ).rejects.toMatchObject({
      status: 422,
      response: { code: "STUDENT_TIMELINE_CURSOR_INVALID" },
    });
    expect(repository.listPage).not.toHaveBeenCalled();
  });

  it("accepts a canonical timestamp on a real leap day", async () => {
    const repository = repositoryMock();
    repository.listPage.mockResolvedValue([]);
    const service = new StudentLessonTimelineService(repository);
    const cursor = Buffer.from(
      JSON.stringify({
        scheduledAt: "2028-02-29T09:00:00.000Z",
        id: STUDENT_ID,
      }),
      "utf8",
    ).toString("base64url");

    await service.list(actor, STUDENT_ID, {
      cursor,
      direction: "next",
      limit: 24,
    });

    expect(repository.listPage).toHaveBeenCalledWith(
      actor,
      STUDENT_ID,
      "next",
      {
        scheduledAt: "2028-02-29T09:00:00.000Z",
        id: STUDENT_ID,
      },
      24,
    );
  });

  it("projects subscription coverage and effective settlement metadata", async () => {
    const repository = repositoryMock();
    repository.listPage.mockImplementation(async (_actor, _studentId, direction) =>
      direction === "previous"
        ? []
        : [
            row({
              id: "covered",
              covered_by_subscription: true,
              settlement_type_key: "completed",
            }),
          ],
    );
    const service = new StudentLessonTimelineService(repository);

    const page = await service.list(
      actor,
      STUDENT_ID,
      { limit: 24 } as StudentLessonTimelineQuery,
    );

    expect(page.items[0].settlement).toEqual({
      coveredBySubscription: true,
      settlementTypeKey: "completed",
    });
  });

  it("returns an empty page without cursors", async () => {
    const repository = repositoryMock();
    repository.listPage.mockResolvedValue([]);
    const service = new StudentLessonTimelineService(repository);

    await expect(
      service.list(actor, STUDENT_ID, { limit: 24 }),
    ).resolves.toEqual({
      items: [],
      previousCursor: null,
      nextCursor: null,
      hasPrevious: false,
      hasNext: false,
    });
  });
});

describe("StudentLessonTimelineRepository scope", () => {
  async function captureSql() {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new StudentLessonTimelineRepository({
      query,
    } as unknown as DatabaseService);

    await repository.listPage(
      actor,
      STUDENT_ID,
      "next",
      {
        scheduledAt: "2026-09-04T09:00:00.000Z",
        id: "00000000-0000-4000-8000-000000000000",
      },
      24,
      true,
    );

    const [sql, params] = query.mock.calls[0] as [string, unknown[]];
    return { sql, normalizedSql: sql.replace(/\s+/g, " "), params };
  }

  it("binds the actor and target student before selecting canonical lesson facts", async () => {
    const { sql, params } = await captureSql();

    expect(sql).toContain("with recursive visible_student as");
    expect(sql).toContain("app.lesson_snapshot_participants");
    expect(sql).toContain("app.lesson_client_charge_facts_effective");
    expect(sql).toContain("app.lesson_reservations");
    expect(sql).toContain("(lesson.scheduled_at, lesson.id) >=");
    expect(sql).toContain("order by lesson.scheduled_at asc, lesson.id asc");
    expect(params.slice(0, 3)).toEqual([actor.role, actor.userId, STUDENT_ID]);
  });

  it("applies teacher and delegated-manager scope to every returned lesson", async () => {
    const { sql, normalizedSql } = await captureSql();

    expect(sql).not.toContain("assigned_lesson");
    expect(sql).toMatch(/\bteacher_profile\.user_id = \$2::uuid/);
    expect(sql).toContain("app.family_members");
    expect(normalizedSql).toContain(
      "coalesce(lesson.branch_id::text, lesson_group.branch_id::text, room.branch_id::text)",
    );
    expect(normalizedSql).toMatch(
      /case when .* then \(.*\) else false end as covered_by_subscription/,
    );
    expect(normalizedSql).toMatch(
      /case when .* then coalesce\(.*\) else null::text end as settlement_type_key/,
    );
  });

  it("selects coverage and settlement for the target participant", async () => {
    const { normalizedSql } = await captureSql();

    expect(normalizedSql).not.toContain(
      "subscription.student_id = visible_student.id",
    );
    expect(normalizedSql).toContain("jsonb_array_elements");
    expect(normalizedSql).toContain(
      "choice.item->>'clientId' = visible_student.id::text",
    );
    expect(normalizedSql).toContain("correction.decision");
    expect(normalizedSql).toContain(
      "case when charge.charge_type is not null then charge.charge_type = 'subscription'",
    );
    expect(normalizedSql).toContain(
      "reservation.subscription_id = target_funding.subscription_id",
    );
    expect(normalizedSql).toContain(
      "participant_decision.item->>'settlementTypeKey'",
    );
  });
});
