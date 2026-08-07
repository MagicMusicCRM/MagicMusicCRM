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
import {
  ConfigSnapshot,
  CrmConfigurationService,
} from "./crm-configuration.service";
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
    expect(
      snapshot.teacherCompensationRules.map((rule) => rule.label),
    ).toEqual([
      "Не оплачивать",
      "Полная стандартная ставка",
      "Процент ставки",
      "Фиксированная сумма",
      "Почасовая сумма",
    ]);
    snapshot.lessonSettlementTypes = snapshot.lessonSettlementTypes.map(
      (type) =>
        type.stableKey === "partially_paid_lesson"
          ? { ...type, hourShareBasisPoints: 6000 }
          : type,
    );
    snapshot.teacherCompensationRules =
      snapshot.teacherCompensationRules.map((rule) =>
        rule.stableKey === "percent" ? { ...rule, value: "12500" } : rule,
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
        entityType: index % 2 === 0 ? "lead" : "student",
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
        settlementTypesChanged: 1,
        compensationRulesChanged: 1,
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
    expect(
      published.snapshot.lessonSettlementTypes.find(
        (type: { stableKey: string }) =>
          type.stableKey === "partially_paid_lesson",
      )!.hourShareBasisPoints,
    ).toBe(6000);
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
    branch.businessSettings = branch.businessSettings.map((setting) =>
      setting.key === "payment_reminder_days"
        ? { ...setting, value: setting.value + 1 }
        : setting,
    );
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
      sources: { payment_reminder_days: "branch_override" },
    });
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

  it("versions and rolls back a Director branch catalog override", async () => {
    const current = await service.getEffective(director, branchId);
    const override = structuredClone(current.snapshot as ConfigSnapshot);
    override.lessonSettlementTypes = override.lessonSettlementTypes.map(
      (type) =>
        type.stableKey === "paid_miss"
          ? { ...type, colorToken: "branch_blue" }
          : type,
    );
    const published = await service.publish(director, {
      branchId,
      baseVersion: current.branchVersion,
      reason: "Branch settlement color override",
      snapshot: override as unknown as Record<string, unknown>,
    });
    expect(published.version).toBe(2);
    await expect(service.getEffective(director, branchId)).resolves.toMatchObject(
      {
        sources: { lessonSettlementTypes: "branch_override" },
      },
    );

    const rollback = await service.rollback(director, {
      branchId,
      expectedVersion: 2,
      targetVersion: 1,
      reason: "Restore school settlement catalog",
    });
    expect(rollback).toMatchObject({ version: 3, rollbackFromVersion: 1 });
    await expect(service.getEffective(director, branchId)).resolves.toMatchObject(
      {
        sources: { lessonSettlementTypes: "school" },
      },
    );
  });

  it("validates catalog bounds and requires stable-key archival", async () => {
    const current = await service.getEffective(director);
    const outOfRange = structuredClone(current.snapshot as ConfigSnapshot);
    outOfRange.lessonSettlementTypes[0]!.hourShareBasisPoints = 20001;
    await expect(
      service.preview(director, {
        baseVersion: current.schoolVersion,
        snapshot: outOfRange as unknown as Record<string, unknown>,
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);

    const removed = structuredClone(current.snapshot as ConfigSnapshot);
    removed.lessonSettlementTypes = removed.lessonSettlementTypes.slice(1);
    await expect(
      service.preview(director, {
        baseVersion: current.schoolVersion,
        snapshot: removed as unknown as Record<string, unknown>,
      }),
    ).resolves.toMatchObject({
      valid: false,
      blockingIssues: expect.arrayContaining([
        expect.objectContaining({ code: "CATALOG_KEY_REMOVAL_FORBIDDEN" }),
      ]),
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
