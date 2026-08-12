import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { GroupLifecycleService } from "./group-lifecycle.service";

describe("GroupLifecycleService", () => {
  const director = { userId: "director-a", role: "director" as const };
  const metadata = {
    idempotencyKey: "group-archive-request-0001",
    requestId: "request-group-archive-0001",
  };

  const row = (overrides: Record<string, unknown> = {}) => ({
    id: "group-a",
    teacher_id: "teacher-a",
    teacher_name: "Мария Петрова",
    teacher_assignment_active: true,
    branch_id: "branch-a",
    branch_name: "Сокол",
    branch_lifecycle_state: "active",
    branch_deleted_at: null,
    timezone_name: "Europe/Moscow",
    room_id: "room-a",
    room_name: "Класс 1",
    room_branch_id: "branch-a",
    room_lifecycle_state: "active",
    room_deleted_at: null,
    name: "Вокальный ансамбль",
    price_per_lesson: 1500,
    teacher_rate: 900,
    lifecycle_state: "active",
    version: 1,
    archived_at: null,
    archive_reason: null,
    archive_effective_date: null,
    active_members: 6,
    membership_history: 8,
    future_lessons: 0,
    active_series: 0,
    active_plans: 0,
    lesson_history: 42,
    completed_lessons: 34,
    ended_series: 2,
    ended_plans: 1,
    ...overrides,
  });

  const createService = (queryRows: Record<string, unknown>[][]) => {
    const query = jest.fn();
    for (const rows of queryRows) query.mockResolvedValueOnce({ rows });
    const database = { query };
    const integrity = { executeVersionedMutation: jest.fn() };
    const policy = { assertCanManageSystemSettings: jest.fn() };
    const service = new GroupLifecycleService(
      database as unknown as DatabaseService,
      integrity as unknown as PlatformIntegrityService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, integrity, policy };
  };

  it("shows schedule blockers while keeping roster and facts preserved", async () => {
    const { service } = createService([
      [row({ future_lessons: 4, active_series: 1, active_plans: 1 })],
    ]);

    await expect(service.preview(director, "group-a")).resolves.toMatchObject({
      canArchive: false,
      policy: {
        deletionMode: "archive",
        rosterPreserved: true,
        historicalFactsPreserved: true,
      },
      blockers: [
        expect.objectContaining({ code: "FUTURE_LESSONS", count: 4 }),
        expect.objectContaining({ code: "ACTIVE_RECURRING_SERIES", count: 1 }),
        expect.objectContaining({ code: "ACTIVE_SCHEDULE_PLANS", count: 1 }),
      ],
      impact: {
        operational: expect.objectContaining({ activeMembers: 6 }),
        preservedHistory: {
          memberships: 8,
          lessons: 42,
          completedLessons: 34,
          endedSeries: 2,
          endedPlans: 1,
        },
      },
    });
  });

  it("refuses archive before mutation while future lessons remain", async () => {
    const { service, integrity } = createService([
      [row({ future_lessons: 1 })],
    ]);
    await expect(
      service.archive(
        director,
        "group-a",
        {
          expectedVersion: 1,
          confirm: true,
          reasonText: "Группа завершила обучение",
          effectiveDate: "2020-01-01",
        },
        metadata,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "GROUP_ARCHIVE_BLOCKED" }),
    });
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("archives atomically and appends lifecycle history", async () => {
    const archived = row({
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      archive_reason: "Группа завершила обучение",
    });
    const { service, integrity } = createService([[row()], [], [archived]]);
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [row()] })
      .mockResolvedValueOnce({
        rows: [{ version: 2, archived_at: "2026-08-11T12:00:00.000Z" }],
      })
      .mockResolvedValueOnce({ rows: [] });
    integrity.executeVersionedMutation.mockImplementation(async (command) => {
      const resultRef = await command.mutate({ query: clientQuery }, 2);
      return {
        resultRef,
        version: 2,
        replayed: false,
        auditId: "audit-a",
        eventId: "event-a",
      };
    });

    await expect(
      service.archive(
        director,
        "group-a",
        {
          expectedVersion: 1,
          confirm: true,
          reasonText: "Группа завершила обучение",
          effectiveDate: "2020-01-01",
        },
        metadata,
      ),
    ).resolves.toMatchObject({
      group: { lifecycleState: "archived", version: 2 },
      replayed: false,
    });
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        aggregateType: "organization:group",
        authorization: expect.objectContaining({
          capabilityKey: "system.settings.manage",
        }),
        audit: expect.objectContaining({
          action: "crm.group_archived",
          reason: "group.archive",
        }),
        outbox: expect.objectContaining({
          type: "organization.group.changed",
        }),
      }),
    );
    expect(clientQuery.mock.calls[1][0]).toContain("update app.groups");
    expect(clientQuery.mock.calls[1][0]).not.toMatch(/delete\s+from/i);
    expect(clientQuery.mock.calls[2][0]).toContain(
      "insert into app.group_lifecycle_history",
    );
  });

  it("blocks restore until branch, room and teacher are active", async () => {
    const archived = row({
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      branch_lifecycle_state: "archived",
      branch_deleted_at: "2026-08-11T11:00:00.000Z",
      room_lifecycle_state: "archived",
      room_deleted_at: "2026-08-11T11:00:00.000Z",
      teacher_assignment_active: false,
    });
    const { service, integrity } = createService([[archived]]);

    await expect(
      service.restore(
        director,
        "group-a",
        {
          expectedVersion: 2,
          confirm: true,
          reasonText: "Новый учебный набор",
          effectiveDate: "2020-01-02",
        },
        { ...metadata, idempotencyKey: "group-restore-request-0001" },
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "GROUP_RESTORE_BLOCKED",
        blockers: expect.arrayContaining([
          expect.objectContaining({ code: "PARENT_BRANCH_NOT_ACTIVE" }),
          expect.objectContaining({ code: "GROUP_ROOM_NOT_ACTIVE" }),
          expect.objectContaining({ code: "GROUP_TEACHER_NOT_ACTIVE" }),
        ]),
      }),
    });
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("enforces a manager's branch scope before returning lifecycle data", async () => {
    const manager = { userId: "manager-a", role: "manager" as const };
    const { service } = createService([[row()], []]);
    await expect(service.preview(manager, "group-a")).rejects.toThrow(
      "Филиал не входит в область доступа.",
    );
  });
});
