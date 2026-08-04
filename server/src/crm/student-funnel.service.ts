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
  PublishStudentFunnelDto,
  RollbackStudentFunnelDto,
  StudentFunnelStageDto,
} from "./dto/student-funnel.dto";

export interface FunnelSnapshot {
  stages: StudentFunnelStageDto[];
}

export interface FunnelPatch {
  order?: string[];
  stages?: Record<string, StudentFunnelStageDto>;
}

interface FunnelRevisionRow {
  id: string;
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

  async getEffective(actor: ActorContext, branchId?: string) {
    this.policy.assertCanReadOperationalData(actor);
    const effective = await this.resolveEffective(this.database, branchId);
    const keys = effective.stages.map((stage) => stage.key);
    const unknown = actor.role === "teacher"
      ? []
      : (
          await this.database.query<{
            status: string;
            count: string | number;
          }>(
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
    return {
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

  async listRevisions(actor: ActorContext, branchId?: string) {
    this.policy.assertCanManageClientConfiguration(actor);
    const result = await this.database.query<FunnelRevisionRow>(
      `
        select id, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where branch_id is not distinct from $1::uuid
        order by version desc
        limit 50
      `,
      [branchId ?? null],
    );
    return { items: result.rows.map((row) => this.revisionDto(row)) };
  }

  async publish(actor: ActorContext, dto: PublishStudentFunnelDto) {
    this.policy.assertCanManageClientConfiguration(actor);
    const result = await this.publishRevision(actor, dto, null);
    await this.afterPublish(actor, result, dto.reason);
    return result;
  }

  async rollback(actor: ActorContext, dto: RollbackStudentFunnelDto) {
    this.policy.assertCanManageClientConfiguration(actor);
    const target = await this.database.query<FunnelRevisionRow>(
      `
        select id, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where branch_id is not distinct from $1::uuid
          and version = $2
        limit 1
      `,
      [dto.branchId ?? null, dto.targetVersion],
    );
    const revision = target.rows[0];
    if (!revision) throw new NotFoundException("Версия воронки не найдена.");
    const targetSnapshot = dto.branchId
      ? this.applyPatch(
          (await this.resolveSchool(this.database)).stages,
          revision.patch as FunnelPatch,
        )
      : revision.effective_snapshot.stages;
    const current = await this.resolveEffective(
      this.database,
      dto.branchId,
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
        expectedVersion: dto.expectedVersion,
        reason: dto.reason,
        stages: targetStages,
      },
      dto.targetVersion,
    );
    await this.afterPublish(actor, result, dto.reason);
    return result;
  }

  async assertCreateStatus(
    client: PoolClient,
    branchId: string | null,
    status: string,
  ): Promise<void> {
    const effective = await this.resolveEffective(client, branchId ?? undefined);
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
    const effective = await this.resolveEffective(client, branchId ?? undefined);
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

  private async publishRevision(
    actor: ActorContext,
    dto: PublishStudentFunnelDto,
    rollbackFromVersion: number | null,
  ) {
    const stages = this.normalizeStages(dto.stages);
    const reason = dto.reason.trim();
    if (!reason) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_REASON_REQUIRED",
        field: "reason",
        message: "Укажите причину публикации.",
      });
    }
    return this.database.transaction(async (client) => {
      if (dto.branchId) await this.assertBranch(client, dto.branchId);
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [`student-funnel:${dto.branchId ?? "school"}`],
      );
      const current = await this.latestRevision(
        client,
        dto.branchId ?? null,
        true,
      );
      const currentVersion = Number(current?.version ?? 0);
      if (currentVersion !== dto.expectedVersion) {
        throw new ConflictException({
          code: "STUDENT_FUNNEL_VERSION_CONFLICT",
          currentVersion,
          message: "Воронка уже изменена в другой вкладке.",
        });
      }

      const school = dto.branchId
        ? await this.resolveSchool(client)
        : current?.effective_snapshot;
      if (!school) throw new NotFoundException("Школьная воронка не найдена.");
      const previousStages = dto.branchId && current
        ? this.applyPatch(school.stages, current.patch as FunnelPatch)
        : current?.effective_snapshot.stages ?? school.stages;
      this.assertStableKeys(
        previousStages,
        stages,
      );
      const patch: FunnelPatch | FunnelSnapshot = dto.branchId
        ? this.diffFromSchool(school.stages, stages)
        : { stages };
      const version = currentVersion + 1;
      const inserted = await client.query<FunnelRevisionRow>(
        `
          insert into app.student_funnel_revisions (
            branch_id,
            version,
            patch,
            effective_snapshot,
            reason,
            rollback_from_version,
            created_by
          )
          values ($1, $2, $3::jsonb, $4::jsonb, $5, $6, $7)
          returning id, branch_id, version, patch, effective_snapshot, reason,
            rollback_from_version, created_by, created_at
        `,
        [
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

  private async resolveEffective(queryable: Queryable, branchId?: string) {
    if (branchId) await this.assertBranch(queryable, branchId);
    const school = await this.latestRevision(queryable, null, false);
    if (!school) throw new NotFoundException("Школьная воронка не настроена.");
    const schoolStages = this.normalizeStages(
      school.effective_snapshot.stages,
    );
    if (!branchId) {
      return {
        stages: schoolStages,
        schoolVersion: Number(school.version),
        branchVersion: 0,
      };
    }
    const branch = await this.latestRevision(queryable, branchId, false);
    return {
      stages: branch
        ? this.applyPatch(schoolStages, branch.patch as FunnelPatch)
        : schoolStages,
      schoolVersion: Number(school.version),
      branchVersion: Number(branch?.version ?? 0),
    };
  }

  private async resolveSchool(queryable: Queryable): Promise<FunnelSnapshot> {
    const revision = await this.latestRevision(queryable, null, false);
    if (!revision) throw new NotFoundException("Школьная воронка не настроена.");
    return { stages: this.normalizeStages(revision.effective_snapshot.stages) };
  }

  private async latestRevision(
    queryable: Queryable,
    branchId: string | null,
    lock: boolean,
  ): Promise<FunnelRevisionRow | null> {
    const result = await runQuery<FunnelRevisionRow>(
      queryable,
      `
        select id, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where branch_id is not distinct from $1::uuid
        order by version desc
        limit 1
        ${lock ? "for update" : ""}
      `,
      [branchId],
    );
    return result.rows[0] ?? null;
  }

  private normalizeStages(rawStages: StudentFunnelStageDto[]) {
    if (!Array.isArray(rawStages) || rawStages.length === 0) {
      throw new UnprocessableEntityException("Добавьте хотя бы одну стадию.");
    }
    const keys = new Set<string>();
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
      keys.add(key);
      return {
        key,
        label,
        style: raw.style,
        active: raw.active === true,
        allowedTransitions: [
          ...new Set((raw.allowedTransitions ?? []).map((value) => value.trim())),
        ].filter((value) => value !== key),
      } satisfies StudentFunnelStageDto;
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
    previous: StudentFunnelStageDto[],
    next: StudentFunnelStageDto[],
  ) {
    const nextKeys = new Set(next.map((stage) => stage.key));
    const missing = previous.find((stage) => !nextKeys.has(stage.key));
    if (missing) {
      throw new UnprocessableEntityException({
        code: "STUDENT_FUNNEL_STAGE_DELETE_FORBIDDEN",
        field: "stages",
        message: `Стадию «${missing.label}» можно архивировать, но нельзя удалить из истории.`,
      });
    }
  }

  private diffFromSchool(
    school: StudentFunnelStageDto[],
    desired: StudentFunnelStageDto[],
  ): FunnelPatch {
    const base = new Map(school.map((stage) => [stage.key, stage]));
    const stages: Record<string, StudentFunnelStageDto> = {};
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
    school: StudentFunnelStageDto[],
    patch: FunnelPatch,
  ): StudentFunnelStageDto[] {
    const byKey = new Map(
      school.map((stage) => [stage.key, { ...stage }]),
    );
    for (const [key, stage] of Object.entries(patch.stages ?? {})) {
      byKey.set(key, stage);
    }
    const order = patch.order ?? school.map((stage) => stage.key);
    const ordered = order
      .map((key) => byKey.get(key))
      .filter((stage): stage is StudentFunnelStageDto => stage !== undefined);
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

  private revisionDto(row: FunnelRevisionRow) {
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
      stages: row.effective_snapshot.stages,
      patch: row.patch,
    };
  }

  private async afterPublish(
    actor: ActorContext,
    result: ReturnType<StudentFunnelService["revisionDto"]>,
    reason: string,
  ) {
    this.policy.assertCanManageClientConfiguration(actor);
    await this.audit.record({
      actor,
      action: "crm.student_funnel_published",
      entityType: "student_funnel_revision",
      entityId: result.id,
      metadata: {
        branchId: result.branchId,
        version: result.version,
        reason,
      },
    });
    this.realtime.emitCrmChanged({
      entity: "student",
      action: "updated",
      id: result.branchId ?? "school",
    });
  }
}
