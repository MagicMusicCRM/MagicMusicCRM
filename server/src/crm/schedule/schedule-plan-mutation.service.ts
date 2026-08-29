import { Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { CrmPolicy } from "../crm.policy";
import type {
  CreateSchedulePlanDto,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { extendSchedulePlanBackwards } from "./schedule-plan-backdate-mutation";
import { moveSchedulePlanStartForward } from "./schedule-plan-forward-start-mutation";
import { lockSchedulePlanSeries } from "./schedule-locks";
import {
  type NormalizedSchedulePlanCreate,
  type PreparedSchedulePlanUpdate,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import { failSchedulePlan } from "./schedule-plan-definition.service";
import { SchedulePlanConstraintPreviewService } from "./schedule-plan-constraint-preview.service";
import { SchedulePlanRepository } from "./schedule-plan.repository";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

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
    private readonly previews: SchedulePlanConstraintPreviewService,
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
      authorization:
        this.policy.teacherCompensationMutationAuthorization(actor),
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
          actor,
          planId,
          version,
          normalized,
          dto,
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
      authorization:
        this.policy.teacherCompensationMutationAuthorization(actor),
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
        this.updateInTransaction(client, actor, planId, version, dto),
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
    actor: ActorContext,
    planId: string,
    version: number,
    normalized: NormalizedSchedulePlanCreate,
    dto: CreateSchedulePlanDto,
  ): Promise<MutationReference> {
    const actorUserId = actor.userId;
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
    const includePast = await this.previews.assertCreateHistoricalConfirmation(
      client,
      actor,
      normalized,
      dto,
    );
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
      actor,
      planId,
      version,
      normalized,
      studentIds,
      includePast,
    );
  }

  private async updateInTransaction(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    version: number,
    dto: UpdateSchedulePlanDto,
  ): Promise<MutationReference> {
    const prepared = await this.definition.prepareUpdate(client, planId, dto);
    const includePast = await this.previews.assertUpdateHistoricalConfirmation(
      client,
      actor,
      planId,
      dto,
      prepared,
    );
    if (prepared.mode === "extend_backwards") {
      return extendSchedulePlanBackwards({
        client,
        actor,
        planId,
        version,
        dto,
        prepared,
        repository: this.repository,
        series: this.series,
        materializer: this.materializer,
        definition: this.definition,
        insertSeries: (input, storedDecision) =>
          this.insertSeries(client, input, actor, storedDecision),
      });
    }
    await lockSchedulePlanSeries(
      client,
      prepared.activeSeries.map((series) => series.id),
    );
    if (prepared.mode === "move_start_forward") {
      return moveSchedulePlanStartForward({
        client,
        planId,
        version,
        prepared,
        repository: this.repository,
        definition: this.definition,
      });
    }
    if (prepared.plan.kind === "individual" && prepared.plan.subscription_id) {
      await this.repository.freezeActiveSeriesSubscription(
        client,
        prepared.activeSeries.map((series) => series.id),
        prepared.plan.subscription_id,
      );
    }
    await this.repository.updatePlan(client, {
      planId,
      title: dto.title?.trim() || prepared.plan.title,
      subscriptionId: prepared.subscriptionId,
      activeFrom: prepared.plan.active_from,
      activeUntil: prepared.activeUntil,
      version,
    });
    const seriesIds = await this.insertContinuations(
      client,
      actor,
      planId,
      version,
      dto.rows,
      prepared,
    );
    const replaceableDates = await this.retirePreviousSeries(
      client,
      prepared,
      dto.rows,
      seriesIds,
    );
    await this.replaceParticipants(client, planId, version, prepared);
    const lessonIds = await this.validateAndMaterialize(
      client,
      dto.rows,
      seriesIds,
      prepared,
      includePast,
      replaceableDates,
    );
    return { planId, seriesIds, lessonIds };
  }

  private async insertAndMaterializeRows(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    version: number,
    normalized: NormalizedSchedulePlanCreate,
    studentIds: string[],
    includePast: boolean,
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
        includePast,
      );
      const seriesId = this.definition.seriesId(planId, version, index);
      await this.insertSeries(
        client,
        {
          id: seriesId,
          planId,
          studentId: normalized.studentId,
          groupId: normalized.groupId,
          validFrom: normalized.activeFrom,
          validUntil: normalized.activeUntil,
          row,
          actorUserId: actor.userId,
          version,
          subscriptionId: normalized.subscriptionId,
        },
        actor,
      );
      await this.materializer.materializePlanSeries(client, seriesId, {
        includePast,
      });
      seriesIds.push(seriesId);
      lessonIds.push(...(await this.definition.lessonIds(client, seriesId)));
    }
    return { planId, seriesIds, lessonIds };
  }

  private async insertContinuations(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    version: number,
    rows: SchedulePlanRowDto[],
    prepared: PreparedSchedulePlanUpdate,
  ) {
    const seriesIds: string[] = [];
    for (const [index, row] of rows.entries()) {
      const seriesId = this.definition.seriesId(planId, version, index);
      await this.insertSeries(
        client,
        {
          id: seriesId,
          planId,
          studentId: prepared.plan.student_id,
          groupId: prepared.plan.group_id,
          validFrom: prepared.effectiveFrom,
          validUntil: prepared.activeUntil,
          row,
          actorUserId: actor.userId,
          version,
          subscriptionId: prepared.subscriptionId,
        },
        actor,
        prepared.activeSeries.find((series) => series.id === row.seriesId)
          ?.planned_financial_decision ?? null,
      );
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
    actor: ActorContext,
    storedDecision: SchedulePlanRowDto["financialDecision"] | null = null,
  ) {
    const financialDecision = await this.authorizedFinancialDecision(
      client,
      actor,
      input.row,
      storedDecision,
    );
    const settlementPlan = await this.settlement.preparePlan(
      client,
      input.row.branchId,
      financialDecision,
    );
    await this.repository.insertSeries(client, {
      ...input,
      row: { ...input.row, financialDecision },
      settlementPlan,
    });
  }

  private authorizedFinancialDecision(
    client: PoolClient,
    actor: ActorContext,
    row: SchedulePlanRowDto,
    storedDecision: SchedulePlanRowDto["financialDecision"] | null,
  ) {
    if (this.policy.canManageTeacherCompensation(actor)) {
      return Promise.resolve(row.financialDecision);
    }
    if (storedDecision) {
      return Promise.resolve({
        ...row.financialDecision,
        teacherCompensationRuleKey: storedDecision.teacherCompensationRuleKey,
        teacherCompensationValueMinor:
          storedDecision.teacherCompensationValueMinor,
      });
    }
    return this.settlement.applyDefaultTeacherCompensation(
      client,
      row.branchId,
      row.financialDecision,
    );
  }

  private async retirePreviousSeries(
    client: PoolClient,
    prepared: PreparedSchedulePlanUpdate,
    rows: SchedulePlanRowDto[],
    seriesIds: string[],
  ) {
    const continuations = new Map<string, string>();
    const replaceableDates = new Map<string, string[]>();
    rows.forEach((row, index) => {
      if (row.seriesId) continuations.set(row.seriesId, seriesIds[index]!);
    });
    for (const old of prepared.activeSeries) {
      const continuationId = continuations.get(old.id) ?? null;
      const removedDates = await this.repository.retireSeries(
        client,
        old.id,
        prepared.effectiveFrom,
        continuationId,
      );
      if (continuationId) replaceableDates.set(continuationId, removedDates);
    }
    return replaceableDates;
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
    includePast: boolean,
    replaceableDates: Map<string, string[]>,
  ) {
    const lessonIds: string[] = [];
    for (const [index, row] of rows.entries()) {
      await this.series.validatePlanRow(
        client,
        row,
        prepared.effectiveFrom,
        prepared.activeUntil,
        prepared.studentIds,
        includePast,
      );
      const seriesId = seriesIds[index]!;
      await this.materializer.materializePlanSeries(client, seriesId, {
        includePast,
        replaceableLineageDates: replaceableDates.get(seriesId) ?? [],
      });
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
