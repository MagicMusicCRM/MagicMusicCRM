import { Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import type { LessonSettlementService } from "../commerce/lesson-settlement.service";
import type { CrmPolicy } from "../crm.policy";
import type {
  CreateSchedulePlanDto,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import type { LessonSeriesCommandService } from "./lesson-series-command.service";
import { lockSchedulePlanSeries } from "./schedule-locks";
import type {
  NormalizedSchedulePlanCreate,
  PreparedSchedulePlanUpdate,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import { failSchedulePlan } from "./schedule-plan-definition.service";
import type { SchedulePlanRepository } from "./schedule-plan.repository";
import type { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

export interface SchedulePlanMutationResult {
  id: string;
  seriesIds: string[];
  lessonIds: string[];
  version: number;
  replayed: boolean;
}

const assertMetadata = (metadata: LessonCommandMetadata) => {
  if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
    failSchedulePlan("IDEMPOTENCY_KEY_REQUIRED", ["Idempotency-Key"]);
  }
  if (!metadata.requestId || metadata.requestId.length > 160) {
    failSchedulePlan("REQUEST_ID_REQUIRED", ["X-Request-Id"]);
  }
};

interface MutationReference extends Record<string, unknown> {
  planId: string;
  seriesIds: string[];
  lessonIds: string[];
}

@Injectable()
export class SchedulePlanMutationService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly repository: SchedulePlanRepository,
    private readonly series: LessonSeriesCommandService,
    private readonly materializer: ScheduleSeriesMaterializerService,
    private readonly settlement: LessonSettlementService,
    private readonly definition: SchedulePlanDefinitionService,
  ) {}

  async create(
    actor: ActorContext,
    dto: CreateSchedulePlanDto,
    metadata: LessonCommandMetadata,
  ): Promise<SchedulePlanMutationResult> {
    this.policy.assertCanWriteCrm(actor);
    assertMetadata(metadata);
    const normalized = this.definition.normalizeCreate(dto);
    const planId = this.definition.planId(
      actor.userId,
      metadata.idempotencyKey,
    );
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: "schedule.plan.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: normalized,
      aggregateType: "schedule:plan",
      aggregateId: planId,
      expectedVersion: 0,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_plan_created",
        entityType: "schedule_plan",
        entityId: planId,
      },
      outbox: {
        type: "schedule.plan.changed",
        payload: { entityId: planId, state: "created" },
      },
      mutate: (client, version) =>
        this.createInTransaction(
          client,
          actor.userId,
          planId,
          version,
          normalized,
        ),
    });
    return this.result(
      planId,
      mutation.version,
      mutation.replayed,
      mutation.resultRef,
    );
  }

  async update(
    actor: ActorContext,
    planId: string,
    dto: UpdateSchedulePlanDto,
    metadata: LessonCommandMetadata,
  ): Promise<SchedulePlanMutationResult> {
    this.policy.assertCanWriteCrm(actor);
    assertMetadata(metadata);
    this.definition.assertRows(dto.rows);
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "schedule.lesson.write" },
      operation: "schedule.plan.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:plan",
      aggregateId: planId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_plan_updated",
        entityType: "schedule_plan",
        entityId: planId,
      },
      outbox: {
        type: "schedule.plan.changed",
        payload: { entityId: planId, state: "updated" },
      },
      mutate: (client, version) =>
        this.updateInTransaction(client, actor.userId, planId, version, dto),
    });
    return this.result(
      planId,
      mutation.version,
      mutation.replayed,
      mutation.resultRef,
    );
  }

  private async createInTransaction(
    client: PoolClient,
    actorUserId: string,
    planId: string,
    version: number,
    normalized: NormalizedSchedulePlanCreate,
  ): Promise<MutationReference> {
    const studentIds =
      normalized.kind === "individual"
        ? [normalized.studentId!]
        : normalized.participants.map((participant) => participant.studentId);
    await this.definition.lockAndValidate(client, {
      planId,
      kind: normalized.kind,
      studentId: normalized.studentId,
      groupId: normalized.groupId,
      subscriptionId: normalized.subscriptionId,
      participants: normalized.participants,
      rows: normalized.rows,
    });
    await this.repository.insertPlan(client, {
      id: planId,
      kind: normalized.kind,
      title: normalized.title,
      studentId: normalized.studentId,
      groupId: normalized.groupId,
      subscriptionId: normalized.subscriptionId,
      activeFrom: normalized.activeFrom,
      activeUntil: normalized.activeUntil,
      actorUserId,
      version,
    });
    if (normalized.kind === "group") {
      await this.repository.insertParticipants(
        client,
        planId,
        normalized.participants,
        normalized.activeFrom,
        normalized.activeUntil,
        version,
      );
    }
    return this.insertAndMaterializeRows(
      client,
      actorUserId,
      planId,
      version,
      normalized,
      studentIds,
    );
  }

  private async updateInTransaction(
    client: PoolClient,
    actorUserId: string,
    planId: string,
    version: number,
    dto: UpdateSchedulePlanDto,
  ): Promise<MutationReference> {
    const prepared = await this.definition.prepareUpdate(client, planId, dto);
    await lockSchedulePlanSeries(
      client,
      prepared.activeSeries.map((series) => series.id),
    );
    const seriesIds = await this.insertContinuations(
      client,
      actorUserId,
      planId,
      version,
      dto.rows,
      prepared,
    );
    await this.retirePreviousSeries(client, prepared, dto.rows, seriesIds);
    await this.replaceParticipants(client, planId, version, prepared);
    await this.repository.updatePlan(client, {
      planId,
      title: dto.title?.trim() || prepared.plan.title,
      subscriptionId: prepared.subscriptionId,
      activeUntil: prepared.activeUntil,
      version,
    });
    const lessonIds = await this.validateAndMaterialize(
      client,
      dto.rows,
      seriesIds,
      prepared,
    );
    return { planId, seriesIds, lessonIds };
  }

  private async insertAndMaterializeRows(
    client: PoolClient,
    actorUserId: string,
    planId: string,
    version: number,
    normalized: NormalizedSchedulePlanCreate,
    studentIds: string[],
  ): Promise<MutationReference> {
    const seriesIds: string[] = [];
    const lessonIds: string[] = [];
    for (const [index, row] of normalized.rows.entries()) {
      await this.series.validatePlanRow(
        client,
        row,
        normalized.activeFrom,
        normalized.activeUntil,
        studentIds,
      );
      const seriesId = this.definition.seriesId(planId, version, index);
      await this.insertSeries(client, {
        id: seriesId,
        planId,
        studentId: normalized.studentId,
        groupId: normalized.groupId,
        validFrom: normalized.activeFrom,
        validUntil: normalized.activeUntil,
        row,
        actorUserId,
        version,
      });
      await this.materializer.materializePlanSeries(client, seriesId);
      seriesIds.push(seriesId);
      lessonIds.push(...(await this.definition.lessonIds(client, seriesId)));
    }
    return { planId, seriesIds, lessonIds };
  }

  private async insertContinuations(
    client: PoolClient,
    actorUserId: string,
    planId: string,
    version: number,
    rows: SchedulePlanRowDto[],
    prepared: PreparedSchedulePlanUpdate,
  ) {
    const seriesIds: string[] = [];
    for (const [index, row] of rows.entries()) {
      const seriesId = this.definition.seriesId(planId, version, index);
      await this.insertSeries(client, {
        id: seriesId,
        planId,
        studentId: prepared.plan.student_id,
        groupId: prepared.plan.group_id,
        validFrom: prepared.effectiveFrom,
        validUntil: prepared.activeUntil,
        row,
        actorUserId,
        version,
      });
      seriesIds.push(seriesId);
    }
    return seriesIds;
  }

  private async insertSeries(
    client: PoolClient,
    input: Omit<
      Parameters<SchedulePlanRepository["insertSeries"]>[1],
      "settlementPlan"
    >,
  ) {
    const settlementPlan = await this.settlement.preparePlan(
      client,
      input.row.branchId,
      input.row.financialDecision,
    );
    await this.repository.insertSeries(client, { ...input, settlementPlan });
  }

  private async retirePreviousSeries(
    client: PoolClient,
    prepared: PreparedSchedulePlanUpdate,
    rows: SchedulePlanRowDto[],
    seriesIds: string[],
  ) {
    const continuations = new Map<string, string>();
    rows.forEach((row, index) => {
      if (row.seriesId) continuations.set(row.seriesId, seriesIds[index]!);
    });
    for (const old of prepared.activeSeries) {
      await this.repository.retireSeries(
        client,
        old.id,
        prepared.effectiveFrom,
        continuations.get(old.id) ?? null,
      );
    }
  }

  private async replaceParticipants(
    client: PoolClient,
    planId: string,
    version: number,
    prepared: PreparedSchedulePlanUpdate,
  ) {
    if (prepared.plan.kind !== "group") return;
    await this.repository.replaceParticipants(
      client,
      planId,
      prepared.participants,
      prepared.effectiveFrom,
      prepared.activeUntil,
      version,
    );
  }

  private async validateAndMaterialize(
    client: PoolClient,
    rows: SchedulePlanRowDto[],
    seriesIds: string[],
    prepared: PreparedSchedulePlanUpdate,
  ) {
    const lessonIds: string[] = [];
    for (const [index, row] of rows.entries()) {
      await this.series.validatePlanRow(
        client,
        row,
        prepared.effectiveFrom,
        prepared.activeUntil,
        prepared.studentIds,
      );
      const seriesId = seriesIds[index]!;
      await this.materializer.materializePlanSeries(client, seriesId);
      lessonIds.push(...(await this.definition.lessonIds(client, seriesId)));
    }
    return lessonIds;
  }

  private result(
    planId: string,
    version: number,
    replayed: boolean,
    resultRef: Record<string, unknown>,
  ): SchedulePlanMutationResult {
    return {
      id: planId,
      seriesIds: resultRef.seriesIds as string[],
      lessonIds: resultRef.lessonIds as string[],
      version,
      replayed,
    };
  }
}
