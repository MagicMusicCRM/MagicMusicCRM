import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { isDeepStrictEqual } from "node:util";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import {
  PublishCrmConfigurationDto,
  RollbackCrmConfigurationDto,
  SaveCrmConfigurationDraftDto,
} from "./dto/crm-configuration.dto";

const valueTypes = new Set([
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
]);
const placementTypes = new Set(["create", "edit", "card", "table"]);
const widthTypes = new Set(["third", "half", "full"]);
const settingDefinitions = {
  default_lesson_duration_minutes: { min: 15, max: 240 },
  payment_reminder_days: { min: 0, max: 60 },
} as const;

export interface ConfigCategory {
  key: string;
  label: string;
  order: number;
  active: boolean;
}

export interface ConfigField {
  id?: string;
  entityType: "lead" | "student";
  key: string;
  label: string;
  valueType: string;
  required: boolean;
  active: boolean;
  system: boolean;
  categoryKey: string;
  order: number;
  width: string;
  placements: string[];
  options: string[];
  optionSetKey?: string;
}

export interface ConfigOptionSet {
  key: string;
  label: string;
  multiple: boolean;
  options: Array<{
    key: string;
    label: string;
    order: number;
    active: boolean;
  }>;
}

export interface ConfigSetting {
  key: keyof typeof settingDefinitions;
  label: string;
  valueType: "integer";
  unit: string;
  min: number;
  max: number;
  value: number;
  branchOverridable: boolean;
}

export interface LessonSettlementTypeConfig {
  stableKey: string;
  label: string;
  colorToken: string;
  hourShareBasisPoints: number;
  fixedPenaltyMinor?: string;
  allowedContexts: string[];
  active: boolean;
  order: number;
}

export interface TeacherCompensationRuleConfig {
  stableKey: string;
  label: string;
  mode: "none" | "standard" | "percent" | "fixed" | "hourly";
  value: string;
  active: boolean;
  order: number;
}

export interface ConfigSnapshot {
  categories: ConfigCategory[];
  fields: ConfigField[];
  optionSets: ConfigOptionSet[];
  businessSettings: ConfigSetting[];
  lessonSettlementTypes?: LessonSettlementTypeConfig[];
  teacherCompensationRules?: TeacherCompensationRuleConfig[];
}

interface RevisionRow {
  id: string;
  branch_id: string | null;
  version: number | string;
  patch: ConfigSnapshot | { businessSettings: ConfigSetting[] };
  effective_snapshot: ConfigSnapshot;
  impact: Record<string, unknown>;
  reason: string;
  rollback_from_version: number | string | null;
  created_by: string | null;
  created_at: Date | string;
}

export interface ImpactReport {
  valid: boolean;
  blockingIssues: Array<{ field: string; code: string; message: string }>;
  warnings: string[];
  changes: {
    fieldsCreated: number;
    fieldsUpdated: number;
    fieldsArchived: number;
    settingsChanged: number;
  };
  affectedScreens: string[];
}

type Queryable = Pick<PoolClient, "query"> | DatabaseService;

function runQuery<T extends QueryResultRow>(
  queryable: Queryable,
  text: string,
  params: unknown[] = [],
): Promise<QueryResult<T>> {
  return (
    queryable.query as (
      query: string,
      values?: unknown[],
    ) => Promise<QueryResult<T>>
  )(text, params);
}

function sameJson(left: unknown, right: unknown): boolean {
  return isDeepStrictEqual(
    JSON.parse(JSON.stringify(left)),
    JSON.parse(JSON.stringify(right)),
  );
}

@Injectable()
export class CrmConfigurationService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeBus,
  ) {}

  async getEffective(actor: ActorContext, branchId?: string) {
    await this.assertScope(actor, branchId);
    const effective = await this.resolveEffective(this.database, branchId);
    return {
      branchId: branchId ?? null,
      source: effective.branchVersion > 0 ? "branch_override" : "school",
      schoolVersion: effective.schoolVersion,
      branchVersion: effective.branchVersion,
      snapshot: effective.snapshot,
      sources: this.settingSources(
        effective.snapshot,
        effective.schoolSnapshot,
      ),
    };
  }

  async getDraft(actor: ActorContext, branchId?: string) {
    await this.assertScope(actor, branchId);
    const result = await this.database.query<{
      base_version: number | string;
      snapshot: ConfigSnapshot;
      updated_at: Date | string;
    }>(
      `select base_version, snapshot, updated_at
       from app.crm_configuration_drafts
       where user_id = $1 and branch_id is not distinct from $2::uuid
       limit 1`,
      [actor.userId, branchId ?? null],
    );
    const existing = result.rows[0];
    if (existing) {
      return {
        branchId: branchId ?? null,
        baseVersion: Number(existing.base_version),
        snapshot: existing.snapshot,
        dirty: true,
        updatedAt: existing.updated_at,
      };
    }
    const effective = await this.resolveEffective(this.database, branchId);
    return {
      branchId: branchId ?? null,
      baseVersion: branchId ? effective.branchVersion : effective.schoolVersion,
      snapshot: effective.snapshot,
      dirty: false,
      updatedAt: null,
    };
  }

  async saveDraft(actor: ActorContext, dto: SaveCrmConfigurationDraftDto) {
    await this.assertScope(actor, dto.branchId);
    const snapshot = this.normalizeSnapshot(dto.snapshot);
    const current = await this.resolveEffective(this.database, dto.branchId);
    const currentVersion = dto.branchId
      ? current.branchVersion
      : current.schoolVersion;
    if (currentVersion !== dto.baseVersion) {
      throw new ConflictException({
        code: "STALE_CONFIGURATION_VERSION",
        message: "Конфигурация уже опубликована в другой вкладке.",
        currentVersion,
      });
    }
    const conflictTarget = dto.branchId
      ? "(user_id, branch_id) where branch_id is not null"
      : "(user_id) where branch_id is null";
    const result = await this.database.query<{ updated_at: Date | string }>(
      `insert into app.crm_configuration_drafts (
         user_id, branch_id, base_version, snapshot
       ) values ($1, $2, $3, $4::jsonb)
       on conflict ${conflictTarget}
       do update set base_version = excluded.base_version,
         snapshot = excluded.snapshot, updated_at = now()
       returning updated_at`,
      [
        actor.userId,
        dto.branchId ?? null,
        dto.baseVersion,
        JSON.stringify(snapshot),
      ],
    );
    return {
      branchId: dto.branchId ?? null,
      baseVersion: dto.baseVersion,
      snapshot,
      dirty: true,
      updatedAt: result.rows[0]?.updated_at,
    };
  }

  async preview(actor: ActorContext, dto: SaveCrmConfigurationDraftDto) {
    await this.assertScope(actor, dto.branchId);
    const snapshot = this.normalizeSnapshot(dto.snapshot);
    const effective = await this.resolveEffective(this.database, dto.branchId);
    return this.buildImpact(
      this.database,
      snapshot,
      effective.snapshot,
      dto.branchId ? effective.schoolSnapshot : undefined,
    );
  }

  async publish(actor: ActorContext, dto: PublishCrmConfigurationDto) {
    await this.assertScope(actor, dto.branchId);
    return this.publishRevision(actor, dto, null);
  }

  async listRevisions(actor: ActorContext, branchId?: string) {
    await this.assertScope(actor, branchId);
    const result = await this.database.query<RevisionRow>(
      `select id, branch_id, version, patch, effective_snapshot, impact,
         reason, rollback_from_version, created_by, created_at
       from app.crm_configuration_revisions
       where branch_id is not distinct from $1::uuid
       order by version desc limit 50`,
      [branchId ?? null],
    );
    return { items: result.rows.map((row) => this.revisionDto(row)) };
  }

  async rollback(actor: ActorContext, dto: RollbackCrmConfigurationDto) {
    await this.assertScope(actor, dto.branchId);
    const target = await this.database.query<RevisionRow>(
      `select id, branch_id, version, patch, effective_snapshot, impact,
         reason, rollback_from_version, created_by, created_at
       from app.crm_configuration_revisions
       where branch_id is not distinct from $1::uuid and version = $2
       limit 1`,
      [dto.branchId ?? null, dto.targetVersion],
    );
    const revision = target.rows[0];
    if (!revision)
      throw new NotFoundException("Версия конфигурации не найдена.");
    const snapshot = dto.branchId
      ? this.applyBranchPatch(
          (await this.resolveSchool(this.database)).snapshot,
          revision.patch as { businessSettings: ConfigSetting[] },
        )
      : revision.effective_snapshot;
    return this.publishRevision(
      actor,
      {
        branchId: dto.branchId,
        baseVersion: dto.expectedVersion,
        reason: dto.reason,
        snapshot: snapshot as unknown as Record<string, unknown>,
      },
      dto.targetVersion,
    );
  }

  private async publishRevision(
    actor: ActorContext,
    dto: PublishCrmConfigurationDto,
    rollbackFromVersion: number | null,
  ) {
    const reason = dto.reason.trim();
    if (!reason) {
      throw new UnprocessableEntityException({
        code: "REASON_REQUIRED",
        field: "reason",
        message: "Укажите причину публикации.",
      });
    }
    const requested = this.normalizeSnapshot(dto.snapshot);
    const result = await this.database.transaction(async (client) => {
      await client.query("select pg_advisory_xact_lock(hashtext($1))", [
        `crm-configuration:${dto.branchId ?? "school"}`,
      ]);
      if (dto.branchId) await this.assertBranch(client, dto.branchId);
      const effective = await this.resolveEffective(client, dto.branchId);
      const currentVersion = dto.branchId
        ? effective.branchVersion
        : effective.schoolVersion;
      if (currentVersion !== dto.baseVersion) {
        throw new ConflictException({
          code: "STALE_CONFIGURATION_VERSION",
          message: "Конфигурация уже опубликована в другой вкладке.",
          currentVersion,
        });
      }
      const impact = await this.buildImpact(
        client,
        requested,
        effective.snapshot,
        dto.branchId ? effective.schoolSnapshot : undefined,
      );
      if (!impact.valid) {
        throw new UnprocessableEntityException({
          code: "CONFIGURATION_INVALID",
          message: "Исправьте блокирующие ошибки перед публикацией.",
          impact,
        });
      }
      const snapshot = dto.branchId
        ? requested
        : await this.syncClientFields(client, requested);
      const nextVersion = currentVersion + 1;
      const patch = dto.branchId
        ? this.branchPatch(effective.schoolSnapshot, snapshot)
        : snapshot;
      const inserted = await client.query<RevisionRow>(
        `insert into app.crm_configuration_revisions (
           branch_id, version, patch, effective_snapshot, impact, reason,
           rollback_from_version, created_by
         ) values ($1, $2, $3::jsonb, $4::jsonb, $5::jsonb, $6, $7, $8)
         returning id, branch_id, version, patch, effective_snapshot, impact,
           reason, rollback_from_version, created_by, created_at`,
        [
          dto.branchId ?? null,
          nextVersion,
          JSON.stringify(patch),
          JSON.stringify(snapshot),
          JSON.stringify(impact),
          reason,
          rollbackFromVersion,
          actor.userId,
        ],
      );
      await client.query(
        `delete from app.crm_configuration_drafts
         where user_id = $1 and branch_id is not distinct from $2::uuid`,
        [actor.userId, dto.branchId ?? null],
      );
      return {
        row: inserted.rows[0]!,
        previousVersion: currentVersion,
      };
    });
    const revision = this.revisionDto(result.row);
    await this.audit.record({
      actor,
      action: "crm.configuration_published",
      entityType: "crm_configuration_revision",
      entityId: revision.id,
      metadata: {
        branchId: revision.branchId,
        beforeVersion: result.previousVersion,
        afterVersion: revision.version,
        reason,
        rollbackFromVersion,
        impact: revision.impact,
      },
    });
    this.realtime.emitSettingChanged("crm.configuration");
    return revision;
  }

  private async assertScope(actor: ActorContext, branchId?: string) {
    this.policy.assertCanManageSystemSettings(actor);
    if (actor.role !== "manager") {
      if (branchId) await this.assertBranch(this.database, branchId);
      return;
    }
    if (!branchId) {
      throw new ForbiddenException(
        "Управляющему доступна только конфигурация назначенного филиала.",
      );
    }
    const result = await this.database.query<{ allowed: boolean }>(
      `select exists (
         select 1 from app.user_crm_links link
         join app.staff_members staff on staff.id = link.entity_id
           and link.entity_type = 'staff' and link.deleted_at is null
           and staff.deleted_at is null
         join app.staff_branch_assignments assignment
           on assignment.staff_member_id = staff.id
           and assignment.deleted_at is null
         where link.user_id = $1 and assignment.branch_id = $2
       ) as allowed`,
      [actor.userId, branchId],
    );
    if (result.rows[0]?.allowed !== true) {
      throw new ForbiddenException("Филиал не входит в область доступа.");
    }
  }

  private async resolveEffective(queryable: Queryable, branchId?: string) {
    const school = await this.resolveSchool(queryable);
    if (!branchId) {
      return {
        schoolVersion: school.version,
        branchVersion: 0,
        schoolSnapshot: school.snapshot,
        snapshot: school.snapshot,
      };
    }
    await this.assertBranch(queryable, branchId);
    const branch = await runQuery<RevisionRow>(
      queryable,
      `select id, branch_id, version, patch, effective_snapshot, impact,
         reason, rollback_from_version, created_by, created_at
       from app.crm_configuration_revisions
       where branch_id = $1 order by version desc limit 1`,
      [branchId],
    );
    const latest = branch.rows[0];
    return {
      schoolVersion: school.version,
      branchVersion: latest ? Number(latest.version) : 0,
      schoolSnapshot: school.snapshot,
      snapshot: latest
        ? this.applyBranchPatch(
            school.snapshot,
            latest.patch as { businessSettings: ConfigSetting[] },
          )
        : school.snapshot,
    };
  }

  private async resolveSchool(queryable: Queryable) {
    const result = await runQuery<RevisionRow>(
      queryable,
      `select id, branch_id, version, patch, effective_snapshot, impact,
         reason, rollback_from_version, created_by, created_at
       from app.crm_configuration_revisions
       where branch_id is null order by version desc limit 1`,
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Школьная конфигурация не создана.");
    return { version: Number(row.version), snapshot: row.effective_snapshot };
  }

  private async buildImpact(
    queryable: Queryable,
    next: ConfigSnapshot,
    current: ConfigSnapshot,
    school?: ConfigSnapshot,
  ): Promise<ImpactReport> {
    const blockingIssues: ImpactReport["blockingIssues"] = [];
    if (school) {
      for (const key of ["categories", "fields", "optionSets"] as const) {
        if (!sameJson(next[key], school[key])) {
          blockingIssues.push({
            field: key,
            code: "BRANCH_SCHEMA_OVERRIDE_FORBIDDEN",
            message: "Филиал может переопределять только бизнес-параметры.",
          });
        }
      }
      const schoolSettings = new Map(
        school.businessSettings.map((setting) => [setting.key, setting]),
      );
      for (const setting of next.businessSettings) {
        if (
          setting.value !== schoolSettings.get(setting.key)?.value &&
          !schoolSettings.get(setting.key)?.branchOverridable
        ) {
          blockingIssues.push({
            field: `businessSettings.${setting.key}`,
            code: "BRANCH_OVERRIDE_FORBIDDEN",
            message: "Параметр не допускает филиальное переопределение.",
          });
        }
      }
    }
    const currentFields = new Map(
      current.fields.map((field) => [
        `${field.entityType}:${field.key}`,
        field,
      ]),
    );
    const nextFields = new Map(
      next.fields.map((field) => [`${field.entityType}:${field.key}`, field]),
    );
    for (const [key, field] of nextFields) {
      const before = currentFields.get(key);
      if (!before) continue;
      if (
        before.system &&
        (field.valueType !== before.valueType || !field.active)
      ) {
        blockingIssues.push({
          field: `fields.${field.key}`,
          code: "SYSTEM_FIELD_LOCKED",
          message: "Тип и активность системного поля защищены.",
        });
      }
      if (before.valueType !== field.valueType && before.id) {
        const count = await runQuery<{ count: number | string }>(
          queryable,
          "select count(*) as count from app.client_custom_field_values where definition_id = $1",
          [before.id],
        );
        if (Number(count.rows[0]?.count ?? 0) > 0) {
          blockingIssues.push({
            field: `fields.${field.key}.valueType`,
            code: "FIELD_TYPE_MIGRATION_REQUIRED",
            message:
              "Поле с сохранёнными значениями нельзя перевести в другой тип.",
          });
        }
      }
    }
    const changed = (field: ConfigField) =>
      JSON.stringify(field) !==
      JSON.stringify(currentFields.get(`${field.entityType}:${field.key}`));
    const settings = new Map(
      current.businessSettings.map((setting) => [setting.key, setting.value]),
    );
    const settingsChanged = next.businessSettings.filter(
      (setting) => settings.get(setting.key) !== setting.value,
    ).length;
    const fieldChange =
      next.fields.some(changed) ||
      current.fields.some(
        (field) => !nextFields.has(`${field.entityType}:${field.key}`),
      );
    return {
      valid: blockingIssues.length === 0,
      blockingIssues,
      warnings:
        settingsChanged > 0
          ? ["Новые значения применятся только к будущим бизнес-снимкам."]
          : [],
      changes: {
        fieldsCreated: next.fields.filter(
          (field) => !currentFields.has(`${field.entityType}:${field.key}`),
        ).length,
        fieldsUpdated: next.fields.filter(
          (field) =>
            currentFields.has(`${field.entityType}:${field.key}`) &&
            changed(field),
        ).length,
        fieldsArchived: current.fields.filter(
          (field) => !nextFields.has(`${field.entityType}:${field.key}`),
        ).length,
        settingsChanged,
      },
      affectedScreens: [
        ...(fieldChange
          ? ["lead.create", "student.create", "client.card.custom_fields"]
          : []),
        ...(settingsChanged
          ? ["schedule.lesson.create", "client.payments"]
          : []),
      ],
    };
  }

  private async syncClientFields(client: PoolClient, snapshot: ConfigSnapshot) {
    const keys = snapshot.fields.map(
      (field) => `${field.entityType}:${field.key}`,
    );
    const categoryLabels = new Map(
      snapshot.categories.map((category) => [category.key, category.label]),
    );
    for (const field of snapshot.fields) {
      const result = await client.query<{ id: string }>(
        `insert into app.client_custom_field_definitions (
           entity_type, field_key, label, value_type, is_required, is_active,
           is_system, options, category_key, category_label, sort_order, width, placements
         ) values ($1, $2, $3, $4, $5, $6, false, $7::jsonb, $8, $9, $10, $11, $12::jsonb)
         on conflict (entity_type, field_key) do update set
           label = excluded.label,
           value_type = case when app.client_custom_field_definitions.is_system
             then app.client_custom_field_definitions.value_type else excluded.value_type end,
           is_required = excluded.is_required,
           is_active = case when app.client_custom_field_definitions.is_system
             then true else excluded.is_active end,
           deleted_at = case when excluded.is_active then null else coalesce(app.client_custom_field_definitions.deleted_at, now()) end,
           options = excluded.options,
           category_key = excluded.category_key,
           category_label = excluded.category_label,
           sort_order = excluded.sort_order,
           width = excluded.width,
           placements = excluded.placements,
           version = app.client_custom_field_definitions.version + 1,
           updated_at = now()
         returning id`,
        [
          field.entityType,
          field.key,
          field.label,
          field.valueType,
          field.required,
          field.active,
          JSON.stringify(field.options),
          field.categoryKey,
          categoryLabels.get(field.categoryKey) ?? field.categoryKey,
          field.order,
          field.width,
          JSON.stringify(field.placements),
        ],
      );
      field.id = result.rows[0]!.id;
    }
    await client.query(
      `update app.client_custom_field_definitions definition
       set is_active = false, deleted_at = coalesce(deleted_at, now()),
         version = version + 1, updated_at = now()
       where not definition.is_system
         and not ((definition.entity_type || ':' || definition.field_key) = any($1::text[]))
         and definition.is_active`,
      [keys],
    );
    return snapshot;
  }

  private normalizeSnapshot(raw: Record<string, unknown>): ConfigSnapshot {
    const categories = this.array(raw.categories, "categories").map(
      (item, index) => {
        const row = this.object(item, `categories.${index}`);
        return {
          key: this.key(row.key, `categories.${index}.key`),
          label: this.text(row.label, `categories.${index}.label`, 80),
          order: this.integer(row.order, `categories.${index}.order`, 0, 1000),
          active: this.boolean(row.active, `categories.${index}.active`),
        };
      },
    );
    this.unique(
      categories.map((row) => row.key),
      "categories",
      "DUPLICATE_CATEGORY",
    );
    const categoryKeys = new Set(categories.map((row) => row.key));
    const fields = this.array(raw.fields, "fields").map((item, index) => {
      const row = this.object(item, `fields.${index}`);
      const entityType = row.entityType;
      if (entityType !== "lead" && entityType !== "student") {
        this.invalid(
          `fields.${index}.entityType`,
          "INVALID_ENTITY",
          "Допустимы lead и student.",
        );
      }
      const valueType = this.text(
        row.valueType,
        `fields.${index}.valueType`,
        32,
      );
      if (!valueTypes.has(valueType)) {
        this.invalid(
          `fields.${index}.valueType`,
          "INVALID_TYPE",
          "Тип поля не поддерживается.",
        );
      }
      const categoryKey = this.key(
        row.categoryKey,
        `fields.${index}.categoryKey`,
      );
      if (!categoryKeys.has(categoryKey)) {
        this.invalid(
          `fields.${index}.categoryKey`,
          "UNKNOWN_CATEGORY",
          "Категория не найдена.",
        );
      }
      const width = this.text(row.width, `fields.${index}.width`, 16);
      if (!widthTypes.has(width)) {
        this.invalid(
          `fields.${index}.width`,
          "INVALID_WIDTH",
          "Ширина поля не поддерживается.",
        );
      }
      const placements = this.array(
        row.placements,
        `fields.${index}.placements`,
      ).map((placement, placementIndex) => {
        const value = this.text(
          placement,
          `fields.${index}.placements.${placementIndex}`,
          16,
        );
        if (!placementTypes.has(value)) {
          this.invalid(
            `fields.${index}.placements.${placementIndex}`,
            "INVALID_PLACEMENT",
            "Размещение поля не поддерживается.",
          );
        }
        return value;
      });
      const options = this.array(
        row.options ?? [],
        `fields.${index}.options`,
      ).map((option, optionIndex) =>
        this.text(option, `fields.${index}.options.${optionIndex}`, 160),
      );
      const system = this.boolean(row.system, `fields.${index}.system`);
      if (
        !system &&
        ["select", "radio", "multi_select", "checkbox_group"].includes(
          valueType,
        ) &&
        options.length === 0 &&
        typeof row.optionSetKey !== "string"
      ) {
        this.invalid(
          `fields.${index}.options`,
          "OPTIONS_REQUIRED",
          "Добавьте хотя бы один вариант.",
        );
      }
      return {
        ...(typeof row.id === "string" ? { id: row.id } : {}),
        entityType,
        key: this.key(row.key, `fields.${index}.key`),
        label: this.text(row.label, `fields.${index}.label`, 120),
        valueType,
        required: this.boolean(row.required, `fields.${index}.required`),
        active: this.boolean(row.active, `fields.${index}.active`),
        system,
        categoryKey,
        order: this.integer(row.order, `fields.${index}.order`, 0, 10000),
        width,
        placements: [...new Set(placements)],
        options: [...new Set(options)],
        ...(typeof row.optionSetKey === "string" && row.optionSetKey.trim()
          ? {
              optionSetKey: this.key(
                row.optionSetKey,
                `fields.${index}.optionSetKey`,
              ),
            }
          : {}),
      } as ConfigField;
    });
    this.unique(
      fields.map((field) => `${field.entityType}:${field.key}`),
      "fields",
      "DUPLICATE_FIELD",
    );
    const optionSets = this.array(raw.optionSets ?? [], "optionSets").map(
      (item, index) => {
        const row = this.object(item, `optionSets.${index}`);
        const options = this.array(
          row.options,
          `optionSets.${index}.options`,
        ).map((option, optionIndex) => {
          const value = this.object(
            option,
            `optionSets.${index}.options.${optionIndex}`,
          );
          return {
            key: this.key(
              value.key,
              `optionSets.${index}.options.${optionIndex}.key`,
            ),
            label: this.text(
              value.label,
              `optionSets.${index}.options.${optionIndex}.label`,
              160,
            ),
            order: this.integer(
              value.order,
              `optionSets.${index}.options.${optionIndex}.order`,
              0,
              1000,
            ),
            active: this.boolean(
              value.active,
              `optionSets.${index}.options.${optionIndex}.active`,
            ),
          };
        });
        this.unique(
          options.map((option) => option.key),
          `optionSets.${index}.options`,
          "DUPLICATE_OPTION",
        );
        return {
          key: this.key(row.key, `optionSets.${index}.key`),
          label: this.text(row.label, `optionSets.${index}.label`, 120),
          multiple: this.boolean(row.multiple, `optionSets.${index}.multiple`),
          options,
        };
      },
    );
    this.unique(
      optionSets.map((set) => set.key),
      "optionSets",
      "DUPLICATE_OPTION_SET",
    );
    const optionSetsByKey = new Map(optionSets.map((set) => [set.key, set]));
    for (const field of fields) {
      if (!field.optionSetKey) continue;
      const optionSet = optionSetsByKey.get(field.optionSetKey);
      if (!optionSet) {
        this.invalid(
          `fields.${field.key}.optionSetKey`,
          "UNKNOWN_OPTION_SET",
          "Выбранный справочник не найден.",
        );
      }
      field.options = optionSet.options
        .filter((option) => option.active)
        .sort((left, right) => left.order - right.order)
        .map((option) => option.label);
    }
    const businessSettings = this.array(
      raw.businessSettings,
      "businessSettings",
    ).map((item, index) => {
      const row = this.object(item, `businessSettings.${index}`);
      const key = this.key(row.key, `businessSettings.${index}.key`);
      const definition =
        settingDefinitions[key as keyof typeof settingDefinitions];
      if (!definition) {
        this.invalid(
          `businessSettings.${index}.key`,
          "UNKNOWN_SETTING",
          "Параметр не входит в безопасный список.",
        );
      }
      const value = this.number(row.value, `businessSettings.${index}.value`);
      if (value < definition.min || value > definition.max) {
        this.invalid(
          `businessSettings.${index}.value`,
          "SETTING_OUT_OF_RANGE",
          `Допустимо ${definition.min}–${definition.max}.`,
        );
      }
      return {
        key: key as keyof typeof settingDefinitions,
        label: this.text(row.label, `businessSettings.${index}.label`, 120),
        valueType: "integer" as const,
        unit: this.text(row.unit, `businessSettings.${index}.unit`, 20),
        min: definition.min,
        max: definition.max,
        value,
        branchOverridable: this.boolean(
          row.branchOverridable,
          `businessSettings.${index}.branchOverridable`,
        ),
      };
    });
    this.unique(
      businessSettings.map((setting) => setting.key),
      "businessSettings",
      "DUPLICATE_SETTING",
    );
    return { categories, fields, optionSets, businessSettings };
  }

  private branchPatch(school: ConfigSnapshot, desired: ConfigSnapshot) {
    const defaults = new Map(
      school.businessSettings.map((setting) => [setting.key, setting]),
    );
    return {
      businessSettings: desired.businessSettings.filter(
        (setting) => setting.value !== defaults.get(setting.key)?.value,
      ),
    };
  }

  private applyBranchPatch(
    school: ConfigSnapshot,
    patch: { businessSettings?: ConfigSetting[] },
  ): ConfigSnapshot {
    const overrides = new Map(
      (patch.businessSettings ?? []).map((setting) => [setting.key, setting]),
    );
    return {
      ...school,
      businessSettings: school.businessSettings.map(
        (setting) => overrides.get(setting.key) ?? setting,
      ),
    };
  }

  private settingSources(snapshot: ConfigSnapshot, school: ConfigSnapshot) {
    const defaults = new Map(
      school.businessSettings.map((setting) => [setting.key, setting.value]),
    );
    return Object.fromEntries(
      snapshot.businessSettings.map((setting) => [
        setting.key,
        setting.value === defaults.get(setting.key)
          ? "school"
          : "branch_override",
      ]),
    );
  }

  private async assertBranch(queryable: Queryable, branchId: string) {
    const result = await runQuery<{ present: boolean }>(
      queryable,
      "select exists (select 1 from app.branches where id = $1 and deleted_at is null) as present",
      [branchId],
    );
    if (!result.rows[0]?.present)
      throw new NotFoundException("Филиал не найден.");
  }

  private revisionDto(row: RevisionRow) {
    return {
      id: row.id,
      branchId: row.branch_id,
      version: Number(row.version),
      reason: row.reason,
      rollbackFromVersion:
        row.rollback_from_version === null
          ? null
          : Number(row.rollback_from_version),
      createdBy: row.created_by,
      createdAt: row.created_at,
      snapshot: row.effective_snapshot,
      patch: row.patch,
      impact: row.impact,
    };
  }

  private array(value: unknown, field: string): unknown[] {
    if (!Array.isArray(value))
      this.invalid(field, "ARRAY_REQUIRED", "Ожидается список.");
    return value as unknown[];
  }

  private object(value: unknown, field: string): Record<string, unknown> {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      this.invalid(field, "OBJECT_REQUIRED", "Ожидается объект.");
    }
    return value as Record<string, unknown>;
  }

  private text(value: unknown, field: string, max: number): string {
    if (
      typeof value !== "string" ||
      !value.trim() ||
      value.trim().length > max
    ) {
      this.invalid(
        field,
        "INVALID_TEXT",
        `Заполните значение длиной до ${max} символов.`,
      );
    }
    return (value as string).trim();
  }

  private key(value: unknown, field: string): string {
    const key = this.text(value, field, 64);
    if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(key)) {
      this.invalid(
        field,
        "INVALID_KEY",
        "Ключ должен начинаться с буквы и содержать только буквы, цифры, _ или -.",
      );
    }
    return key;
  }

  private boolean(value: unknown, field: string): boolean {
    if (typeof value !== "boolean")
      this.invalid(field, "BOOLEAN_REQUIRED", "Ожидается да/нет.");
    return value as boolean;
  }

  private number(value: unknown, field: string): number {
    if (typeof value !== "number" || !Number.isFinite(value)) {
      this.invalid(field, "NUMBER_REQUIRED", "Ожидается число.");
    }
    return value as number;
  }

  private integer(value: unknown, field: string, min: number, max: number) {
    const number = this.number(value, field);
    if (!Number.isInteger(number) || number < min || number > max) {
      this.invalid(
        field,
        "INTEGER_OUT_OF_RANGE",
        `Допустимо целое число ${min}–${max}.`,
      );
    }
    return number;
  }

  private unique(values: string[], field: string, code: string) {
    if (new Set(values).size !== values.length) {
      this.invalid(field, code, "Ключи должны быть уникальными.");
    }
  }

  private invalid(field: string, code: string, message: string): never {
    throw new UnprocessableEntityException({ code, field, message });
  }
}
