import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { buildCrmConfigurationBaseline } from "./crm-configuration-baseline";
import { CrmConfigurationService } from "./crm-configuration.service";
import { CrmPolicy } from "./crm.policy";

describe("CrmConfigurationService", () => {
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
      "penalty_lesson",
    ]);
    expect(
      result.teacherCompensationRules.map((rule) => rule.stableKey),
    ).toEqual(["none", "percent", "fixed", "hourly"]);
  });
});
