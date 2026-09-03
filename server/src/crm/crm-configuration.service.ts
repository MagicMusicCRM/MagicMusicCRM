import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import {
  applyCrmConfigurationBranchPatch,
  createCrmConfigurationBranchPatch,
  getCrmConfigurationSettingSources,
  sameCrmConfigurationValue,
} from "./crm-configuration-branch.policy";
import type {
  ConfigBranchPatch,
  ConfigSnapshot,
} from "./crm-configuration.contracts";
import { buildCrmConfigurationImpact } from "./crm-configuration-impact.policy";
import {
  assertCrmConfigurationBranch,
  crmConfigurationRevisionDto,
  type CrmConfigurationRevisionRow,
  hasStoredCrmClientFieldValues,
  resolveEffectiveCrmConfiguration,
  resolveSchoolCrmConfiguration,
  syncCrmClientFields,
} from "./crm-configuration-persistence";
import { normalizeCrmConfigurationSnapshot } from "./crm-configuration-snapshot-normalizer";
import { CrmPolicy } from "./crm.policy";
import {
  PublishCrmConfigurationDto,
  RollbackCrmConfigurationDto,
  SaveCrmConfigurationDraftDto,
} from "./dto/crm-configuration.dto";

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
    const effective = await resolveEffectiveCrmConfiguration(
      this.database,
      branchId,
    );
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
      await assertCrmConfigurationBranch(this.database, branchId);
    }
    const effective = await resolveEffectiveCrmConfiguration(
      this.database,
      branchId,
    );
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
    const effective = await resolveEffectiveCrmConfiguration(
      this.database,
      branchId,
    );
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
    const current = await resolveEffectiveCrmConfiguration(
      this.database,
      dto.branchId,
    );
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
    this.assertSystemOwnedCatalogUnchanged(current.snapshot, snapshot);
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
    const effective = await resolveEffectiveCrmConfiguration(
      this.database,
      dto.branchId,
    );
    this.assertSystemOwnedCatalogUnchanged(effective.snapshot, snapshot);
    return buildCrmConfigurationImpact({
      next: snapshot,
      current: effective.snapshot,
      school: dto.branchId ? effective.schoolSnapshot : undefined,
      hasStoredClientFieldValues: (definitionId) =>
        hasStoredCrmClientFieldValues(this.database, definitionId),
    });
  }

  async publish(actor: ActorContext, dto: PublishCrmConfigurationDto) {
    await this.assertScope(actor, dto.branchId);
    return this.publishRevision(actor, dto, null);
  }

  async listRevisions(actor: ActorContext, branchId?: string) {
    await this.assertScope(actor, branchId);
    const result = await this.database.query<CrmConfigurationRevisionRow>(
      `select id, branch_id, version, patch, effective_snapshot, impact,
         reason, rollback_from_version, created_by, created_at
       from app.crm_configuration_revisions
       where branch_id is not distinct from $1::uuid
       order by version desc limit 50`,
      [branchId ?? null],
    );
    return { items: result.rows.map(crmConfigurationRevisionDto) };
  }

  async rollback(actor: ActorContext, dto: RollbackCrmConfigurationDto) {
    await this.assertScope(actor, dto.branchId);
    const target = await this.database.query<CrmConfigurationRevisionRow>(
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
          (await resolveSchoolCrmConfiguration(this.database)).snapshot,
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
       if (dto.branchId) {
         await assertCrmConfigurationBranch(client, dto.branchId);
       }
       const effective = await resolveEffectiveCrmConfiguration(
         client,
         dto.branchId,
       );
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
      this.assertSystemOwnedCatalogUnchanged(effective.snapshot, requested);
      const impact = await buildCrmConfigurationImpact({
        next: requested,
        current: effective.snapshot,
        school: dto.branchId ? effective.schoolSnapshot : undefined,
        hasStoredClientFieldValues: (definitionId) =>
           hasStoredCrmClientFieldValues(client, definitionId),
      });
      if (!impact.valid) {
        throw new UnprocessableEntityException({
          code: "CONFIGURATION_INVALID",
          message: "Исправьте блокирующие ошибки перед публикацией.",
          impact,
        });
      }
      const snapshot = dto.branchId
        ? requested
         : await syncCrmClientFields(client, requested);
      const nextVersion = currentVersion + 1;
      const patch = dto.branchId
        ? createCrmConfigurationBranchPatch(effective.schoolSnapshot, snapshot)
        : snapshot;
       const inserted = await client.query<CrmConfigurationRevisionRow>(
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
    const revision = crmConfigurationRevisionDto(result.row);
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
      if (branchId) {
        await assertCrmConfigurationBranch(this.database, branchId);
      }
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

  private assertSystemOwnedCatalogUnchanged(
    current: ConfigSnapshot,
    next: ConfigSnapshot,
  ): void {
    if (
      sameCrmConfigurationValue(
        current.lessonSettlementTypes,
        next.lessonSettlementTypes,
      ) &&
      sameCrmConfigurationValue(
        current.teacherCompensationRules,
        next.teacherCompensationRules,
      )
    ) {
      return;
    }
    throw new ForbiddenException({
      code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY",
    });
  }

}
