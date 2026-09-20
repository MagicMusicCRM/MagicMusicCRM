import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import type { LessonSettlementPort } from "../commerce/lesson-settlement.port";
import type { CrmPolicy } from "../crm.policy";
import type { SchedulePlanRowDto } from "../dto/schedule-plan.dto";
import type { PreparedSchedulePlanUpdate } from "./schedule-plan-definition.types";
import type { PreparedSchedulePlanRow } from "./schedule-plan-preview.types";

type RowDecision = SchedulePlanRowDto["financialDecision"];

const sameTeacherDecision = (left: RowDecision, right: RowDecision) =>
  left.teacherCompensationRuleKey === right.teacherCompensationRuleKey &&
  left.teacherCompensationValueMinor === right.teacherCompensationValueMinor &&
  left.teacherCreditedDurationMinutes === right.teacherCreditedDurationMinutes &&
  left.teacherCompensationSource === right.teacherCompensationSource;

const teacherDecision = (decision: RowDecision) => ({
  teacherCompensationRuleKey: decision.teacherCompensationRuleKey,
  teacherCompensationValueMinor: decision.teacherCompensationValueMinor,
  teacherCreditedDurationMinutes: decision.teacherCreditedDurationMinutes,
  teacherCompensationSource: decision.teacherCompensationSource,
});

const storedDecisionContext = (
  policy: CrmPolicy,
  actor: ActorContext,
  row: SchedulePlanRowDto,
  prepared?: PreparedSchedulePlanUpdate,
) => {
  const storedSeries = prepared?.activeSeries.find(
    (series) => series.id === row.seriesId,
  );
  const stored = storedSeries?.planned_financial_decision;
  const storedTeacherDecision = stored ? teacherDecision(stored) : undefined;
  const preservesTeacher = Boolean(
    stored &&
      stored.teacherCompensationSource !== "automatic" &&
      (!policy.canManageTeacherCompensation(actor) ||
        sameTeacherDecision(row.financialDecision, stored)),
  );
  const effectiveDecision = preservesTeacher
    ? { ...row.financialDecision, ...storedTeacherDecision }
    : row.financialDecision;
  return {
    storedSeries,
    stored,
    usesStoredCatalog:
      stored !== null &&
      stored !== undefined &&
      fingerprintPayload(effectiveDecision) === fingerprintPayload(stored),
    preservedTeacherDecision:
      preservesTeacher && storedTeacherDecision
        ? {
            ...storedTeacherDecision,
            teacherCompensationSource:
              storedTeacherDecision.teacherCompensationSource ?? "manual",
          }
        : undefined,
  };
};

export async function prepareSchedulePlanRow(input: {
  client: PoolClient;
  actor: ActorContext;
  row: SchedulePlanRowDto;
  allowedClientIds: string[];
  policy: CrmPolicy;
  settlement: LessonSettlementPort;
  prepared?: PreparedSchedulePlanUpdate;
}): Promise<PreparedSchedulePlanRow> {
  const { client, actor, row, allowedClientIds, policy, settlement, prepared } =
    input;
  policy.assertCanSupplyTeacherCompensation(actor, row.financialDecision);
  const context = storedDecisionContext(policy, actor, row, prepared);
  const unchangedLegacyWithoutClientDecisions = Boolean(
    context.storedSeries &&
      context.usesStoredCatalog &&
      !context.stored?.clientDecisions?.length,
  );
  const settlementPlan = await settlement.resolvePlannedPlan(client, {
    branchId: row.branchId,
    durationMinutes: row.durationMinutes ?? 60,
    decision: row.financialDecision,
    actorUserId: actor.userId,
    authorization: policy.teacherCompensationMutationAuthorization(actor),
    reasonText: row.plannedSettlementReason,
    ...(context.storedSeries && context.usesStoredCatalog
      ? {
          configurationRevisionIds: {
            settlementRevisionId: context.storedSeries.settlement_revision_id,
            compensationRevisionId:
              context.storedSeries.compensation_revision_id,
          },
        }
      : {}),
    ...(!unchangedLegacyWithoutClientDecisions
      ? { requiredClientIds: allowedClientIds }
      : {}),
    ...(context.preservedTeacherDecision
      ? { preservedTeacherDecision: context.preservedTeacherDecision }
      : {}),
  });
  return {
    row: { ...row, financialDecision: settlementPlan.decision },
    settlementPlan,
  };
}
