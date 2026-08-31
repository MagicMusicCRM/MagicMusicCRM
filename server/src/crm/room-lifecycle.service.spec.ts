import { AuditPresentationService } from "../audit/audit-presentation.service";
import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { RoomLifecycleService } from "./room-lifecycle.service";

describe("RoomLifecycleService", () => {
  const director = { userId: "director-a", role: "director" as const };
  const manager = { userId: "manager-a", role: "manager" as const };
  const metadata = {
    idempotencyKey: "room-archive-request-0001",
    requestId: "request-room-archive-0001",
  };

  const row = (overrides: Record<string, unknown> = {}) => ({
    id: "room-a",
    branch_id: "branch-a",
    branch_name: "Сокол",
    branch_lifecycle_state: "active",
    branch_deleted_at: null,
    timezone_name: "Europe/Moscow",
    name: "Класс 1",
    capacity: 8,
    lifecycle_state: "active",
    version: 1,
    archived_at: null,
    archive_reason: null,
    archive_effective_date: null,
    active_groups: 0,
    future_lessons: 0,
    active_series: 0,
    active_plans: 0,
    future_conflicts: 0,
    lesson_history: 18,
    completed_lessons: 12,
    ended_series: 3,
    ended_plans: 2,
    ...overrides,
  });

  const createService = (queryRows: Record<string, unknown>[][]) => {
    const query = jest.fn();
    for (const rows of queryRows) query.mockResolvedValueOnce({ rows });
    const database = { query };
    const integrity = { executeVersionedMutation: jest.fn() };
    const policy = { assertCanManageSystemSettings: jest.fn() };
    const service = new RoomLifecycleService(
      database as unknown as DatabaseService,
      integrity as unknown as PlatformIntegrityService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, integrity, policy };
  };

  const presentAudit = (audit: {
    action: string;
    metadata?: Record<string, unknown>;
    beforeRef?: Record<string, unknown>;
    afterRef?: Record<string, unknown>;
  }) =>
    new AuditPresentationService().present({
      id: "audit-room",
      actionKey: audit.action,
      actor: { id: director.userId, name: "Директор", role: director.role },
      target: { type: "room", id: "room-a", displayName: "Класс 1" },
      metadata: audit.metadata ?? null,
      beforeRef: audit.beforeRef ?? null,
      afterRef: audit.afterRef ?? null,
      reason: null,
      reasonText: null,
      occurredAt: new Date("2026-08-11T12:00:00.000Z"),
    });

  it("returns every live scheduling blocker and preserved history", async () => {
    const { service } = createService([
      [
        row({
          active_groups: 2,
          future_lessons: 4,
          active_series: 1,
          active_plans: 1,
          future_conflicts: 1,
        }),
      ],
    ]);

    await expect(service.preview(director, "room-a")).resolves.toMatchObject({
      canArchive: false,
      canRestore: false,
      policy: {
        deletionMode: "archive",
        historicalFactsPreserved: true,
      },
      blockers: [
        expect.objectContaining({ code: "ACTIVE_GROUPS", count: 2 }),
        expect.objectContaining({ code: "FUTURE_LESSONS", count: 4 }),
        expect.objectContaining({ code: "ACTIVE_RECURRING_SERIES", count: 1 }),
        expect.objectContaining({ code: "ACTIVE_SCHEDULE_PLANS", count: 1 }),
        expect.objectContaining({ code: "FUTURE_ROOM_CONFLICTS", count: 1 }),
      ],
      impact: {
        operational: expect.any(Object),
        preservedHistory: {
          lessons: 18,
          completedLessons: 12,
          endedSeries: 3,
          endedPlans: 2,
        },
      },
    });
  });

  it("keeps delegated managers from room lifecycle commands", async () => {
    const { service, query } = createService([]);
    await expect(service.preview(manager, "room-a")).rejects.toThrow(
      "Архивировать и восстанавливать аудитории может только директор.",
    );
    expect(query).not.toHaveBeenCalled();
  });

  it("refuses archive before integrity mutation when a future lesson remains", async () => {
    const { service, integrity } = createService([
      [row({ future_lessons: 1 })],
    ]);
    await expect(
      service.archive(
        director,
        "room-a",
        {
          expectedVersion: 1,
          confirm: true,
          reasonText: "Ремонт класса",
          effectiveDate: "2020-01-01",
        },
        metadata,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "ROOM_ARCHIVE_BLOCKED" }),
    });
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("archives atomically, appends history and never deletes lessons", async () => {
    const archived = row({
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      archive_reason: "Ремонт класса",
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
        "room-a",
        {
          expectedVersion: 1,
          confirm: true,
          reasonText: "Ремонт класса",
          effectiveDate: "2020-01-01",
        },
        metadata,
      ),
    ).resolves.toMatchObject({
      room: { lifecycleState: "archived", version: 2 },
      replayed: false,
    });

    const command = integrity.executeVersionedMutation.mock.calls[0][0];
    expect(command).toMatchObject({
      aggregateType: "organization:room",
      expectedVersion: 1,
      authorization: { capabilityKey: "config.crm.edit" },
      audit: { action: "crm.room_archived", reason: "room.archive" },
      outbox: { type: "organization.room.changed" },
    });
    expect(presentAudit(command.audit).changes).toEqual([
      {
        key: "lifecycleState",
        label: "Статус аудитории",
        before: "Активна",
        after: "В архиве",
      },
    ]);
    expect(command.audit).toMatchObject({
      beforeRef: { name: "Класс 1", capacity: 8, lifecycleState: "active" },
      afterRef: { name: "Класс 1", capacity: 8, lifecycleState: "archived" },
    });
    expect(JSON.stringify([
      command.audit.beforeRef,
      command.audit.afterRef,
    ])).not.toMatch(/room-a|branch-a|Capacity/);
    expect(clientQuery.mock.calls[1][0]).toContain("update app.rooms");
    expect(clientQuery.mock.calls[1][0]).not.toMatch(/delete\s+from/i);
    expect(clientQuery.mock.calls[2][0]).toContain(
      "insert into app.room_lifecycle_history",
    );
    expect(JSON.parse(clientQuery.mock.calls[2][1][9])).toMatchObject({
      roomId: "room-a",
      branchId: "branch-a",
      roomVersion: 1,
      archivedAt: null,
      archiveEffectiveDate: null,
      impact: expect.any(Object),
    });
  });

  it("blocks restore while the parent branch is archived", async () => {
    const archived = row({
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      branch_lifecycle_state: "archived",
      branch_deleted_at: "2026-08-11T11:00:00.000Z",
    });
    const { service, integrity } = createService([[archived]]);

    await expect(
      service.restore(
        director,
        "room-a",
        {
          expectedVersion: 2,
          confirm: true,
          reasonText: "Класс снова доступен",
          effectiveDate: "2020-01-02",
        },
        { ...metadata, idempotencyKey: "room-restore-request-0001" },
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "ROOM_RESTORE_BLOCKED" }),
    });
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("restores an archived room through the same versioned contract", async () => {
    const archived = row({
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      archive_reason: "Ремонт класса",
    });
    const active = row({ version: 3 });
    const { service, integrity } = createService([[archived], [], [active]]);
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [archived] })
      .mockResolvedValueOnce({ rows: [{ version: 3 }] })
      .mockResolvedValueOnce({ rows: [] });
    integrity.executeVersionedMutation.mockImplementation(async (command) => {
      const resultRef = await command.mutate({ query: clientQuery }, 3);
      return {
        resultRef,
        version: 3,
        replayed: false,
        auditId: "audit-b",
        eventId: "event-b",
      };
    });

    await expect(
      service.restore(
        director,
        "room-a",
        {
          expectedVersion: 2,
          confirm: true,
          reasonText: "Класс снова доступен",
          effectiveDate: "2020-01-02",
        },
        { ...metadata, idempotencyKey: "room-restore-request-0001" },
      ),
    ).resolves.toMatchObject({
      room: { lifecycleState: "active", version: 3 },
    });
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.room.restore",
        expectedVersion: 2,
      }),
    );
    const command = integrity.executeVersionedMutation.mock.calls[0][0];
    expect(presentAudit(command.audit).changes).toEqual([
      {
        key: "lifecycleState",
        label: "Статус аудитории",
        before: "В архиве",
        after: "Активна",
      },
    ]);
    expect(command.audit).toMatchObject({
      beforeRef: { name: "Класс 1", capacity: 8, lifecycleState: "archived" },
      afterRef: { name: "Класс 1", capacity: 8, lifecycleState: "active" },
    });
    expect(JSON.stringify([
      command.audit.beforeRef,
      command.audit.afterRef,
    ])).not.toMatch(/room-a|branch-a|Capacity/);
  });
});
