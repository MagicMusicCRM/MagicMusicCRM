import {
  ConflictException,
  ForbiddenException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { RealtimeBus } from "../realtime/realtime-bus";
import { createCrmConfigurationBranchPatch } from "./crm-configuration-branch.policy";
import type { ConfigSnapshot } from "./crm-configuration.contracts";
import { CrmConfigurationService } from "./crm-configuration.service";
import { CrmPolicy } from "./crm.policy";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("CRM configuration tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Unified CRM configuration (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let service: CrmConfigurationService;
  let branchId: string;
  let director: ActorContext;
  let manager: ActorContext;
  const audit = { record: jest.fn().mockResolvedValue(undefined) };
  const realtime = { emitSettingChanged: jest.fn() };

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");
    const directorId = randomUUID();
    const managerId = randomUUID();
    branchId = randomUUID();
    const managerProfileId = randomUUID();
    const staffId = randomUUID();
    await client.query(
      `insert into app.users (id, email, role, profile_completed)
       values ($1, $2, 'director', true), ($3, $4, 'manager', true)`,
      [
        directorId,
        `${directorId}@test.local`,
        managerId,
        `${managerId}@test.local`,
      ],
    );
    await client.query(
      "insert into app.branches (id, name) values ($1, 'V6 Config Branch')",
      [branchId],
    );
    await client.query(
      `insert into app.profiles (id, user_id, first_name, last_name)
       values ($1, $2, 'Config', 'Manager')`,
      [managerProfileId, managerId],
    );
    await client.query(
      `insert into app.staff_members (id, profile_id, role)
       values ($1, $2, 'manager')`,
      [staffId, managerProfileId],
    );
    await client.query(
      `insert into app.user_crm_links (
         user_id, entity_type, entity_id, link_source, created_by, confirmed_at
       ) values ($1, 'staff', $2, 'manual_phone', $3, now())`,
      [managerId, staffId, directorId],
    );
    await client.query(
      `insert into app.staff_branch_assignments (staff_member_id, branch_id)
       values ($1, $2)`,
      [staffId, branchId],
    );
    const database = {
      query: (text: string, params?: unknown[]) => client.query(text, params),
      transaction: <T>(work: (transactionClient: PoolClient) => Promise<T>) =>
        work(client),
    } as unknown as DatabaseService;
    service = new CrmConfigurationService(
      database,
      new CrmPolicy(),
      audit as unknown as AuditService,
      realtime as unknown as RealtimeBus,
    );
    director = { userId: directorId, role: "director" };
    manager = { userId: managerId, role: "manager" };
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("bootstraps and publishes the first school configuration from version zero", async () => {
    await client.query("savepoint empty_school_configuration");
    try {
      await client.query(
        `insert into app.client_custom_field_definitions (
           field_key, label, value_type, is_required,
           is_active, is_system, category_key, category_label, sort_order,
           width, placements, options, visible_on_lead, visible_on_student
         ) values (
           'zeroStateOptionalField', 'Поле чистого старта', 'text',
           false, true, false, 'general', 'Основная информация', 999,
           'full', '["create","edit","card"]'::jsonb, '[]'::jsonb,
           true, true
         )
         on conflict (field_key) do update
         set deleted_at = null, is_active = true, is_system = false`,
      );
      await client.query("set local session_replication_role = replica");
      await client.query(
        "drop trigger crm_configuration_revision_immutable on app.crm_configuration_revisions",
      );
      await client.query("delete from app.crm_configuration_revisions");

      const emptySchool = await service.getEffective(director);
      const snapshot = emptySchool.snapshot as ConfigSnapshot;
      expect(emptySchool).toMatchObject({
        source: "school",
        schoolVersion: 0,
        branchVersion: 0,
      });
      expect(snapshot.fields).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ key: "firstName", system: true }),
          expect.objectContaining({
            key: "zeroStateOptionalField",
            system: false,
          }),
        ]),
      );
      expect(snapshot.businessSettings).toHaveLength(2);
      expect(snapshot.lessonSettlementTypes).toHaveLength(7);
      expect(snapshot.teacherCompensationRules).toHaveLength(5);
      await expect(service.listRevisions(director)).resolves.toMatchObject({
        items: [],
      });

      const published = await service.publish(director, {
        baseVersion: 0,
        reason: "Первая настройка школы",
        snapshot: snapshot as unknown as Record<string, unknown>,
      });
      expect(published).toMatchObject({ version: 1, branchId: null });
      await expect(service.getEffective(director)).resolves.toMatchObject({
        schoolVersion: 1,
      });
    } finally {
      await client.query("rollback to savepoint empty_school_configuration");
    }
  });

  it("publishes the supported type matrix and syncs existing client forms", async () => {
    const current = await service.getEffective(director);
    const baseVersion = current.schoolVersion as number;
    const snapshot = structuredClone(current.snapshot as ConfigSnapshot);
    expect(snapshot.lessonSettlementTypes.map((type) => type.label)).toEqual([
      "Занятие",
      "Частично оплачиваемое занятие",
      "Бесплатное занятие",
      "Оплачиваемый пропуск",
      "Частично оплачиваемый пропуск",
      "Неоплачиваемый пропуск",
      "Занятие со штрафом",
    ]);
    expect(snapshot.teacherCompensationRules.map((rule) => rule.label)).toEqual(
      [
        "Не оплачивать",
        "Полная стандартная ставка",
        "Процент ставки",
        "Фиксированная сумма",
        "Почасовая сумма",
      ],
    );
    snapshot.categories.push({
      key: "v6_fields",
      label: "V6 поля",
      order: 10,
      active: true,
    });
    snapshot.optionSets.push({
      key: "experience_levels",
      label: "Опыт",
      multiple: false,
      options: [
        { key: "new", label: "Начинающий", order: 0, active: true },
        { key: "pro", label: "Опытный", order: 1, active: true },
      ],
    });
    const types = [
      "text",
      "textarea",
      "number",
      "money",
      "duration",
      "boolean",
      "toggle",
      "date",
      "datetime",
      "select",
      "radio",
      "multi_select",
      "checkbox_group",
      "email",
      "phone",
      "url",
    ];
    for (const [index, valueType] of types.entries()) {
      snapshot.fields.push({
        key: `v6_${valueType}`,
        label: `V6 ${valueType}`,
        valueType,
        required: false,
        active: true,
        system: false,
        categoryKey: "v6_fields",
        order: index,
        width: index % 3 === 0 ? "third" : "half",
        placements: ["create", "edit", "card"],
        options: ["Начинающий", "Опытный"],
        visibility: { lead: true, student: true },
        ...(["select", "radio", "multi_select", "checkbox_group"].includes(
          valueType,
        )
          ? { optionSetKey: "experience_levels" }
          : {}),
      });
    }

    const preview = await service.preview(director, {
      baseVersion,
      snapshot: snapshot as unknown as Record<string, unknown>,
    });
    expect(preview).toMatchObject({
      valid: true,
      changes: {
        fieldsCreated: types.length,
        settlementTypesChanged: 0,
        compensationRulesChanged: 0,
      },
      affectedScreens: expect.arrayContaining([
        "lead.create",
        "student.create",
      ]),
    });
    await service.saveDraft(director, {
      baseVersion,
      snapshot: snapshot as unknown as Record<string, unknown>,
    });
    const published = await service.publish(director, {
      baseVersion,
      reason: "V6 configuration type matrix",
      snapshot: snapshot as unknown as Record<string, unknown>,
    });
    expect(published.version).toBe(baseVersion + 1);
    const stored = await client.query<{
      value_type: string;
      category_label: string;
      placements: string[];
    }>(
      `select value_type, category_label, placements
       from app.client_custom_field_definitions
       where field_key like 'v6_%'`,
    );
    expect(new Set(stored.rows.map((row) => row.value_type))).toEqual(
      new Set(types),
    );
    expect(stored.rows.every((row) => row.category_label === "V6 поля")).toBe(
      true,
    );
    expect(stored.rows.every((row) => row.placements.includes("create"))).toBe(
      true,
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.configuration_published",
        metadata: expect.objectContaining({
          beforeVersion: baseVersion,
          afterVersion: baseVersion + 1,
          reason: "V6 configuration type matrix",
        }),
      }),
    );
    expect(realtime.emitSettingChanged).toHaveBeenCalledWith(
      "crm.configuration",
    );
  });

  it("projects active lesson decisions to operational administrators", async () => {
    const catalog = await service.getLessonDecisionCatalog(
      { userId: randomUUID(), role: "admin" },
      branchId,
    );
    expect(catalog.branchId).toBe(branchId);
    expect(catalog.defaultLessonDurationMinutes).toBe(60);
    expect(catalog.settlementTypes).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ stableKey: "free_lesson" }),
        expect.objectContaining({ stableKey: "paid_miss" }),
      ]),
    );
    expect(catalog.teacherCompensationRules).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ stableKey: "none" }),
        expect.objectContaining({ stableKey: "standard" }),
      ]),
    );
  });

  it("keeps branch overrides sparse and manager scope branch-only", async () => {
    const school = await service.getEffective(director);
    const branch = structuredClone(school.snapshot as ConfigSnapshot);
    branch.businessSettings = branch.businessSettings.map((setting) => {
      if (setting.key === "payment_reminder_days") {
        return { ...setting, value: setting.value + 1 };
      }
      if (setting.key === "default_lesson_duration_minutes") {
        return { ...setting, value: 75 };
      }
      return setting;
    });
    const preview = await service.preview(manager, {
      branchId,
      baseVersion: 0,
      snapshot: branch as unknown as Record<string, unknown>,
    });
    expect(preview.blockingIssues).toEqual([]);
    await service.publish(manager, {
      branchId,
      baseVersion: 0,
      reason: "Branch payment reminder",
      snapshot: branch as unknown as Record<string, unknown>,
    });
    const effective = await service.getEffective(manager, branchId);
    expect(effective).toMatchObject({
      source: "branch_override",
      branchVersion: 1,
      sources: {
        default_lesson_duration_minutes: "branch_override",
        payment_reminder_days: "branch_override",
      },
    });
    const branchCatalog = await service.getLessonDecisionCatalog(
      { userId: randomUUID(), role: "admin" },
      branchId,
    );
    expect(branchCatalog.defaultLessonDurationMinutes).toBe(75);
    await expect(service.getEffective(manager)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    const protectedChange = structuredClone(
      effective.snapshot as ConfigSnapshot,
    );
    protectedChange.lessonSettlementTypes =
      protectedChange.lessonSettlementTypes.map((type) =>
        type.stableKey === "paid_miss"
          ? { ...type, label: "Платный пропуск — попытка Manager" }
          : type,
      );
    const auditCalls = audit.record.mock.calls.length;
    const realtimeCalls = realtime.emitSettingChanged.mock.calls.length;
    await expect(
      service.publish(manager, {
        branchId,
        baseVersion: 1,
        reason: "Forbidden mixed catalog publish",
        snapshot: protectedChange as unknown as Record<string, unknown>,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(audit.record).toHaveBeenCalledTimes(auditCalls);
    expect(realtime.emitSettingChanged).toHaveBeenCalledTimes(realtimeCalls);
    const invalid = structuredClone(effective.snapshot as ConfigSnapshot);
    invalid.categories.push({
      key: "branch_schema",
      label: "Forbidden",
      order: 99,
      active: true,
    });
    await expect(
      service.publish(manager, {
        branchId,
        baseVersion: 1,
        reason: "Invalid branch schema",
        snapshot: invalid as unknown as Record<string, unknown>,
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    const revisions = await service.listRevisions(director, branchId);
    expect(revisions.items).toHaveLength(1);
  });

  it("preserves the current branch-effective system catalogs during rollback", async () => {
    const school = await service.getEffective(director);
    const beforeHistoricalRelease = await service.getEffective(
      director,
      branchId,
    );
    const historicalRelease = structuredClone(
      beforeHistoricalRelease.snapshot as ConfigSnapshot,
    );
    historicalRelease.lessonSettlementTypes =
      historicalRelease.lessonSettlementTypes.map((type) =>
        type.stableKey === "paid_miss"
          ? { ...type, colorToken: "branch_blue" }
          : type,
      );
    historicalRelease.teacherCompensationRules =
      historicalRelease.teacherCompensationRules.map((rule) =>
        rule.stableKey === "percent" ? { ...rule, value: "9000" } : rule,
      );
    const historicalPatch = createCrmConfigurationBranchPatch(
      school.snapshot as ConfigSnapshot,
      historicalRelease,
    );
    const historicalVersion = beforeHistoricalRelease.branchVersion + 1;
    await client.query("set local session_replication_role = replica");
    await client.query(
      `insert into app.crm_configuration_revisions (
         branch_id, version, patch, effective_snapshot, impact, reason,
         rollback_from_version, created_by
       ) values ($1, $2, $3::jsonb, $4::jsonb, $5::jsonb, $6, $7, $8)`,
      [
        branchId,
        historicalVersion,
        JSON.stringify(historicalPatch),
        JSON.stringify(historicalRelease),
        JSON.stringify({ valid: true, blockingIssues: [], warnings: [] }),
        "Historical system policy release",
        null,
        director.userId,
      ],
    );
    await client.query("set local session_replication_role = origin");
    const current = await service.getEffective(director, branchId);
    expect(current).toMatchObject({
      branchVersion: historicalVersion,
      sources: {
        lessonSettlementTypes: "branch_override",
        teacherCompensationRules: "branch_override",
      },
    });

    const rollback = await service.rollback(director, {
      branchId,
      expectedVersion: current.branchVersion,
      targetVersion: beforeHistoricalRelease.branchVersion,
      reason: "Restore editable branch values",
    });
    expect(rollback).toMatchObject({
      version: current.branchVersion + 1,
      rollbackFromVersion: beforeHistoricalRelease.branchVersion,
    });
    expect(rollback.snapshot.lessonSettlementTypes).toEqual(
      current.snapshot.lessonSettlementTypes,
    );
    expect(rollback.snapshot.teacherCompensationRules).toEqual(
      current.snapshot.teacherCompensationRules,
    );
    await expect(
      service.getEffective(director, branchId),
    ).resolves.toMatchObject({
      sources: {
        lessonSettlementTypes: "branch_override",
        teacherCompensationRules: "branch_override",
      },
    });
  });

  it("rejects direct catalog patches before catalog-specific validation", async () => {
    const current = await service.getEffective(director);
    const outOfRange = structuredClone(current.snapshot as ConfigSnapshot);
    outOfRange.lessonSettlementTypes[0]!.hourShareBasisPoints = 20001;
    await expect(
      service.preview(director, {
        baseVersion: current.schoolVersion,
        snapshot: outOfRange as unknown as Record<string, unknown>,
      }),
    ).rejects.toMatchObject({
      status: 403,
      response: { code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY" },
    });

    const removed = structuredClone(current.snapshot as ConfigSnapshot);
    removed.lessonSettlementTypes = removed.lessonSettlementTypes.slice(1);
    await expect(
      service.preview(director, {
        baseVersion: current.schoolVersion,
        snapshot: removed as unknown as Record<string, unknown>,
      }),
    ).rejects.toMatchObject({
      status: 403,
      response: { code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY" },
    });
  });

  it("rejects the second stale publish and rolls back as a new immutable revision", async () => {
    const current = await service.getEffective(director);
    const baseVersion = current.schoolVersion as number;
    const snapshot = structuredClone(current.snapshot as ConfigSnapshot);
    snapshot.businessSettings = snapshot.businessSettings.map((setting) =>
      setting.key === "payment_reminder_days"
        ? { ...setting, value: Math.min(setting.max, setting.value + 1) }
        : setting,
    );
    await service.publish(director, {
      baseVersion,
      reason: "Concurrent winner",
      snapshot: snapshot as unknown as Record<string, unknown>,
    });
    await expect(
      service.publish(director, {
        baseVersion,
        reason: "Concurrent loser",
        snapshot: snapshot as unknown as Record<string, unknown>,
      }),
    ).rejects.toBeInstanceOf(ConflictException);

    const revisions = await service.listRevisions(director);
    const target = revisions.items.at(-1)!;
    const beforeRollback = revisions.items[0]!.version;
    const rollback = await service.rollback(director, {
      expectedVersion: beforeRollback,
      targetVersion: target.version,
      reason: "Restore prior approved configuration",
    });
    expect(rollback).toMatchObject({
      version: beforeRollback + 1,
      rollbackFromVersion: target.version,
    });
    expect(
      rollback.snapshot.lessonSettlementTypes.find(
        (type: { stableKey: string }) =>
          type.stableKey === "partially_paid_lesson",
      )!.hourShareBasisPoints,
    ).toBe(5000);
    expect(
      rollback.snapshot.teacherCompensationRules.find(
        (rule: { stableKey: string }) => rule.stableKey === "percent",
      )!.value,
    ).toBe("10000");
    await client.query("savepoint immutable_configuration_check");
    await expect(
      client.query(
        "update app.crm_configuration_revisions set reason = 'rewrite' where id = $1",
        [rollback.id],
      ),
    ).rejects.toMatchObject({ code: "23514" });
    await client.query("rollback to savepoint immutable_configuration_check");
  });

  it("blocks a down migration that would destroy configured catalogs", async () => {
    await client.query("savepoint commerce_catalog_down_guard");
    await expect(
      client.query(
        readFileSync(
          resolve(
            process.cwd(),
            "db/migrations/0109_v7_commerce_catalogs.down.sql",
          ),
          "utf8",
        ),
      ),
    ).rejects.toThrow("configured commerce catalogs would be destroyed");
    await client.query("rollback to savepoint commerce_catalog_down_guard");
  });
});
