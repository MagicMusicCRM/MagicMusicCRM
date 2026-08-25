import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import { AuditService } from "../audit/audit.service";
import { authorizeCurrentCapability } from "../access-control/capability-request-authorizer";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import {
  buildCrmConfigurationBaseline,
  ClientFieldDefinitionRow,
} from "./crm-configuration-baseline";
import {
  applyCrmConfigurationBranchPatch,
  createCrmConfigurationBranchPatch,
  getCrmConfigurationSettingSources,
  sameCrmConfigurationValue,
} from "./crm-configuration-branch.policy";
import type {
  ConfigBranchPatch,
  ConfigField,
  ConfigSnapshot,
  ImpactReport,
} from "./crm-configuration.contracts";
import { normalizeCrmConfigurationSnapshot } from "./crm-configuration-snapshot-normalizer";
import { CrmPolicy } from "./crm.policy";
import {
  PublishCrmConfigurationDto,
  RollbackCrmConfigurationDto,
  SaveCrmConfigurationDraftDto,
} from "./dto/crm-configuration.dto";

interface RevisionRow {
  id: string;
  branch_id: string | null;
  version: number | string;
  patch: ConfigSnapshot | ConfigBranchPatch;
  effective_snapshot: ConfigSnapshot;
  impact: Record<string, unknown>;
  reason: string;
  rollback_from_version: number | string | null;
  created_by: string | null;
  created_at: Date | string;
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
      sources: getCrmConfigurationSettingSources(
        effective.snapshot,
        effective.schoolSnapshot,
      ),
    };
  }

  async getLessonDecisionCatalog(actor: ActorContext, branchId?: string) {
    this.policy.assertCanWriteCrm(actor);
    if (actor.role === "manager") {
      await this.assertScope(actor, branchId);
    } else if (branchId) {
      await this.assertBranch(this.database, branchId);
    }
    const effective = await this.resolveEffective(this.database, branchId);
    const defaultLessonDurationMinutes =
      effective.snapshot.businessSettings.find(
        (setting) => setting.key === "default_lesson_duration_minutes",
      )?.value ?? 60;
    return {
      branchId: branchId ?? null,
      defaultLessonDurationMinutes,
      settlementTypes: effective.snapshot.lessonSettlementTypes.filter(
        (type) => type.active,
      ),
      teacherCompensationRules:
        effective.snapshot.teacherCompensationRules.filter(
          (rule) => rule.active,
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
        snapshot: normalizeCrmConfigurationSnapshot(
          existing.snapshot as unknown as Record<string, unknown>,
        ),
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
    const snapshot = normalizeCrmConfigurationSnapshot(dto.snapshot);
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
    await this.assertCommerceCatalogAccess(
      this.database,
      actor,
      snapshot,
      current.snapshot,
    );
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
    const snapshot = normalizeCrmConfigurationSnapshot(dto.snapshot);
    const effective = await this.resolveEffective(this.database, dto.branchId);
    await this.assertCommerceCatalogAccess(
      this.database,
      actor,
      snapshot,
      effective.snapshot,
    );
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
      ? applyCrmConfigurationBranchPatch(
          (await this.resolveSchool(this.database)).snapshot,
          revision.patch as ConfigBranchPatch,
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
    const requested = normalizeCrmConfigurationSnapshot(dto.snapshot);
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
      await this.assertCommerceCatalogAccess(
        client,
        actor,
        requested,
        effective.snapshot,
        true,
      );
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
        ? createCrmConfigurationBranchPatch(effective.schoolSnapshot, snapshot)
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
        ? applyCrmConfigurationBranchPatch(
            school.snapshot,
            latest.patch as ConfigBranchPatch,
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
    if (!row) {
      const definitions = await runQuery<ClientFieldDefinitionRow>(
        queryable,
        `select id, field_key, label, value_type, is_required,
           is_active, is_system, category_key, category_label, sort_order, width,
           placements, options, visible_on_lead, visible_on_student
         from app.client_custom_field_definitions
         where is_active = true and deleted_at is null
         order by sort_order, label`,
      );
      return {
        version: 0,
        snapshot: buildCrmConfigurationBaseline(definitions.rows),
      };
    }
    return {
      version: Number(row.version),
      snapshot: normalizeCrmConfigurationSnapshot(
        row.effective_snapshot as unknown as Record<string, unknown>,
      ),
    };
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
        if (!sameCrmConfigurationValue(next[key], school[key])) {
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
      current.fields.map((field) => [field.key, field]),
    );
    for (const [field, previous, following] of [
      [
        "lessonSettlementTypes",
        current.lessonSettlementTypes,
        next.lessonSettlementTypes,
      ],
      [
        "teacherCompensationRules",
        current.teacherCompensationRules,
        next.teacherCompensationRules,
      ],
    ] as const) {
      const nextKeys = new Set(following.map((item) => item.stableKey));
      for (const item of previous) {
        if (!nextKeys.has(item.stableKey)) {
          blockingIssues.push({
            field: `${field}.${item.stableKey}`,
            code: "CATALOG_KEY_REMOVAL_FORBIDDEN",
            message:
              "Стабильный ключ нельзя удалить или переименовать; архивируйте тип.",
          });
        }
      }
    }
    const nextFields = new Map(
      next.fields.map((field) => [field.key, field]),
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
      JSON.stringify(currentFields.get(field.key));
    const settings = new Map(
      current.businessSettings.map((setting) => [setting.key, setting.value]),
    );
    const settingsChanged = next.businessSettings.filter(
      (setting) => settings.get(setting.key) !== setting.value,
    ).length;
    const changedCatalogItems = <T extends { stableKey: string }>(
      following: T[],
      previous: T[],
    ) => {
      const previousByKey = new Map(
        previous.map((item) => [item.stableKey, item]),
      );
      return following.filter(
        (item) =>
          !sameCrmConfigurationValue(item, previousByKey.get(item.stableKey)),
      ).length;
    };
    const settlementTypesChanged = changedCatalogItems(
      next.lessonSettlementTypes,
      current.lessonSettlementTypes,
    );
    const compensationRulesChanged = changedCatalogItems(
      next.teacherCompensationRules,
      current.teacherCompensationRules,
    );
    const fieldChange =
      next.fields.some(changed) ||
      current.fields.some(
        (field) => !nextFields.has(field.key),
      );
    return {
      valid: blockingIssues.length === 0,
      blockingIssues,
      warnings: [
        ...(settingsChanged > 0
          ? ["Новые значения применятся только к будущим бизнес-снимкам."]
          : []),
        ...(settlementTypesChanged > 0 || compensationRulesChanged > 0
          ? [
              "Новые правила применятся только к будущим решениям; история сохранит прежние снимки.",
            ]
          : []),
      ],
      changes: {
        fieldsCreated: next.fields.filter(
          (field) => !currentFields.has(field.key),
        ).length,
        fieldsUpdated: next.fields.filter(
          (field) =>
            currentFields.has(field.key) && changed(field),
        ).length,
        fieldsArchived: current.fields.filter(
          (field) => !nextFields.has(field.key),
        ).length,
        settingsChanged,
        settlementTypesChanged,
        compensationRulesChanged,
      },
      affectedScreens: [
        ...(fieldChange
          ? ["lead.create", "student.create", "client.card.custom_fields"]
          : []),
        ...(settingsChanged
          ? ["schedule.lesson.create", "client.payments"]
          : []),
        ...(settlementTypesChanged > 0 ? ["schedule.lesson.decision"] : []),
        ...(compensationRulesChanged > 0 ? ["teacher.compensation"] : []),
      ],
    };
  }

  private async syncClientFields(client: PoolClient, snapshot: ConfigSnapshot) {
    const keys = snapshot.fields.map((field) => field.key);
    const categoryLabels = new Map(
      snapshot.categories.map((category) => [category.key, category.label]),
    );
    for (const field of snapshot.fields) {
      const result = await client.query<{ id: string }>(
        `insert into app.client_custom_field_definitions (
           field_key, label, value_type, is_required, is_active,
           is_system, options, category_key, category_label, sort_order, width,
           placements, visible_on_lead, visible_on_student
         ) values ($1, $2, $3, $4, $5, false, $6::jsonb, $7, $8, $9, $10,
           $11::jsonb, $12, $13)
         on conflict (field_key) do update set
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
           visible_on_lead = case
             when app.client_custom_field_definitions.is_system
               then app.client_custom_field_definitions.visible_on_lead
             else excluded.visible_on_lead end,
           visible_on_student = case
             when app.client_custom_field_definitions.is_system
               then app.client_custom_field_definitions.visible_on_student
             else excluded.visible_on_student end,
           version = app.client_custom_field_definitions.version + 1,
           updated_at = now()
         returning id`,
        [
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
          field.visibility.lead,
          field.visibility.student,
        ],
      );
      field.id = result.rows[0]!.id;
    }
    await client.query(
      `update app.client_custom_field_definitions definition
       set is_active = false, deleted_at = coalesce(deleted_at, now()),
         version = version + 1, updated_at = now()
       where not definition.is_system
         and not (definition.field_key = any($1::text[]))
         and definition.is_active`,
      [keys],
    );
    return snapshot;
  }

  private async assertCommerceCatalogAccess(
    queryable: Queryable,
    actor: ActorContext,
    next: ConfigSnapshot,
    current: ConfigSnapshot,
    lockForCommit = false,
  ): Promise<void> {
    if (
      sameCrmConfigurationValue(
        next.lessonSettlementTypes,
        current.lessonSettlementTypes,
      ) &&
      sameCrmConfigurationValue(
        next.teacherCompensationRules,
        current.teacherCompensationRules,
      )
    ) {
      return;
    }
    await authorizeCurrentCapability(
      queryable,
      actor,
      "config.commerce.manage",
      lockForCommit,
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

}
