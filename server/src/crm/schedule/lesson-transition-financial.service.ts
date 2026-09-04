import {
  ConflictException,
  Inject,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import {
  LESSON_SETTLEMENT_PORT,
  type LessonFinancialDecision,
  type LessonSettlementPort,
  type LessonSettlementResult,
} from "../commerce/lesson-settlement.port";
import {
  type LessonSettlementCoverageSnapshot,
  SubscriptionReservationService,
} from "../commerce/subscription-reservation.service";
import {
  stableTransitionId,
  targetTransitionState,
} from "./lesson-transition.rules";
import type {
  PreparedRescheduleFinancials,
  TransitionOperation,
  ResolvedTransitionDto,
  ResolvedRescheduleTransitionDto,
  TransitionSource,
} from "./lesson-transition.types";

type ConfigurationRevisionIds = {
  settlementRevisionId: string;
  compensationRevisionId: string;
};

export interface RescheduleFinancialCommitInput
  extends PreparedRescheduleFinancials {
  actor: ActorContext;
  reasonText?: string;
  sourceConfigurationRevisionIds: ConfigurationRevisionIds;
  successorConfigurationRevisionIds: ConfigurationRevisionIds;
  coverage: LessonSettlementCoverageSnapshot;
  correctionId: string;
}

export interface CommittedRescheduleFinancials {
  sourceSettlement: LessonSettlementResult;
  successorPlanId: string;
  transferredReservationId: string | null;
}

@Injectable()
export class LessonTransitionFinancialService {
  constructor(
    @Inject(LESSON_SETTLEMENT_PORT)
    private readonly settlement: LessonSettlementPort,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  async previewFinancial(
    client: PoolClient,
    actor: ActorContext,
    source: TransitionSource,
    lessonId: string,
    operation: TransitionOperation,
    dto: ResolvedTransitionDto,
  ): Promise<LessonSettlementResult> {
    await client.query("savepoint lesson_transition_preview");
    try {
      if (source.lifecycleState === "successfully_completed") {
        if (dto.operation !== "reschedule") {
          throw new ConflictException({
            code: "COMPLETED_LESSON_RESCHEDULE_NOT_ALLOWED",
            lessonId: source.id,
          });
        }
        return await this.applyCompletedRescheduleCorrection(
          client,
          source,
          actor,
          dto,
          stableTransitionId(
            `schedule.lesson.completed-reschedule-preview\0${lessonId}\0${source.version}`,
          ),
        );
      }
      if (operation !== "reschedule") {
        await client.query(
          "update app.lessons set lifecycle_state = $2 where id = $1",
          [lessonId, targetTransitionState(operation)],
        );
      }
      const sourceDecision = dto.operation === "reschedule"
        ? dto.sourceFinancialDecision
        : dto.financialDecision;
      const sourceConfigurationRevisionIds = dto.operation === "reschedule"
        ? dto.sourceConfigurationRevisionIds
        : dto.configurationRevisionIds;
      const settled = await this.settlement.settle(client, lessonId, {
        context: operation,
        decision: sourceDecision,
        reasonText: dto.reasonText?.trim(),
        configurationRevisionIds: sourceConfigurationRevisionIds,
      });
      await this.reservations.terminalize(client, settled);
      return settled;
    } finally {
      await client.query("rollback to savepoint lesson_transition_preview");
      await client.query("release savepoint lesson_transition_preview");
    }
  }

  async applyCompletedRescheduleCorrection(
    client: PoolClient,
    source: TransitionSource,
    actor: ActorContext,
    dto: ResolvedRescheduleTransitionDto,
    correctionId: string,
  ): Promise<LessonSettlementResult> {
    return this.correctCompletedSource(
      client,
      source,
      actor,
      dto.sourceFinancialDecision,
      dto.sourceConfigurationRevisionIds,
      dto.reasonText,
      correctionId,
    );
  }

  private async correctCompletedSource(
    client: PoolClient,
    source: TransitionSource,
    actor: ActorContext,
    sourceFinancialDecision: LessonFinancialDecision,
    sourceConfigurationRevisionIds: ConfigurationRevisionIds,
    reason: string | undefined,
    correctionId: string,
  ): Promise<LessonSettlementResult> {
    if (!source.branchId || source.lifecycleState !== "successfully_completed") {
      throw new ConflictException({
        code: "COMPLETED_LESSON_RESCHEDULE_NOT_ALLOWED",
        lessonId: source.id,
      });
    }
    const reasonText = reason?.trim();
    if (!reasonText) {
      throw new UnprocessableEntityException({
        code: "LESSON_TRANSITION_REASON_REQUIRED",
        fields: ["reasonText"],
      });
    }
    const previous = await client.query<{ id: string; version: number | string }>(
      `select id, version from app.lesson_settlement_corrections
       where lesson_id = $1 order by version desc limit 1 for update`,
      [source.id],
    );
    await client.query(
      `insert into app.lesson_settlement_corrections (
         id, lesson_id, version, supersedes_correction_id, decision,
         settlement_revision_id, compensation_revision_id,
         reason_text, actor_user_id
       ) values ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9)`,
      [
        correctionId,
        source.id,
        Number(previous.rows[0]?.version ?? 0) + 1,
        previous.rows[0]?.id ?? null,
        JSON.stringify(sourceFinancialDecision),
        sourceConfigurationRevisionIds.settlementRevisionId,
        sourceConfigurationRevisionIds.compensationRevisionId,
        reasonText,
        actor.userId,
      ],
    );
    return this.settlement.settle(client, source.id, {
      context: "settle",
      decision: sourceFinancialDecision,
      reasonText,
      configurationRevisionIds: sourceConfigurationRevisionIds,
      correction: { id: correctionId },
    });
  }

  async commitRescheduleFinancials(
    client: PoolClient,
    source: TransitionSource,
    successorId: string,
    financials: RescheduleFinancialCommitInput,
  ): Promise<CommittedRescheduleFinancials> {
    let sourceSettlement: LessonSettlementResult;
    if (source.lifecycleState === "successfully_completed") {
      sourceSettlement = await this.correctCompletedSource(
        client,
        source,
        financials.actor,
        financials.sourceFinancialDecision,
        financials.sourceConfigurationRevisionIds,
        financials.reasonText,
        financials.correctionId,
      );
    } else {
      sourceSettlement = await this.settlement.settle(client, source.id, {
        context: "reschedule",
        decision: financials.sourceFinancialDecision,
        reasonText: financials.reasonText?.trim(),
        configurationRevisionIds: financials.sourceConfigurationRevisionIds,
      });
    }
    const plan = await this.settlement.assignPreparedPlan(client, {
      lessonId: successorId,
      selectedBy: financials.actor.userId,
      reasonText: financials.reasonText,
      decision: financials.successorFinancialDecision,
      ...financials.successorConfigurationRevisionIds,
    });
    const allocations = await this.settlement.plannedSubscriptionAllocations(
      client,
      successorId,
      plan,
    );
    const transferredIds = new Set<string>();
    let transferredReservationId: string | null = null;
    for (const allocation of allocations) {
      const transferable = financials.coverage.reservations.find(
        (reservation) =>
          reservation.state === "reserved" &&
          reservation.subscriptionId === allocation.subscriptionId &&
          !transferredIds.has(reservation.id),
      );
      if (transferable) {
        const transferred = await this.reservations.transferActiveReservation(
          client,
          {
            reservationId: transferable.id,
            sourceLessonId: source.id,
            successorLessonId: successorId,
            subscriptionId: allocation.subscriptionId,
            units: allocation.units,
          },
        );
        if (transferred) {
          transferredIds.add(transferred);
          transferredReservationId ??= transferred;
          continue;
        }
      }
      await this.reservations.allocate(client, {
        lessonId: successorId,
        chargeType: "subscription",
        ...allocation,
      });
    }
    await this.reservations.releaseForLessons(client, [source.id]);
    return {
      sourceSettlement,
      successorPlanId: successorId,
      transferredReservationId,
    };
  }
}
