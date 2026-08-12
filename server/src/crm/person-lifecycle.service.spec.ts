import { DatabaseService } from "../db/database.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { PersonLifecycleService } from "./person-lifecycle.service";

describe("PersonLifecycleService", () => {
  const director = { userId: "director-a", role: "director" as const };
  const manager = { userId: "manager-a", role: "manager" as const };
  const metadata = {
    idempotencyKey: "person-offboard-request-0001",
    requestId: "request-person-offboard-0001",
  };
  const row = (overrides: Record<string, unknown> = {}) => ({
    id: "teacher-a",
    name: "Иван Петров",
    status: "active",
    lifecycle_state: "active",
    version: 1,
    offboarded_at: null,
    offboard_reason: null,
    lifecycle_previous_status: null,
    lifecycle_account_was_active: null,
    lifecycle_snapshot: {},
    user_id: "teacher-user-a",
    app_role: "teacher",
    is_app_account: true,
    branch_assignments: [{ branchId: "branch-a" }],
    future_lessons: 0,
    active_series: 0,
    active_groups: 0,
    open_tasks: 0,
    active_leads: 0,
    active_overrides: 2,
    active_sessions: 3,
    ...overrides,
  });

  const createService = (queryRows: Record<string, unknown>[][]) => {
    const query = jest.fn();
    for (const rows of queryRows) query.mockResolvedValueOnce({ rows });
    const database = { query };
    const integrity = { executeVersionedMutation: jest.fn() };
    const policy = { assertCanManageSystemSettings: jest.fn() };
    const service = new PersonLifecycleService(
      database as unknown as DatabaseService,
      integrity as unknown as PlatformIntegrityService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, integrity, policy };
  };

  it("shows all teacher blockers and access impact in preview", async () => {
    const { service } = createService([
      [row({ future_lessons: 2, active_series: 1, active_groups: 3 })],
    ]);

    await expect(service.preview(director, "teacher", "teacher-a")).resolves.toMatchObject({
      person: { lifecycleState: "active", version: 1 },
      account: { enabled: true, activeSessions: 3, activeOverrides: 2 },
      canOffboard: false,
      blockers: [
        expect.objectContaining({ code: "FUTURE_LESSONS", count: 2 }),
        expect.objectContaining({ code: "ACTIVE_SERIES", count: 1 }),
        expect.objectContaining({ code: "ACTIVE_GROUPS", count: 3 }),
      ],
    });
  });

  it("keeps managers outside credential and offboarding control", async () => {
    const { service, query } = createService([]);
    await expect(
      service.preview(manager, "staff", "staff-a"),
    ).rejects.toThrow("только директору");
    expect(query).not.toHaveBeenCalled();
  });

  it("refuses offboarding while assigned work remains", async () => {
    const { service, integrity } = createService([[row({ future_lessons: 1 })]]);
    await expect(
      service.offboard(
        director,
        "teacher",
        "teacher-a",
        { expectedVersion: 1, reasonText: "Сотрудник уволен", confirm: true },
        metadata,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ code: "PERSON_OFFBOARD_BLOCKED" }),
    });
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("offboards atomically and revokes assignments, sessions and overrides", async () => {
    const archived = row({
      lifecycle_state: "archived",
      status: "inactive",
      version: 2,
      is_app_account: false,
      active_sessions: 0,
      active_overrides: 0,
    });
    const { service, integrity } = createService([[row()], [], [archived]]);
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [row()] })
      .mockResolvedValueOnce({ rows: [], rowCount: 1 })
      .mockResolvedValue({ rows: [], rowCount: 1 });
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
      service.offboard(
        director,
        "teacher",
        "teacher-a",
        { expectedVersion: 1, reasonText: "Сотрудник уволен", confirm: true },
        metadata,
      ),
    ).resolves.toMatchObject({
      preview: { person: { lifecycleState: "archived", version: 2 } },
      replayed: false,
    });

    const sql = clientQuery.mock.calls.map((call) => String(call[0])).join("\n");
    expect(sql).toContain("update app.teachers");
    expect(sql).toContain("update app.teacher_branches");
    expect(sql).toContain("update app.refresh_sessions");
    expect(sql).toContain("update app.user_capability_overrides");
    expect(sql).toContain("insert into app.person_lifecycle_history");
    expect(sql).not.toMatch(/delete\s+from/i);
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.teacher.offboard",
        aggregateType: "organization:teacher",
        authorization: expect.objectContaining({
          capabilityKey: "system.settings.manage",
        }),
        outbox: expect.objectContaining({
          type: "organization.person.changed",
        }),
      }),
    );
  });
});
