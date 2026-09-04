import { loadExcludedLessonParticipantIds } from "./lesson-settlement-facts.persistence";
import { assertLessonPayers, resolveLessonFunding } from "./lesson-funding";
import { ConflictException, NotFoundException } from "@nestjs/common";
import type { PoolClient } from "pg";
import {
  calculateClientSettlement,
  durationShareBasisPoints,
} from "./lesson-settlement.calculation";
import {
  assertPlannedLessonSettlementDecision,
  invalidLessonSettlementDecision,
  loadLessonSettlementCatalog,
  rethrowLessonSettlementCalculation,
  type LessonSettlementCatalog,
} from "./lesson-settlement-catalog";
import type {
  ClientChargeFactType,
  LessonFinancialDecision,
  PlannedSubscriptionAllocation,
  PreparedLessonSettlementPlan,
  StoredLessonSettlementPlan,
} from "./lesson-settlement.port";
import { resolveSettlementPolicy } from "./lesson-settlement-policy";

interface PlanChargeSource {
  client_type: "lead" | "student";
  client_id: string;
  charge_type: ClientChargeFactType;
  charge_value: string;
  subscription_id: string | null;
}

export async function prepareLessonSettlementPlan(
  client: PoolClient,
  branchId: string,
  decision: LessonFinancialDecision,
  actorUserId?: string,
): Promise<PreparedLessonSettlementPlan> {
  const catalog = await loadLessonSettlementCatalog(client, branchId);
  return prepareLessonSettlementPlanWithCatalog(
    client,
    catalog,
    decision,
    actorUserId,
  );
}

export async function prepareLessonSettlementPlanWithCatalog(
  client: PoolClient,
  catalog: LessonSettlementCatalog,
  decision: LessonFinancialDecision,
  actorUserId?: string,
): Promise<PreparedLessonSettlementPlan> {
  await assertLessonPayers(client, decision, actorUserId);
  assertPlannedLessonSettlementDecision(catalog, decision);
  return {
    decision: JSON.parse(JSON.stringify(decision)) as LessonFinancialDecision,
    settlementRevisionId: catalog.settlement_revision_id,
    compensationRevisionId: catalog.compensation_revision_id,
  };
}

export async function assignLessonSettlementPlan(
  client: PoolClient,
  input: {
    lessonId: string;
    branchId: string;
    decision: LessonFinancialDecision;
    selectedBy: string;
    reasonText?: string;
  },
): Promise<PreparedLessonSettlementPlan> {
  const prepared = await prepareLessonSettlementPlan(
    client,
    input.branchId,
    input.decision,
    input.selectedBy,
  );
  await insertPreparedLessonSettlementPlan(client, {
    lessonId: input.lessonId,
    selectedBy: input.selectedBy,
    reasonText: input.reasonText,
    ...prepared,
  });
  return prepared;
}

export async function cloneLessonSettlementPlan(
  client: PoolClient,
  input: {
    sourceLessonId: string;
    targetLessonId: string;
    selectedBy: string;
    reasonText?: string;
    fallback?: PreparedLessonSettlementPlan;
  },
): Promise<PreparedLessonSettlementPlan> {
  const source = await loadLessonSettlementPlan(
    client,
    input.sourceLessonId,
    true,
  );
  if (!source && !input.fallback) {
    throw new ConflictException({
      code: "LESSON_SETTLEMENT_PLAN_MISSING",
      lessonId: input.sourceLessonId,
    });
  }
  const prepared = source
    ? preparedPlanFromStored(source)
    : input.fallback!;
  await assertLessonPayers(client, prepared.decision, input.selectedBy);
  await insertPreparedLessonSettlementPlan(client, {
    lessonId: input.targetLessonId,
    selectedBy: input.selectedBy,
    reasonText: input.reasonText ?? source?.reasonText ?? undefined,
    ...prepared,
  });
  return prepared;
}

function preparedPlanFromStored(
  source: StoredLessonSettlementPlan,
): PreparedLessonSettlementPlan {
  return {
    decision: source.decision,
    settlementRevisionId: source.settlementRevisionId,
    compensationRevisionId: source.compensationRevisionId,
  };
}

export async function insertPreparedLessonSettlementPlan(
  client: PoolClient,
  input: PreparedLessonSettlementPlan & {
    lessonId: string;
    selectedBy: string;
    reasonText?: string;
  },
): Promise<void> {
  const result = await client.query(
    `
      insert into app.lesson_settlement_plans (
        lesson_id, decision, settlement_revision_id,
        compensation_revision_id, selected_by, reason_text
      ) values ($1, $2::jsonb, $3, $4, $5, $6)
      on conflict (lesson_id) do nothing
      returning lesson_id
    `,
    [
      input.lessonId,
      JSON.stringify(input.decision),
      input.settlementRevisionId,
      input.compensationRevisionId,
      input.selectedBy,
      input.reasonText?.trim() || null,
    ],
  );
  if (!result.rows[0]) {
    throw new ConflictException({
      code: "LESSON_SETTLEMENT_PLAN_EXISTS",
      lessonId: input.lessonId,
    });
  }
  await insertLessonSettlementPlanRevision(client, input, 1);
}

async function insertLessonSettlementPlanRevision(
  client: PoolClient,
  input: PreparedLessonSettlementPlan & {
    lessonId: string;
    selectedBy: string;
    reasonText?: string;
  },
  version: number,
): Promise<void> {
  await client.query(
    `insert into app.lesson_settlement_plan_revisions (
       lesson_id, version, decision, settlement_revision_id,
       compensation_revision_id, reason_text, actor_user_id
     ) values ($1, $2, $3::jsonb, $4, $5, $6, $7)`,
    [
      input.lessonId,
      version,
      JSON.stringify(input.decision),
      input.settlementRevisionId,
      input.compensationRevisionId,
      input.reasonText?.trim() || null,
      input.selectedBy,
    ],
  );
}

export async function plannedLessonSubscriptionAllocations(
  client: PoolClient,
  lessonId: string,
  plan: PreparedLessonSettlementPlan,
): Promise<PlannedSubscriptionAllocation[]> {
  const catalog = await loadLessonSettlementCatalog(client, "", {
    settlementRevisionId: plan.settlementRevisionId,
    compensationRevisionId: plan.compensationRevisionId,
  });
  assertPlannedLessonSettlementDecision(catalog, plan.decision);
  const { charges, durationMinutes } = await loadPlanAllocationSources(
    client,
    lessonId,
  );
  await assertLessonPayers(client, plan.decision);
  const excludedIds = await loadExcludedLessonParticipantIds(client, lessonId);
  const knownIds = new Set([...charges.map((charge) => charge.client_id), ...excludedIds]);
  if ((plan.decision.clientDecisions ?? []).some((item) => !knownIds.has(item.clientId))) {
    invalidLessonSettlementDecision("UNKNOWN_LESSON_CLIENT", "clientDecisions");
  }
  return calculatePlanAllocations(charges, durationMinutes, plan, catalog);
}

async function loadPlanAllocationSources(
  client: PoolClient,
  lessonId: string,
): Promise<{ charges: PlanChargeSource[]; durationMinutes: number }> {
  const duration = await client.query<{ duration_minutes: number }>(
    `select duration_minutes from app.lessons
     where id = $1 and deleted_at is null`,
    [lessonId],
  );
  if (!duration.rows[0]) throw new NotFoundException("Урок не найден.");
  const charges = await client.query<PlanChargeSource>(
    `select snapshot.client_type, snapshot.client_id,
       snapshot.client_charge_type as charge_type,
       snapshot.client_charge_value as charge_value,
       snapshot.subscription_id
     from app.lesson_snapshots snapshot
     where snapshot.lesson_id = $1 and snapshot.group_id is null
     union all
     select 'student'::text, participant.student_id,
       participant.charge_type, participant.charge_value,
       participant.subscription_id
     from app.lesson_snapshot_participants participant
     where participant.lesson_id = $1
       and not exists (
         select 1 from app.lesson_participant_exclusions exclusion
         where exclusion.lesson_id = participant.lesson_id
           and exclusion.student_id = participant.student_id
       )
     order by client_type, client_id`,
    [lessonId],
  );
  return {
    charges: charges.rows,
    durationMinutes: duration.rows[0].duration_minutes,
  };
}

function calculatePlanAllocations(
  charges: PlanChargeSource[],
  durationMinutes: number,
  plan: PreparedLessonSettlementPlan,
  catalog: LessonSettlementCatalog,
): PlannedSubscriptionAllocation[] {
  const decisions = new Map(
    (plan.decision.clientDecisions ?? []).map((item) => [item.clientId, item]),
  );
  return charges.flatMap((charge) =>
    calculatePlanAllocation(
      charge,
      durationMinutes,
      plan.decision,
      decisions.get(charge.client_id),
      catalog,
    ),
  );
}

function calculatePlanAllocation(
  charge: PlanChargeSource,
  durationMinutes: number,
  decision: LessonFinancialDecision,
  selected: NonNullable<LessonFinancialDecision["clientDecisions"]>[number]
    | undefined,
  catalog: LessonSettlementCatalog,
): PlannedSubscriptionAllocation[] {
  const funding = resolveLessonFunding(charge, selected);
  const { chargeType, subscriptionId } = funding;
  const settlementKey = selected?.settlementTypeKey ??
    decision.settlementTypeKey;
  const settlement = catalog.settlement_types.find(
    (item) => item.stableKey === settlementKey,
  );
  if (!settlement) {
    invalidLessonSettlementDecision(
      "SETTLEMENT_TYPE_NOT_ALLOWED",
      "settlementTypeKey",
    );
  }
  const policy = resolveSettlementPolicy(catalog, settlementKey);
  if (
    policy.clientDurationMode === "manual" &&
    selected?.chargeDurationMinutes === undefined &&
    decision.teacherCompensationSource !== undefined
  ) {
    invalidLessonSettlementDecision(
      "CLIENT_PARTIAL_DURATION_REQUIRED",
      `clientDecisions.${charge.client_id}.chargeDurationMinutes`,
    );
  }
  let calculated;
  try {
    calculated = calculateClientSettlement({
      durationMinutes,
      hourShareBasisPoints: selected?.chargeDurationMinutes === undefined
        ? settlement.hourShareBasisPoints
        : durationShareBasisPoints(
            selected.chargeDurationMinutes,
            durationMinutes,
          ),
      fixedPenaltyMinor: settlement.fixedPenaltyMinor ?? "0",
      chargeType,
      baseChargeMinor: funding.baseChargeMinor,
    });
  } catch (error) {
    rethrowLessonSettlementCalculation(error);
  }
  if (chargeType !== "subscription" || !subscriptionId) return [];
  const units = Number(calculated.units);
  if (units <= 0) return [];
  return [
    {
      clientType: charge.client_type,
      clientId: charge.client_id,
      ...(selected?.payerStudentId
        ? { payerStudentId: selected.payerStudentId }
        : {}),
      subscriptionId,
      units,
    },
  ];
}

export async function replaceLessonSettlementPlan(
  client: PoolClient,
  input: PreparedLessonSettlementPlan & {
    lessonId: string;
    expectedVersion: number;
    selectedBy: string;
    reasonText: string;
  },
): Promise<number> {
  const result = await client.query<{ version: number | string }>(
    `update app.lesson_settlement_plans
     set decision = $3::jsonb,
         settlement_revision_id = $4,
         compensation_revision_id = $5,
         selected_by = $6,
         selected_at = now(),
         reason_text = $7,
         failure_code = null,
         version = version + 1,
         updated_at = now()
     where lesson_id = $1 and version = $2 and state in ('planned', 'review_required')
     returning version`,
    [
      input.lessonId,
      input.expectedVersion,
      JSON.stringify(input.decision),
      input.settlementRevisionId,
      input.compensationRevisionId,
      input.selectedBy,
      input.reasonText.trim(),
    ],
  );
  if (!result.rows[0]) {
    throw new ConflictException({ code: "LESSON_SETTLEMENT_PLAN_STALE" });
  }
  const version = Number(result.rows[0].version);
  await insertLessonSettlementPlanRevision(client, input, version);
  return version;
}

export async function loadLessonSettlementPlan(
  client: PoolClient,
  lessonId: string,
  lock = false,
): Promise<StoredLessonSettlementPlan | null> {
  const result = await client.query<{
    lesson_id: string;
    decision: LessonFinancialDecision;
    settlement_revision_id: string;
    compensation_revision_id: string;
    version: number | string;
    state: StoredLessonSettlementPlan["state"];
    reason_text: string | null;
  }>(
    `select lesson_id, decision, settlement_revision_id,
       compensation_revision_id, version, state, reason_text
     from app.lesson_settlement_plans where lesson_id = $1
     ${lock ? "for update" : ""}`,
    [lessonId],
  );
  const row = result.rows[0];
  return row
    ? {
        lessonId: row.lesson_id,
        decision: row.decision,
        settlementRevisionId: row.settlement_revision_id,
        compensationRevisionId: row.compensation_revision_id,
        version: Number(row.version),
        state: row.state,
        reasonText: row.reason_text,
      }
    : null;
}

export async function markLessonSettlementPlanState(
  client: PoolClient,
  lessonId: string,
  state: "settled" | "review_required" | "cancelled",
  failureCode?: string,
): Promise<void> {
  const result = await client.query(
    `update app.lesson_settlement_plans
     set state = $2,
         failure_code = case when $2 = 'review_required' then $3 else null end,
         version = version + 1,
         updated_at = now()
     where lesson_id = $1
       and state in ('planned', 'review_required')
     returning lesson_id`,
    [lessonId, state, failureCode?.trim().slice(0, 120) || null],
  );
  if (!result.rows[0]) {
    throw new ConflictException({
      code: "LESSON_SETTLEMENT_PLAN_STATE",
      lessonId,
    });
  }
}
