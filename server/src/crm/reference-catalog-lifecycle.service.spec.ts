import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { ReferenceCatalogLifecycleService } from "./reference-catalog-lifecycle.service";

describe("ReferenceCatalogLifecycleService", () => {
  const director = { userId: "director-a", role: "director" as const };
  const manager = { userId: "manager-a", role: "manager" as const };
  const metadata = {
    idempotencyKey: "reference-lifecycle-request-0001",
    requestId: "request-reference-lifecycle-0001",
  };

  const row = (overrides: Record<string, unknown> = {}) => ({
    id: "discipline-a",
    name: "Вокал",
    kind: null,
    sort_order: null,
    color: null,
    branch_id: null,
    branch_name: null,
    branch_lifecycle_state: null,
    discipline_id: null,
    discipline_lifecycle_state: null,
    lifecycle_state: "active",
    version: 1,
    archived_at: null,
    archive_reason: null,
    active_branch_assignments: 0,
    active_teacher_assignments: 0,
    active_student_assignments: 0,
    active_packages: 0,
    historical_branch_assignments: 2,
    historical_teacher_assignments: 3,
    historical_student_assignments: 4,
    historical_packages: 5,
    historical_uses: 0,
    ...overrides,
  });

  const createService = (queryRows: Record<string, unknown>[][]) => {
    const query = jest.fn();
    for (const rows of queryRows) query.mockResolvedValueOnce({ rows });
    const database = { query };
    const integrity = { executeVersionedMutation: jest.fn() };
    const policy = { assertCanManageClientConfiguration: jest.fn() };
    const service = new ReferenceCatalogLifecycleService(
      database as unknown as DatabaseService,
      integrity as unknown as PlatformIntegrityService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, integrity, policy };
  };

  it("shows discipline usage as non-blocking preserved impact", async () => {
    const { service } = createService([[
      row({
        active_branch_assignments: 1,
        active_teacher_assignments: 2,
        active_student_assignments: 3,
        active_packages: 4,
      }),
    ]]);

    await expect(
      service.preview(director, "discipline", "discipline-a"),
    ).resolves.toMatchObject({
      entity: { lifecycleState: "active", version: 1 },
      canArchive: true,
      blockers: [],
      impact: {
        activeBranchAssignments: 1,
        activeTeachers: 2,
        activeStudents: 3,
        activePackages: 4,
        preservedHistory: {
          branchAssignments: 2,
          teacherAssignments: 3,
          studentAssignments: 4,
          packageVersions: 5,
        },
      },
      policy: {
        deletionMode: "archive",
        identityPreserved: true,
        historicalFactsPreserved: true,
      },
    });
  });

  it("keeps managers outside global reference configuration", async () => {
    const { service, query, policy } = createService([]);
    policy.assertCanManageClientConfiguration.mockImplementation(() => {
      throw new Error("only director");
    });

    await expect(
      service.preview(manager, "loss_reason", "reason-a"),
    ).rejects.toThrow("only director");
    expect(query).not.toHaveBeenCalled();
  });

  it("keeps branch discipline usage informational during unassignment", async () => {
    const { service } = createService([[
      row({
        id: "branch-discipline-a",
        branch_id: "branch-a",
        branch_name: "Центр",
        discipline_id: "discipline-a",
        active_student_assignments: 2,
      }),
    ]]);

    await expect(
      service.preview(director, "branch_discipline", "branch-discipline-a"),
    ).resolves.toMatchObject({
      canArchive: true,
      blockers: [],
      impact: expect.objectContaining({ activeStudents: 2 }),
    });
  });

  it("unassigns a branch discipline atomically without deleting its identity", async () => {
    const active = row({
      id: "branch-discipline-a",
      branch_id: "branch-a",
      branch_name: "Центр",
      branch_lifecycle_state: "active",
      discipline_id: "discipline-a",
      discipline_lifecycle_state: "active",
      sort_order: 2,
    });
    const archived = row({
      ...active,
      lifecycle_state: "archived",
      version: 2,
      archived_at: "2026-08-11T12:00:00.000Z",
      archive_reason: "Больше не ведём в филиале",
    });
    const { service, integrity } = createService([[active], [], [archived]]);
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [active] })
      .mockResolvedValueOnce({ rows: [{ id: "branch-discipline-a" }] })
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
        "branch_discipline",
        "branch-discipline-a",
        {
          expectedVersion: 1,
          reasonText: "Больше не ведём в филиале",
          confirm: true,
        },
        metadata,
      ),
    ).resolves.toMatchObject({
      preview: {
        entity: { lifecycleState: "archived", version: 2 },
        canRestore: true,
      },
      replayed: false,
    });

    const sql = clientQuery.mock.calls.map((call) => String(call[0])).join("\n");
    expect(sql).toContain("update app.branch_disciplines");
    expect(sql).toContain("insert into app.reference_catalog_history");
    expect(sql).not.toMatch(/delete\s+from/i);
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.reference.branch_discipline.unassigned",
        aggregateType: "reference:branch_discipline",
        authorization: expect.objectContaining({ capabilityKey: "config.crm.edit" }),
        outbox: expect.objectContaining({ type: "reference.catalog.changed" }),
      }),
    );
  });

  it("renames a reason through the versioned audit and outbox path", async () => {
    const active = row({
      id: "reason-a",
      name: "Дорого",
      kind: "lost",
      sort_order: 1,
      historical_uses: 8,
    });
    const renamed = row({ ...active, name: "Высокая цена", version: 2 });
    const { service, integrity } = createService([[active], [], [renamed]]);
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [active] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ version: 2 }] })
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
      service.rename(
        director,
        "loss_reason",
        "reason-a",
        {
          name: "Высокая цена",
          expectedVersion: 1,
          reasonText: "Уточнение формулировки",
          confirm: true,
        },
        metadata,
      ),
    ).resolves.toMatchObject({
      preview: {
        entity: { name: "Высокая цена", version: 2 },
        impact: { historicalLeadTransitions: 8 },
      },
    });

    const sql = clientQuery.mock.calls.map((call) => String(call[0])).join("\n");
    expect(sql).toContain("update app.lead_loss_reasons");
    expect(sql).toContain("insert into app.reference_catalog_history");
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.reference.loss_reason.rename",
        aggregateType: "reference:loss_reason",
      }),
    );
  });
});
