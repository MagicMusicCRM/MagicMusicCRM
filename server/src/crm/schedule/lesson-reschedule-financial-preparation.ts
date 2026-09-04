import { ConflictException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type {
  LessonFinancialDecision,
  LessonSettlementPort,
} from "../commerce/lesson-settlement.port";
import type { CrmPolicy } from "../crm.policy";
import {
  requiredTransitionClientIds,
  serverOwnedRescheduleSourceDecision,
  transitionDecisionForResolution,
} from "./lesson-transition.rules";
import type {
  CalculatedTransitionPreview,
  PlannedSettlementProjection,
  PreparedRescheduleFinancials,
  ResolvedRescheduleTransitionDto,
  ResolvedTransitionDto,
  TransitionFinancialProjection,
  TransitionOperation,
  NormalizedReschedulePreview,
  TransitionSource,
  TransitionSuccessor,
} from "./lesson-transition.types";

type ConfigurationRevisionIds = {
  settlementRevisionId: string;
  compensationRevisionId: string;
};

export interface PreparedRescheduleFinancialPlans
  extends PreparedRescheduleFinancials {
  sourceConfigurationRevisionIds: ConfigurationRevisionIds;
  successorConfigurationRevisionIds: ConfigurationRevisionIds;
}

const successorClientIds = (successor: TransitionSuccessor): string[] =>
  successor.kind === "individual"
    ? [successor.clientRef.id]
    : [...new Set(successor.participants.map(({ studentId }) => studentId))]
      .sort();

const resolvedDecision = async (
  client: PoolClient,
  actor: ActorContext,
  policy: CrmPolicy,
  settlement: LessonSettlementPort,
  input: {
    branchId: string;
    durationMinutes: number;
    decision: LessonFinancialDecision;
    reasonText?: string;
    requiredClientIds: string[];
    preservedTeacherDecision?: Parameters<
      LessonSettlementPort["resolvePlannedPlan"]
    >[1]["preservedTeacherDecision"];
  },
) => {
  const prepared = await settlement.resolvePlannedPlan(client, {
    ...input,
    actorUserId: actor.userId,
    authorization: policy.teacherCompensationMutationAuthorization(actor),
  });
  const teacherCompensationSource = prepared.decision.teacherCompensationSource;
  if (!teacherCompensationSource) {
    throw new ConflictException({
      code: "TEACHER_COMPENSATION_SOURCE_UNRESOLVED",
    });
  }
  return {
    decision: { ...prepared.decision, teacherCompensationSource },
    configurationRevisionIds: {
      settlementRevisionId: prepared.settlementRevisionId,
      compensationRevisionId: prepared.compensationRevisionId,
    },
  };
};

export async function prepareRescheduleFinancialPlans(
  client: PoolClient,
  actor: ActorContext,
  policy: CrmPolicy,
  settlement: LessonSettlementPort,
  source: TransitionSource,
  successor: TransitionSuccessor,
  successorFinancialDecision: LessonFinancialDecision,
  reasonText: string | undefined,
  preservedTeacherDecision?: Parameters<
    LessonSettlementPort["resolvePlannedPlan"]
  >[1]["preservedTeacherDecision"],
): Promise<PreparedRescheduleFinancialPlans> {
  const sourcePlan = await resolvedDecision(client, actor, policy, settlement, {
    branchId: source.branchId!,
    durationMinutes: source.durationMinutes,
    decision: serverOwnedRescheduleSourceDecision(
      requiredTransitionClientIds(source),
    ),
    reasonText,
    requiredClientIds: requiredTransitionClientIds(source),
  });
  const successorPlan = await resolvedDecision(client, actor, policy, settlement, {
    branchId: successor.branchId,
    durationMinutes: successor.durationMinutes,
    decision: transitionDecisionForResolution(
      successorFinancialDecision,
      Boolean(preservedTeacherDecision),
    ),
    reasonText,
    requiredClientIds: successorClientIds(successor),
    ...(preservedTeacherDecision ? { preservedTeacherDecision } : {}),
  });
  return {
    sourceFinancialDecision: sourcePlan.decision,
    successorFinancialDecision: successorPlan.decision,
    sourceConfigurationRevisionIds: sourcePlan.configurationRevisionIds,
    successorConfigurationRevisionIds: successorPlan.configurationRevisionIds,
  };
}

export async function prepareResolvedRescheduleTransition(
  client: PoolClient,
  actor: ActorContext,
  policy: CrmPolicy,
  settlement: LessonSettlementPort,
  source: TransitionSource,
  successor: TransitionSuccessor,
  dto: NormalizedReschedulePreview,
  preservedTeacherDecision?: Parameters<
    LessonSettlementPort["resolvePlannedPlan"]
  >[1]["preservedTeacherDecision"],
): Promise<ResolvedRescheduleTransitionDto> {
  const prepared = await prepareRescheduleFinancialPlans(
    client,
    actor,
    policy,
    settlement,
    source,
    successor,
    dto.successorFinancialDecision,
    dto.reasonText,
    preservedTeacherDecision,
  );
  return {
    ...dto,
    operation: "reschedule",
    ...prepared,
  };
}

export const previewDecisionProjection = (
  _operation: TransitionOperation,
  dto: ResolvedTransitionDto,
): Pick<
  CalculatedTransitionPreview,
  "financialDecision" | "sourceFinancialDecision" | "successorFinancialDecision"
> => dto.operation === "reschedule"
  ? {
      sourceFinancialDecision: dto.sourceFinancialDecision,
      successorFinancialDecision: dto.successorFinancialDecision,
    }
  : { financialDecision: dto.financialDecision };

export const previewFinancialProjection = (
  operation: TransitionOperation,
  sourceFinancialPreview: TransitionFinancialProjection,
  successorPlannedSettlementPreview: PlannedSettlementProjection,
) => operation === "reschedule"
  ? { sourceFinancialPreview, successorPlannedSettlementPreview }
  : { financialPreview: sourceFinancialPreview };
