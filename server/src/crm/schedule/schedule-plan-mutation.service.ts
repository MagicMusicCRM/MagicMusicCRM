import { Injectable } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import type {
  CreateSchedulePlanDto,
  SchedulePlanRowDto,
  UpdateSchedulePlanDto,
} from "../dto/schedule-plan.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { acquireLessonSettlementCoordinationGate } from "../commerce/lesson-settlement-locks";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { extendSchedulePlanBackwards } from "./schedule-plan-backdate-mutation";
import { moveSchedulePlanStartForward } from "./schedule-plan-forward-start-mutation";
import { lockSchedulePlanSeries } from "./schedule-locks";
import {
  type NormalizedSchedulePlanCreate,
  type PreparedSchedulePlanUpdate,
  SchedulePlanDefinitionService,
} from "./schedule-plan-definition.service";
import { assertSchedulePlanMetadata as assertMetadata } from "./schedule-plan-definition.service";
import { SchedulePlanConstraintPreviewService } from "./schedule-plan-constraint-preview.service";
import type { PreparedSchedulePlanRow } from "./schedule-plan-preview.types";
import type {
  SchedulePlanMutationReference as MutationReference,
  SchedulePlanMutationResult,
} from "./schedule-plan-mutation.types";
import { SchedulePlanRepository } from "./schedule-plan.repository";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

export type { SchedulePlanMutationResult } from "./schedule-plan-mutation.types";

@Injectable()
export class SchedulePlanMutationService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly repository: SchedulePlanRepository,
    private readonly series: LessonSeriesCommandService,
    private readonly materializer: ScheduleSeriesMaterializerService,
    private readonly definition: SchedulePlanDefinitionService,
    private readonly previews: SchedulePlanConstraintPreviewService,
  ) {}

  async create(
    actor: ActorContext,
    dto: CreateSchedulePlanDto,
    metadata: LessonCommandMetadata,
  ): Promise<SchedulePlanMutationResult> {
    this.policy.assertCanWriteCrm(actor);
    this.policy.assertCanSupplyTeacherCompensation(actor, dto.rows);
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
    this.policy.assertCanSupplyTeacherCompensation(actor, dto.rows);
    assertMetadata(metadata);
    this.definition.assertRows(dto.rows);
    let prepared: PreparedSchedulePlanUpdate | undefined;
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
      beforeVersionAdvance: async (client) => {
        await acquireLessonSettlementCoordinationGate(client);
        prepared = await this.definition.prepareUpdate(client, planId, dto);
      },
      mutate: (client, version) =>
        this.updateInTransaction(
          client,
          actor,
          planId,
          version,
          dto,
          prepared!,
        ),
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
    await this.series.assertPlanExpansionBounds(
      client,
      normalized.rows,
      normalized.activeFrom,
      normalized.activeUntil,
    );
    const preparedRows = await this.previews.prepareRows(
      client,
      actor,
      normalized.rows,
      studentIds,
    );
    const includePast = await this.previews.assertCreateHistoricalConfirmation(
      client,
      actor,
      normalized,
      dto,
      preparedRows,
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
      preparedRows,
    );
  }

  private async updateInTransaction(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    version: number,
    dto: UpdateSchedulePlanDto,
    prepared: PreparedSchedulePlanUpdate,
  ): Promise<MutationReference> {
    await this.series.assertPlanExpansionBounds(
      client,
      dto.rows,
      prepared.effectiveFrom,
      prepared.activeUntil,
    );
    const preparedRows = await this.previews.prepareRows(
      client,
      actor,
      dto.rows,
      prepared.studentIds,
      prepared,
    );
    const includePast = await this.previews.assertUpdateHistoricalConfirmation(
      client,
      actor,
      planId,
      dto,
      prepared,
      preparedRows,
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
        preparedRows,
        insertSeries: (input, preparedRow) =>
          this.insertSeries(client, input, preparedRow),
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
      preparedRows,
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
    preparedRows: PreparedSchedulePlanRow[],
  ): Promise<MutationReference> {
    const seriesIds: string[] = [];
    const lessonIds: string[] = [];
    for (const [index, preparedRow] of preparedRows.entries()) {
      const row = preparedRow.row;
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
        preparedRow,
      );
      await this.materializer.materializePlanSeries(client, seriesId, {
        includePast,
        deferPlanReservations: true,
      });
      seriesIds.push(seriesId);
      lessonIds.push(...(await this.definition.lessonIds(client, seriesId)));
    }
    await this.materializer.allocatePlanReservations(client, lessonIds);
    return { planId, seriesIds, lessonIds };
  }

  private async insertContinuations(
    client: PoolClient,
    actor: ActorContext,
    planId: string,
    version: number,
    rows: SchedulePlanRowDto[],
    prepared: PreparedSchedulePlanUpdate,
    preparedRows: PreparedSchedulePlanRow[],
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
          row: preparedRows[index]!.row,
          actorUserId: actor.userId,
          version,
          subscriptionId: prepared.subscriptionId,
        },
        preparedRows[index]!,
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
    preparedRow: PreparedSchedulePlanRow,
  ) {
    await this.repository.insertSeries(client, {
      ...input,
      row: preparedRow.row,
      settlementPlan: preparedRow.settlementPlan,
    });
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
    for (const [index] of rows.entries()) {
      const seriesId = seriesIds[index]!;
      await this.materializer.materializePlanSeries(client, seriesId, {
        includePast,
        deferPlanReservations: true,
        replaceableLineageDates: replaceableDates.get(seriesId) ?? [],
      });
      lessonIds.push(...(await this.definition.lessonIds(client, seriesId)));
    }
    await this.materializer.allocatePlanReservations(client, lessonIds);
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
