import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { buildCrmConfigurationBaseline } from "./crm-configuration-baseline";
import type {
  ConfigBranchPatch,
  ConfigSnapshot,
} from "./crm-configuration.contracts";
import { CrmConfigurationService } from "./crm-configuration.service";
import { CrmPolicy } from "./crm.policy";

const branchId = "10000000-0000-4000-8000-000000000001";

function revision(
  snapshot: ConfigSnapshot,
  version: number,
  branch: string | null,
  patch: ConfigSnapshot | ConfigBranchPatch = snapshot,
  rollbackFromVersion: number | null = null,
) {
  return {
    id: `revision-${branch ?? "school"}-${version}`,
    branch_id: branch,
    version,
    patch,
    effective_snapshot: snapshot,
    impact: {},
    reason: "Тестовая конфигурация",
    rollback_from_version: rollbackFromVersion,
    created_by: "director-1",
    created_at: "2026-08-25T00:00:00.000Z",
  };
}

function catalogLabel(snapshot: ConfigSnapshot, label: string): ConfigSnapshot {
  return {
    ...snapshot,
    lessonSettlementTypes: snapshot.lessonSettlementTypes.map((type, index) =>
      index === 0 ? { ...type, label } : type,
    ),
    teacherCompensationRules: snapshot.teacherCompensationRules.map(
      (rule, index) => (index === 0 ? { ...rule, label } : rule),
    ),
  };
}

function serviceFixture(options: { branch?: boolean } = {}) {
  const schoolSnapshot = buildCrmConfigurationBaseline([]);
  const historicalSnapshot = catalogLabel(
    {
      ...schoolSnapshot,
      businessSettings: schoolSnapshot.businessSettings.map((setting, index) =>
        index === 0 ? { ...setting, value: setting.value + 1 } : setting,
      ),
    },
    "Исторический каталог",
  );
  const currentSnapshot = catalogLabel(schoolSnapshot, "Текущий каталог");
  const historicalPatch: ConfigBranchPatch = {
    businessSettings: historicalSnapshot.businessSettings.filter(
      (setting, index) => index === 0,
    ),
    lessonSettlementTypes: historicalSnapshot.lessonSettlementTypes,
    teacherCompensationRules: historicalSnapshot.teacherCompensationRules,
  };
  const currentBranchPatch: ConfigBranchPatch = { businessSettings: [] };
  const target = revision(
    historicalSnapshot,
    3,
    options.branch ? branchId : null,
    options.branch ? historicalPatch : historicalSnapshot,
  );
  const schoolCurrent = revision(currentSnapshot, 4, null);
  const branchCurrent = revision(
    currentSnapshot,
    4,
    branchId,
    currentBranchPatch,
  );
  const query = jest.fn(async (text: string, params: unknown[] = []) => {
    if (text.includes("from app.user_crm_links")) {
      return { rows: [{ allowed: true }] };
    }
    if (text.includes("from app.branches")) {
      return { rows: [{ present: true }] };
    }
    if (text.includes("version = $2")) {
      return { rows: [target] };
    }
    if (text.includes("where branch_id is null order")) {
      return { rows: [schoolCurrent] };
    }
    if (text.includes("where branch_id = $1 order")) {
      return { rows: [branchCurrent] };
    }
    if (text.includes("insert into app.crm_configuration_revisions")) {
      return {
        rows: [
          revision(
            JSON.parse(String(params[3])) as ConfigSnapshot,
            Number(params[1]),
            (params[0] as string | null) ?? null,
            JSON.parse(String(params[2])) as ConfigSnapshot | ConfigBranchPatch,
            (params[6] as number | null) ?? null,
          ),
        ],
      };
    }
    return { rows: [] };
  });
  const database = {
    query,
    transaction: async <T>(
      work: (client: { query: typeof query }) => Promise<T>,
    ) => work({ query }),
  } as unknown as DatabaseService;
  const audit = { record: jest.fn().mockResolvedValue(undefined) };
  const realtime = { emitSettingChanged: jest.fn() };
  return {
    service: new CrmConfigurationService(
      database,
      new CrmPolicy(),
      audit as unknown as AuditService,
      realtime as unknown as RealtimeBus,
    ),
    audit,
    currentSnapshot,
    historicalSnapshot,
    query,
    realtime,
    target,
  };
}

describe("CrmConfigurationService", () => {
  it.each([
    ["saveDraft", "lessonSettlementTypes"],
    ["saveDraft", "teacherCompensationRules"],
    ["preview", "lessonSettlementTypes"],
    ["preview", "teacherCompensationRules"],
    ["publish", "lessonSettlementTypes"],
    ["publish", "teacherCompensationRules"],
  ] as const)(
    "rejects a branch %s patch to protected %s with a typed business error",
    async (operation, catalog) => {
      const fixture = serviceFixture({ branch: true });
      const snapshot = structuredClone(fixture.currentSnapshot);
      if (catalog === "lessonSettlementTypes") {
        snapshot.lessonSettlementTypes[0].label = "Операторский патч";
      } else {
        snapshot.teacherCompensationRules[0].label = "Операторский патч";
      }
      const actor: ActorContext = { userId: "manager-1", role: "manager" };
      const dto = {
        branchId,
        baseVersion: 4,
        snapshot: snapshot as unknown as Record<string, unknown>,
      };

      const request =
        operation === "saveDraft"
          ? fixture.service.saveDraft(actor, dto)
          : operation === "preview"
            ? fixture.service.preview(actor, dto)
            : fixture.service.publish(actor, {
                ...dto,
                reason: "Запрещённый каталог",
              });

      await expect(request).rejects.toMatchObject({
        status: 403,
        response: { code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY" },
      });
      expect(
        fixture.query.mock.calls.some(([text]) =>
          String(text).includes("insert into app.crm_configuration"),
        ),
      ).toBe(false);
    },
  );

  it("rolls back school editable settings without restoring historical protected catalogs", async () => {
    const fixture = serviceFixture();
    const result = await fixture.service.rollback(
      { userId: "director-1", role: "director" },
      {
        expectedVersion: 4,
        targetVersion: 3,
        reason: "Вернуть редактируемую настройку",
      },
    );

    expect(result).toMatchObject({ version: 5, rollbackFromVersion: 3 });
    expect(result.snapshot.businessSettings[0].value).toBe(
      fixture.historicalSnapshot.businessSettings[0].value,
    );
    expect(result.snapshot.lessonSettlementTypes).toEqual(
      fixture.currentSnapshot.lessonSettlementTypes,
    );
    expect(result.snapshot.teacherCompensationRules).toEqual(
      fixture.currentSnapshot.teacherCompensationRules,
    );
    expect(
      fixture.target.effective_snapshot.lessonSettlementTypes[0].label,
    ).toBe("Исторический каталог");
    expect(fixture.audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        metadata: expect.objectContaining({
          beforeVersion: 4,
          afterVersion: 5,
          rollbackFromVersion: 3,
        }),
      }),
    );
  });

  it("rolls back branch editable settings without restoring historical protected catalogs", async () => {
    const fixture = serviceFixture({ branch: true });
    const result = await fixture.service.rollback(
      { userId: "director-1", role: "director" },
      {
        branchId,
        expectedVersion: 4,
        targetVersion: 3,
        reason: "Вернуть филиальный параметр",
      },
    );

    expect(result).toMatchObject({
      branchId,
      version: 5,
      rollbackFromVersion: 3,
    });
    expect(result.snapshot.businessSettings[0].value).toBe(
      fixture.historicalSnapshot.businessSettings[0].value,
    );
    expect(result.snapshot.lessonSettlementTypes).toEqual(
      fixture.currentSnapshot.lessonSettlementTypes,
    );
    expect(result.snapshot.teacherCompensationRules).toEqual(
      fixture.currentSnapshot.teacherCompensationRules,
    );
    expect(
      (fixture.target.patch as ConfigBranchPatch).lessonSettlementTypes?.[0]
        ?.label,
    ).toBe("Исторический каталог");
    expect(fixture.audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        metadata: expect.objectContaining({
          branchId,
          beforeVersion: 4,
          afterVersion: 5,
          rollbackFromVersion: 3,
        }),
      }),
    );
  });

  it("rejects a preview that changes the system-owned settlement catalog", async () => {
    const snapshot = buildCrmConfigurationBaseline([]);
    const requested = structuredClone(snapshot);
    requested.lessonSettlementTypes[0].label = "Изменённое занятие";
    const database = {
      query: jest.fn().mockResolvedValue({
        rows: [
          {
            id: "revision-1",
            branch_id: null,
            version: 4,
            patch: snapshot,
            effective_snapshot: snapshot,
            impact: {},
            reason: "Тестовая конфигурация",
            rollback_from_version: null,
            created_by: "director-1",
            created_at: "2026-08-25T00:00:00.000Z",
          },
        ],
      }),
    } as unknown as DatabaseService;
    const service = new CrmConfigurationService(
      database,
      new CrmPolicy(),
      { record: jest.fn() } as unknown as AuditService,
      { emitSettingChanged: jest.fn() } as unknown as RealtimeBus,
    );
    const director: ActorContext = { userId: "director-1", role: "director" };

    await expect(
      service.preview(director, {
        baseVersion: 4,
        snapshot: requested as unknown as Record<string, unknown>,
      }),
    ).rejects.toMatchObject({
      status: 403,
      response: { code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY" },
    });
  });

  it("projects only active lesson decisions with the configured duration", async () => {
    const snapshot = buildCrmConfigurationBaseline([]);
    snapshot.businessSettings[0].value = 45;
    snapshot.lessonSettlementTypes[1].active = false;
    snapshot.teacherCompensationRules[1].active = false;
    const database = {
      query: jest.fn().mockResolvedValue({
        rows: [
          {
            id: "revision-1",
            branch_id: null,
            version: 4,
            patch: snapshot,
            effective_snapshot: snapshot,
            impact: {},
            reason: "Тестовая конфигурация",
            rollback_from_version: null,
            created_by: "director-1",
            created_at: "2026-08-25T00:00:00.000Z",
          },
        ],
      }),
    } as unknown as DatabaseService;
    const service = new CrmConfigurationService(
      database,
      new CrmPolicy(),
      { record: jest.fn() } as unknown as AuditService,
      { emitSettingChanged: jest.fn() } as unknown as RealtimeBus,
    );
    const director: ActorContext = { userId: "director-1", role: "director" };

    const result = await service.getLessonDecisionCatalog(director);

    expect(result.branchId).toBeNull();
    expect(result.defaultLessonDurationMinutes).toBe(45);
    expect(result.settlementTypes.map((type) => type.stableKey)).toEqual([
      "lesson",
      "free_lesson",
      "paid_miss",
      "partially_paid_miss",
      "unpaid_miss",
    ]);
    expect(
      result.teacherCompensationRules.map((rule) => rule.stableKey),
    ).toEqual(["none", "percent", "fixed", "hourly"]);
  });
});
