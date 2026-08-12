import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import {
  ClientPipelineStageDto,
  ClientPipelineType,
  PreviewClientPipelineDto,
  PublishClientPipelineDto,
  PublishStudentFunnelDto,
  RollbackClientPipelineDto,
  RollbackStudentFunnelDto,
} from "./dto/student-funnel.dto";

export interface FunnelSnapshot {
  stages: ClientPipelineStageDto[];
}

export interface FunnelPatch {
  order?: string[];
  stages?: Record<string, ClientPipelineStageDto>;
}

interface FunnelRevisionRow {
  id: string;
  client_type: ClientPipelineType;
  branch_id: string | null;
  version: string | number;
  patch: FunnelPatch | FunnelSnapshot;
  effective_snapshot: FunnelSnapshot;
  reason: string;
  rollback_from_version: string | number | null;
  created_by: string | null;
  created_at: Date | string;
}

type Queryable = Pick<PoolClient, "query"> | DatabaseService;

function runQuery<T extends QueryResultRow>(
  queryable: Queryable,
  text: string,
  params: unknown[],
): Promise<QueryResult<T>> {
  return (
    queryable.query as (
      query: string,
      values?: unknown[],
    ) => Promise<QueryResult<T>>
  )(text, params);
}

@Injectable()
export class StudentFunnelService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  async getEffective(
    actor: ActorContext,
    branchId?: string,
    clientType: ClientPipelineType = "student",
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const effective = await this.resolveEffective(
      this.database,
      branchId,
      clientType,
    );
    const keys = effective.stages.map((stage) => stage.key);
    const unknown =
      actor.role === "teacher"
        ? []
        : await this.remediationRows(clientType, branchId, keys);
    return {
      clientType,
      branchId: branchId ?? null,
      source: effective.branchVersion > 0 ? "branch_override" : "school",
      schoolVersion: effective.schoolVersion,
      branchVersion: effective.branchVersion,
      stages: effective.stages,
      remediationStatuses: unknown.map((row) => ({
        key: row.status,
        count: Number(row.count),
      })),
    };
  }

  async listRevisions(
    actor: ActorContext,
    branchId?: string,
    clientType: ClientPipelineType = "student",
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    const result = await this.database.query<FunnelRevisionRow>(
      `
        select id, client_type, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where client_type = $1
          and branch_id is not distinct from $2::uuid
        order by version desc
        limit 50
      `,
      [clientType, branchId ?? null],
    );
    return { items: result.rows.map((row) => this.revisionDto(row)) };
  }

  async preview(actor: ActorContext, dto: PreviewClientPipelineDto) {
    this.policy.assertCanManageClientConfiguration(actor);
    const stages = this.normalizeStages(dto.stages);
    const current = await this.resolveEffective(
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
      affectedClients: await this.countClients(
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
    const target = await this.database.query<FunnelRevisionRow>(
      `
        select id, client_type, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where client_type = $1
          and branch_id is not distinct from $2::uuid
          and version = $3
        limit 1
      `,
      [clientType, dto.branchId ?? null, dto.targetVersion],
    );
    const revision = target.rows[0];
    if (!revision) throw new NotFoundException("Версия воронки не найдена.");
    const targetSnapshot = dto.branchId
      ? this.applyPatch(
          (await this.resolveSchool(this.database, clientType)).stages,
          revision.patch as FunnelPatch,
        )
      : revision.effective_snapshot.stages;
    const current = await this.resolveEffective(
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

  async assertCreateStatus(
    client: PoolClient,
    branchId: string | null,
    status: string,
  ): Promise<void> {
    const effective = await this.resolveEffective(
      client,
      branchId ?? undefined,
      "student",
    );
    const target = effective.stages.find((stage) => stage.key === status);
    if (!target?.active) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_STAGE_UNAVAILABLE",
        field: "status",
        message: "Выбранная стадия ученика недоступна в этом филиале.",
      });
    }
  }

  async assertTransition(
    client: PoolClient,
    branchId: string | null,
    currentStatus: string | null,
    nextStatus: string,
  ): Promise<void> {
    const effective = await this.resolveEffective(
      client,
      branchId ?? undefined,
      "student",
    );
    const next = effective.stages.find((stage) => stage.key === nextStatus);
    if (!next?.active) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_STAGE_UNAVAILABLE",
        field: "status",
        message: "Целевая стадия архивирована или не настроена.",
      });
    }
    if (currentStatus === nextStatus) return;
    const current = effective.stages.find(
      (stage) => stage.key === currentStatus,
    );
    // Unknown legacy values are an explicit remediation bucket. Moving out of
    // it into an active configured stage is the only permitted transition.
    if (!current) return;
    if (!current.allowedTransitions.includes(nextStatus)) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_TRANSITION_DENIED",
        field: "status",
        message: `Переход «${current.label}» → «${next.label}» запрещён настройками воронки.`,
      });
    }
  }

  async assertLeadTransition(
    client: PoolClient,
    branchId: string | null,
    currentStatusId: string | null,
    nextStatusId: string,
    hasReason = false,
  ): Promise<void> {
    const statusIds = currentStatusId
      ? [currentStatusId, nextStatusId]
      : [nextStatusId];
    const rows = await client.query<{ id: string; stage_key: string }>(
      `select id, stage_key from app.lead_statuses where id = any($1::uuid[])`,
      [statusIds],
    );
    const keyById = new Map(rows.rows.map((row) => [row.id, row.stage_key]));
    const nextKey = keyById.get(nextStatusId);
    if (!nextKey) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_STAGE_UNAVAILABLE",
        field: "statusId",
        message: "Выбранная стадия лида не настроена.",
      });
    }
    const effective = await this.resolveEffective(
      client,
      branchId ?? undefined,
      "lead",
    );
    const next = effective.stages.find((stage) => stage.key === nextKey);
    if (!next?.active) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_STAGE_UNAVAILABLE",
        field: "statusId",
        message: "Целевая стадия лида архивирована или недоступна.",
      });
    }
    if (currentStatusId === null || currentStatusId === nextStatusId) return;
    const currentKey = keyById.get(currentStatusId);
    const current = effective.stages.find((stage) => stage.key === currentKey);
    if (current && !current.allowedTransitions.includes(nextKey)) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_TRANSITION_DENIED",
        field: "statusId",
        message: `Переход «${current.label}» → «${next.label}» запрещён настройками воронки.`,
      });
    }
    if (next.requiresReason && !hasReason) {
      throw new UnprocessableEntityException({
        code: "LEAD_PIPELINE_REASON_REQUIRED",
        field: "reasonId",
        message: `Для перехода на стадию «${next.label}» укажите причину.`,
      });
    }
  }

  private async publishRevision(
    actor: ActorContext,
    dto: PublishStudentFunnelDto | PublishClientPipelineDto,
    rollbackFromVersion: number | null,
  ) {
    const clientType: ClientPipelineType =
      "clientType" in dto ? dto.clientType : "student";
    const stages = this.normalizeStages(dto.stages);
    const reason = dto.reason.trim();
    if (!reason) {
      throw new UnprocessableEntityException({
        code: "CLIENT_PIPELINE_REASON_REQUIRED",
        field: "reason",
        message: "Укажите причину публикации.",
      });
    }
    return this.database.transaction(async (client) => {
      if (dto.branchId) await this.assertBranch(client, dto.branchId);
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [`client-pipeline:${clientType}:${dto.branchId ?? "school"}`],
      );
      const current = await this.latestRevision(
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
        ? await this.resolveSchool(client, clientType)
        : (current?.effective_snapshot ?? { stages: [] });
      const previousStages =
        dto.branchId && current
          ? this.applyPatch(school.stages, current.patch as FunnelPatch)
          : (current?.effective_snapshot.stages ?? school.stages);
      this.assertStableKeys(previousStages, stages);
      const patch: FunnelPatch | FunnelSnapshot = dto.branchId
        ? this.diffFromSchool(school.stages, stages)
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
      return this.revisionDto(inserted.rows[0]!);
    });
  }

  private async resolveEffective(
    queryable: Queryable,
    branchId: string | undefined,
    clientType: ClientPipelineType,
  ) {
    if (branchId) await this.assertBranch(queryable, branchId);
    const school = await this.latestRevision(
      queryable,
      null,
      clientType,
      false,
    );
    if (!school) {
      if (branchId) {
        throw new NotFoundException("Сначала настройте школьную воронку.");
      }
      return {
        stages: [] as ClientPipelineStageDto[],
        schoolVersion: 0,
        branchVersion: 0,
      };
    }
    const schoolStages = this.normalizeStages(school.effective_snapshot.stages);
    if (!branchId) {
      return {
        stages: schoolStages,
        schoolVersion: Number(school.version),
        branchVersion: 0,
      };
    }
    const branch = await this.latestRevision(
      queryable,
      branchId,
      clientType,
      false,
    );
    return {
      stages: branch
        ? this.applyPatch(schoolStages, branch.patch as FunnelPatch)
        : schoolStages,
      schoolVersion: Number(school.version),
      branchVersion: Number(branch?.version ?? 0),
    };
  }

  private async resolveSchool(
    queryable: Queryable,
    clientType: ClientPipelineType,
  ): Promise<FunnelSnapshot> {
    const revision = await this.latestRevision(
      queryable,
      null,
      clientType,
      false,
    );
    if (!revision)
      throw new NotFoundException("Школьная воронка не настроена.");
    return { stages: this.normalizeStages(revision.effective_snapshot.stages) };
  }

  private async latestRevision(
    queryable: Queryable,
    branchId: string | null,
    clientType: ClientPipelineType,
    lock: boolean,
  ): Promise<FunnelRevisionRow | null> {
    const result = await runQuery<FunnelRevisionRow>(
      queryable,
      `
        select id, client_type, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where client_type = $1
          and branch_id is not distinct from $2::uuid
        order by version desc
        limit 1
        ${lock ? "for update" : ""}
      `,
      [clientType, branchId],
    );
    return result.rows[0] ?? null;
  }

  private normalizeStages(rawStages: ClientPipelineStageDto[]) {
    if (!Array.isArray(rawStages) || rawStages.length === 0) {
      throw new UnprocessableEntityException("Добавьте хотя бы одну стадию.");
    }
    const keys = new Set<string>();
    const labels = new Set<string>();
    const stages = rawStages.map((raw) => {
      const key = raw.key?.trim().toLowerCase();
      const label = raw.label?.trim();
      if (!key || !/^[a-z][a-z0-9_-]{0,63}$/.test(key) || keys.has(key)) {
        throw new UnprocessableEntityException({
          code: "STUDENT_FUNNEL_STAGE_KEY_INVALID",
          field: "stages.key",
          message: "Ключи стадий должны быть уникальными.",
        });
      }
      if (!label || label.length > 80) {
        throw new UnprocessableEntityException({
          code: "STUDENT_FUNNEL_STAGE_LABEL_INVALID",
          field: "stages.label",
          message: "Укажите название стадии.",
        });
      }
      const normalizedLabel = label.toLocaleLowerCase("ru");
      if (labels.has(normalizedLabel)) {
        throw new UnprocessableEntityException({
          code: "CLIENT_PIPELINE_STAGE_LABEL_DUPLICATE",
          field: "stages.label",
          message: "Названия стадий должны быть уникальными.",
        });
      }
      keys.add(key);
      labels.add(normalizedLabel);
      return {
        key,
        label,
        style: raw.style,
        active: raw.active === true,
        terminal: raw.terminal === true,
        requiresReason: raw.requiresReason === true,
        allowedTransitions: [
          ...new Set(
            (raw.allowedTransitions ?? []).map((value) => value.trim()),
          ),
        ].filter((value) => value !== key),
      } satisfies ClientPipelineStageDto;
    });
    if (!stages.some((stage) => stage.active)) {
      throw new UnprocessableEntityException(
        "В воронке должна остаться хотя бы одна активная стадия.",
      );
    }
    for (const stage of stages) {
      for (const target of stage.allowedTransitions) {
        if (!keys.has(target)) {
          throw new UnprocessableEntityException({
            code: "STUDENT_FUNNEL_TRANSITION_TARGET_INVALID",
            field: "stages.allowedTransitions",
            message: `Стадия «${stage.label}» ссылается на неизвестный переход.`,
          });
        }
      }
    }
    return stages;
  }

  private assertStableKeys(
    previous: ClientPipelineStageDto[],
    next: ClientPipelineStageDto[],
  ) {
    const nextKeys = new Set(next.map((stage) => stage.key));
    const missing = previous.find((stage) => !nextKeys.has(stage.key));
    if (missing) {
      throw new UnprocessableEntityException({
        code: "CLIENT_PIPELINE_STAGE_DELETE_FORBIDDEN",
        field: "stages",
        message: `Стадию «${missing.label}» можно архивировать, но нельзя удалить из истории.`,
      });
    }
  }

  private diffFromSchool(
    school: ClientPipelineStageDto[],
    desired: ClientPipelineStageDto[],
  ): FunnelPatch {
    const base = new Map(school.map((stage) => [stage.key, stage]));
    const stages: Record<string, ClientPipelineStageDto> = {};
    for (const stage of desired) {
      if (JSON.stringify(base.get(stage.key)) !== JSON.stringify(stage)) {
        stages[stage.key] = stage;
      }
    }
    const schoolOrder = school.map((stage) => stage.key);
    const desiredOrder = desired.map((stage) => stage.key);
    return {
      ...(JSON.stringify(schoolOrder) === JSON.stringify(desiredOrder)
        ? {}
        : { order: desiredOrder }),
      ...(Object.keys(stages).length === 0 ? {} : { stages }),
    };
  }

  private applyPatch(
    school: ClientPipelineStageDto[],
    patch: FunnelPatch,
  ): ClientPipelineStageDto[] {
    const byKey = new Map(school.map((stage) => [stage.key, { ...stage }]));
    for (const [key, stage] of Object.entries(patch.stages ?? {})) {
      byKey.set(key, stage);
    }
    const order = patch.order ?? school.map((stage) => stage.key);
    const ordered = order
      .map((key) => byKey.get(key))
      .filter((stage): stage is ClientPipelineStageDto => stage !== undefined);
    for (const [key, stage] of byKey) {
      if (!order.includes(key)) ordered.push(stage);
    }
    return this.normalizeStages(ordered);
  }

  private async assertBranch(queryable: Queryable, branchId: string) {
    const result = await runQuery<{ present: boolean }>(
      queryable,
      "select exists (select 1 from app.branches where id = $1 and deleted_at is null) as present",
      [branchId],
    );
    if (result.rows[0]?.present !== true) {
      throw new NotFoundException("Филиал не найден.");
    }
  }

  private async remediationRows(
    clientType: ClientPipelineType,
    branchId: string | undefined,
    keys: string[],
  ) {
    if (clientType === "lead") {
      return (
        await this.database.query<{ status: string; count: string | number }>(
          `
            select coalesce(status.stage_key, '__empty__') as status,
              count(*) as count
            from app.leads lead
            left join app.lead_statuses status on status.id = lead.status_id
            where lead.deleted_at is null
              and ($1::uuid is null or lead.branch_id = $1)
              and not (coalesce(status.stage_key, '__empty__') = any($2::text[]))
            group by coalesce(status.stage_key, '__empty__')
            order by count(*) desc, status asc
          `,
          [branchId ?? null, keys],
        )
      ).rows;
    }
    return (
      await this.database.query<{ status: string; count: string | number }>(
        `
          select coalesce(nullif(btrim(status), ''), '__empty__') as status,
            count(*) as count
          from app.students
          where deleted_at is null
            and ($1::uuid is null or branch_id = $1)
            and not (coalesce(nullif(btrim(status), ''), '__empty__') = any($2::text[]))
          group by coalesce(nullif(btrim(status), ''), '__empty__')
          order by count(*) desc, status asc
        `,
        [branchId ?? null, keys],
      )
    ).rows;
  }

  private async countClients(
    clientType: ClientPipelineType,
    branchId: string | undefined,
    stageKeys: string[],
  ): Promise<number> {
    if (stageKeys.length === 0) return 0;
    const result =
      clientType === "lead"
        ? await this.database.query<{ count: string | number }>(
            `
            select count(*) as count
            from app.leads lead
            join app.lead_statuses status on status.id = lead.status_id
            where lead.deleted_at is null
              and ($1::uuid is null or lead.branch_id = $1)
              and status.stage_key = any($2::text[])
          `,
            [branchId ?? null, stageKeys],
          )
        : await this.database.query<{ count: string | number }>(
            `
            select count(*) as count
            from app.students
            where deleted_at is null
              and ($1::uuid is null or branch_id = $1)
              and status = any($2::text[])
          `,
            [branchId ?? null, stageKeys],
          );
    return Number(result.rows[0]?.count ?? 0);
  }

  private async syncLeadStatuses(
    client: PoolClient,
    stages: ClientPipelineStageDto[],
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

  private revisionDto(row: FunnelRevisionRow) {
    return {
      id: row.id,
      clientType: row.client_type,
      branchId: row.branch_id,
      version: Number(row.version),
      reason: row.reason,
      rollbackFromVersion:
        row.rollback_from_version === null
          ? null
          : Number(row.rollback_from_version),
      createdBy: row.created_by,
      createdAt: row.created_at,
      stages: row.effective_snapshot.stages,
      patch: row.patch,
    };
  }

  private async afterPublish(
    actor: ActorContext,
    result: ReturnType<StudentFunnelService["revisionDto"]>,
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
