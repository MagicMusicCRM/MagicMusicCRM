import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import {
  ClientPipelineType,
  PreviewClientPipelineDto,
  PublishClientPipelineDto,
  PublishStudentFunnelDto,
  RollbackClientPipelineDto,
  RollbackStudentFunnelDto,
} from "../dto/student-funnel.dto";
import {
  applyPatch,
  assertStableKeys,
  diffFromSchool,
  normalizeStages,
  toFunnelRevisionDto,
} from "./student-funnel.definition";
import { StudentFunnelRepository } from "./student-funnel.repository";
import { StudentFunnelResolverService } from "./student-funnel-resolver.service";
import {
  FunnelPatch,
  FunnelRevisionDto,
  FunnelRevisionRow,
  FunnelSnapshot,
} from "./student-funnel.types";

@Injectable()
export class StudentFunnelRevisionService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
    private readonly repository: StudentFunnelRepository,
    private readonly resolver: StudentFunnelResolverService,
  ) {}

  async preview(actor: ActorContext, dto: PreviewClientPipelineDto) {
    this.policy.assertCanManageClientConfiguration(actor);
    const stages = normalizeStages(dto.stages);
    const current = await this.resolver.resolveEffective(
      this.database,
      dto.branchId,
      dto.clientType,
    );
    const scopeVersion = dto.branchId
      ? current.branchVersion
      : current.schoolVersion;
    if (scopeVersion !== dto.expectedVersion) {
      throw new ConflictException({
        code: "CLIENT_PIPELINE_VERSION_CONFLICT",
        currentVersion: scopeVersion,
        message: "Воронка уже изменена в другой вкладке.",
      });
    }
    const previous = new Map(current.stages.map((stage) => [stage.key, stage]));
    const nextKeys = new Set(stages.map((stage) => stage.key));
    const missing = current.stages.filter((stage) => !nextKeys.has(stage.key));
    const archived = stages.filter(
      (stage) => previous.get(stage.key)?.active === true && !stage.active,
    );
    return {
      valid: missing.length === 0,
      changes: {
        created: stages.filter((stage) => !previous.has(stage.key)).length,
        updated: stages.filter(
          (stage) =>
            previous.has(stage.key) &&
            JSON.stringify(previous.get(stage.key)) !== JSON.stringify(stage),
        ).length,
        archived: archived.length,
      },
      affectedClients: await this.repository.countClients(
        dto.clientType,
        dto.branchId,
        archived.map((stage) => stage.key),
      ),
      blockingIssues: missing.map((stage) => ({
        code: "CLIENT_PIPELINE_STAGE_DELETE_FORBIDDEN",
        stageKey: stage.key,
        message: `Стадию «${stage.label}» можно архивировать, но нельзя удалить.`,
      })),
    };
  }

  async publish(
    actor: ActorContext,
    dto: PublishStudentFunnelDto | PublishClientPipelineDto,
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    const result = await this.publishRevision(actor, dto, null);
    await this.afterPublish(
      actor,
      result,
      dto.reason,
      "clientType" in dto ? dto.clientType : "student",
    );
    return result;
  }

  async rollback(
    actor: ActorContext,
    dto: RollbackStudentFunnelDto | RollbackClientPipelineDto,
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    const clientType: ClientPipelineType =
      "clientType" in dto ? dto.clientType : "student";
    const revision = await this.repository.findRevision(
      dto.branchId,
      clientType,
      dto.targetVersion,
    );
    if (!revision) throw new NotFoundException("Версия воронки не найдена.");
    const targetSnapshot = dto.branchId
      ? applyPatch(
          (await this.resolver.resolveSchool(this.database, clientType)).stages,
          revision.patch as FunnelPatch,
        )
      : revision.effective_snapshot.stages;
    const current = await this.resolver.resolveEffective(
      this.database,
      dto.branchId,
      clientType,
    );
    const targetKeys = new Set(targetSnapshot.map((stage) => stage.key));
    const targetStages = [
      ...targetSnapshot,
      ...current.stages
        .filter((stage) => !targetKeys.has(stage.key))
        .map((stage) => ({
          ...stage,
          active: false,
          allowedTransitions: [],
        })),
    ];
    const result = await this.publishRevision(
      actor,
      {
        branchId: dto.branchId,
        clientType,
        expectedVersion: dto.expectedVersion,
        reason: dto.reason,
        stages: targetStages,
      },
      dto.targetVersion,
    );
    await this.afterPublish(actor, result, dto.reason, clientType);
    return result;
  }

  private async publishRevision(
    actor: ActorContext,
    dto: PublishStudentFunnelDto | PublishClientPipelineDto,
    rollbackFromVersion: number | null,
  ) {
    const clientType: ClientPipelineType =
      "clientType" in dto ? dto.clientType : "student";
    const stages = normalizeStages(dto.stages);
    const reason = dto.reason.trim();
    if (!reason) {
      throw new UnprocessableEntityException({
        code: "CLIENT_PIPELINE_REASON_REQUIRED",
        field: "reason",
        message: "Укажите причину публикации.",
      });
    }
    return this.database.transaction(async (client) => {
      if (dto.branchId) {
        await this.repository.assertBranch(client, dto.branchId);
      }
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [`client-pipeline:${clientType}:${dto.branchId ?? "school"}`],
      );
      const current = await this.repository.latestRevision(
        client,
        dto.branchId ?? null,
        clientType,
        true,
      );
      const currentVersion = Number(current?.version ?? 0);
      if (currentVersion !== dto.expectedVersion) {
        throw new ConflictException({
          code: "CLIENT_PIPELINE_VERSION_CONFLICT",
          currentVersion,
          message: "Воронка уже изменена в другой вкладке.",
        });
      }

      const school = dto.branchId
        ? await this.resolver.resolveSchool(client, clientType)
        : (current?.effective_snapshot ?? { stages: [] });
      const previousStages =
        dto.branchId && current
          ? applyPatch(school.stages, current.patch as FunnelPatch)
          : (current?.effective_snapshot.stages ?? school.stages);
      assertStableKeys(previousStages, stages);
      const patch: FunnelPatch | FunnelSnapshot = dto.branchId
        ? diffFromSchool(school.stages, stages)
        : { stages };
      const version = currentVersion + 1;
      if (clientType === "lead") {
        await this.syncLeadStatuses(client, stages, dto.branchId === undefined);
      }
      const inserted = await client.query<FunnelRevisionRow>(
        `
          insert into app.student_funnel_revisions (
            client_type,
            branch_id,
            version,
            patch,
            effective_snapshot,
            reason,
            rollback_from_version,
            created_by
          )
          values ($1, $2, $3, $4::jsonb, $5::jsonb, $6, $7, $8)
          returning id, client_type, branch_id, version, patch, effective_snapshot, reason,
            rollback_from_version, created_by, created_at
        `,
        [
          clientType,
          dto.branchId ?? null,
          version,
          JSON.stringify(patch),
          JSON.stringify({ stages }),
          reason,
          rollbackFromVersion,
          actor.userId,
        ],
      );
      return toFunnelRevisionDto(inserted.rows[0]!);
    });
  }

  private async syncLeadStatuses(
    client: PoolClient,
    stages: PublishClientPipelineDto["stages"],
    schoolScope: boolean,
  ) {
    if (schoolScope) {
      await client.query(
        `
          update app.lead_statuses
          set name = '__pipeline_sync__' || stage_key
          where stage_key = any($1::text[])
        `,
        [stages.map((stage) => stage.key)],
      );
    }
    for (const [sortOrder, stage] of stages.entries()) {
      await client.query(
        `
          insert into app.lead_statuses (
            stage_key, name, color, sort_order, is_terminal, requires_reason
          )
          values ($1, $2, $3, $4, $5, $6)
          on conflict (stage_key) do update
          set name = excluded.name,
              color = excluded.color,
              sort_order = excluded.sort_order,
              is_terminal = excluded.is_terminal,
              requires_reason = excluded.requires_reason
          where $7::boolean
        `,
        [
          stage.key,
          stage.label,
          stage.style,
          sortOrder,
          stage.terminal === true,
          stage.requiresReason === true,
          schoolScope,
        ],
      );
    }
  }

  private async afterPublish(
    actor: ActorContext,
    result: FunnelRevisionDto,
    reason: string,
    clientType: ClientPipelineType,
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    await this.audit.record({
      actor,
      action: "crm.client_pipeline_published",
      entityType: "client_pipeline_revision",
      entityId: result.id,
      metadata: {
        branchId: result.branchId,
        clientType,
        version: result.version,
        reason,
      },
    });
    this.realtime.emitCrmChanged({
      entity: clientType,
      action: "updated",
      id: result.branchId ?? "school",
    });
  }
}
