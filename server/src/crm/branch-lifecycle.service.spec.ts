import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { BranchLifecycleService } from "./branch-lifecycle.service";

describe("BranchLifecycleService", () => {
  const director = { userId: "director-a", role: "director" as const };
  const manager = { userId: "manager-a", role: "manager" as const };
  const metadata = {
    idempotencyKey: "branch-close-request-0001",
    requestId: "request-branch-close-0001",
  };

  const row = (overrides: Record<string, unknown> = {}) => ({
    id: "branch-a",
    name: "Сокол",
    address: "Москва",
    lifecycle_state: "active",
    version: 1,
    archived_at: null,
    archive_reason: null,
    archive_effective_date: null,
    timezone_name: "Europe/Moscow",
    active_leads: 0,
    active_students: 0,
    active_families: 0,
    active_rooms: 0,
    active_groups: 0,
    staff_assignments: 0,
    teacher_assignments: 0,
    future_lessons: 0,
    active_series: 0,
    open_tasks: 0,
    active_packages: 0,
    configuration_drafts: 0,
    payment_facts: 4,
    expense_facts: 2,
    lesson_history: 18,
    configuration_revisions: 3,
    chat_history: 6,
    ...overrides,
  });

  const createService = (queryRows: Record<string, unknown>[][]) => {
    const query = jest.fn();
    for (const rows of queryRows) query.mockResolvedValueOnce({ rows });
    const database = { query };
    const integrity = { executeVersionedMutation: jest.fn() };
    const policy = { assertCanManageSystemSettings: jest.fn() };
    const service = new BranchLifecycleService(
      database as unknown as DatabaseService,
      integrity as unknown as PlatformIntegrityService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, integrity, policy };
  };

  it("returns concrete blockers and preserves historical facts in preview", async () => {
    const { service } = createService([
      [row({ active_students: 3, future_lessons: 2, open_tasks: 1 })],
    ]);

    await expect(service.preview(director, "branch-a")).resolves.toMatchObject({
      canClose: false,
      policy: {
        deletionMode: "archive",
        historicalFactsPreserved: true,
      },
      blockers: [
        expect.objectContaining({ code: "ACTIVE_STUDENTS", count: 3 }),
        expect.objectContaining({ code: "FUTURE_LESSONS", count: 2 }),
        expect.objectContaining({ code: "OPEN_TASKS", count: 1 }),
      ],
      impact: {
        operational: expect.any(Object),
        preservedHistory: {
          payments: 4,
          expenses: 2,
          lessons: 18,
          configurationRevisions: 3,
          chats: 6,
        },
      },
    });
  });

  it("keeps delegated managers from branch lifecycle commands", async () => {
    const { service, query } = createService([]);
    await expect(service.preview(manager, "branch-a")).rejects.toThrow(
      "Закрывать и восстанавливать филиалы может только директор.",
    );
    expect(query).not.toHaveBeenCalled();
  });

  it("refuses archive before integrity mutation when blockers remain", async () => {
    const { service, integrity } = createService([[row({ active_rooms: 1 })]]);
    await expect(
      service.archive(
        director,
        "branch-a",
        {
          expectedVersion: 1,
          confirm: true,
          reasonText: "Закрытие офиса",
          effectiveDate: "2020-01-01",
        },
        metadata,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "BRANCH_CLOSE_BLOCKED" }),
    });
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("rejects a future effective date until scheduled closing has write guards", async () => {
    const { service, integrity } = createService([[row()]]);
    await expect(
      service.archive(
        director,
        "branch-a",
        {
          expectedVersion: 1,
          confirm: true,
          reasonText: "Закрытие в будущем",
          effectiveDate: "2999-01-01",
        },
        metadata,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "BRANCH_EFFECTIVE_DATE_IN_FUTURE",
      }),
    });
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("archives atomically, records append-only history and never deletes facts", async () => {
    const archived = row({
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      archive_reason: "Закрытие офиса",
    });
    const { service, integrity } = createService([
      [row()],
      [],
      [archived],
    ]);
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
        "branch-a",
        {
          expectedVersion: 1,
          confirm: true,
          reasonText: "Закрытие офиса",
          effectiveDate: "2020-01-01",
        },
        metadata,
      ),
    ).resolves.toMatchObject({
      branch: { lifecycleState: "archived", version: 2 },
      replayed: false,
    });

    const command = integrity.executeVersionedMutation.mock.calls[0][0];
    expect(command).toMatchObject({
      aggregateType: "organization:branch",
      expectedVersion: 1,
      authorization: { capabilityKey: "config.crm.edit" },
      audit: { action: "crm.branch_archived", reason: "branch.close" },
      outbox: { type: "organization.branch.changed" },
    });
    expect(clientQuery.mock.calls[1][0]).toContain("update app.branches");
    expect(clientQuery.mock.calls[1][0]).not.toMatch(/delete\s+from/i);
    expect(clientQuery.mock.calls[2][0]).toContain(
      "insert into app.branch_lifecycle_history",
    );
  });

  it("restores an archived tombstone through the same integrity contract", async () => {
    const archived = row({
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      archive_reason: "Закрытие офиса",
    });
    const active = row({ version: 3 });
    const { service, integrity } = createService([[archived], [], [active]]);
    integrity.executeVersionedMutation.mockResolvedValue({
      resultRef: {
        branchId: "branch-a",
        lifecycleState: "active",
        branchVersion: 3,
      },
      version: 3,
      replayed: false,
      auditId: "audit-b",
      eventId: "event-b",
    });

    await expect(
      service.restore(
        director,
        "branch-a",
        {
          expectedVersion: 2,
          confirm: true,
          reasonText: "Филиал снова работает",
          effectiveDate: "2020-01-02",
        },
        { ...metadata, idempotencyKey: "branch-restore-request-0001" },
      ),
    ).resolves.toMatchObject({ branch: { lifecycleState: "active", version: 3 } });
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.branch.restore",
        expectedVersion: 2,
      }),
    );
  });
});
