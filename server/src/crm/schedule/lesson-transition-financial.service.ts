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
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import {
  stableTransitionId,
  targetTransitionState,
} from "./lesson-transition.rules";
import type {
  TransitionOperation,
  ResolvedTransitionDto,
  ResolvedRescheduleTransitionDto,
  TransitionSource,
} from "./lesson-transition.types";

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
      await client.query(
        "update app.lessons set lifecycle_state = $2 where id = $1",
        [lessonId, targetTransitionState(operation)],
      );
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
    if (!source.branchId || source.lifecycleState !== "successfully_completed") {
      throw new ConflictException({
        code: "COMPLETED_LESSON_RESCHEDULE_NOT_ALLOWED",
        lessonId: source.id,
      });
    }
    const reasonText = dto.reasonText?.trim();
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
        JSON.stringify(dto.sourceFinancialDecision),
        dto.sourceConfigurationRevisionIds.settlementRevisionId,
        dto.sourceConfigurationRevisionIds.compensationRevisionId,
        reasonText,
        actor.userId,
      ],
    );
    return this.settlement.settle(client, source.id, {
      context: "settle",
      decision: dto.sourceFinancialDecision,
      reasonText,
      configurationRevisionIds: {
        settlementRevisionId:
          dto.sourceConfigurationRevisionIds.settlementRevisionId,
        compensationRevisionId:
          dto.sourceConfigurationRevisionIds.compensationRevisionId,
      },
      correction: { id: correctionId },
    });
  }

  async assignAndAllocateSuccessor(
    client: PoolClient,
    successorId: string,
    actor: ActorContext,
    reasonText: string | undefined,
    decision: LessonFinancialDecision,
    configurationRevisionIds: {
      settlementRevisionId: string;
      compensationRevisionId: string;
    },
  ): Promise<void> {
    const plan = await this.settlement.assignPreparedPlan(client, {
      lessonId: successorId,
      selectedBy: actor.userId,
      reasonText,
      decision,
      ...configurationRevisionIds,
    });
    const allocations = await this.settlement.plannedSubscriptionAllocations(
      client,
      successorId,
      plan,
    );
    for (const allocation of allocations) {
      await this.reservations.allocate(client, {
        lessonId: successorId,
        chargeType: "subscription",
        ...allocation,
      });
    }
  }
}
