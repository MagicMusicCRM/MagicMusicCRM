import { ConflictException } from "@nestjs/common";
import type { PoolClient } from "pg";
import {
  calculateClientSettlement,
  calculateTeacherCompensation,
  rublesToMinor,
} from "./lesson-settlement.calculation";
import {
  invalidLessonSettlementDecision,
  loadLessonSettlementCatalog,
  rethrowLessonSettlementCalculation,
  type LessonSettlementCatalog,
} from "./lesson-settlement-catalog";
import {
  insertConfiguredLessonClientFacts,
  insertConfiguredLessonTeacherFact,
  insertLegacyLessonSettlementFacts,
  loadExcludedLessonParticipantIds,
  loadLessonSettlementCharges,
  loadLessonSettlementFacts,
  loadLessonSettlementSource,
  loadSupersededLessonFacts,
  type CalculatedLessonClientFact,
  type CalculatedLessonTeacherFact,
  type LessonSettlementChargeSource,
  type LessonSettlementSource,
} from "./lesson-settlement-facts.persistence";
import type {
  ClientChargeFactType,
  LessonSettlementInput,
  LessonSettlementResult,
} from "./lesson-settlement.port";
import {
  assertCorrectionSubscriptionCapacity,
  reserveLessonSettlementSubscriptions,
} from "./lesson-settlement-subscription-capacity";

export async function settleLesson(
  client: PoolClient,
  lessonId: string,
  input?: LessonSettlementInput,
): Promise<LessonSettlementResult> {
  await client.query(
    "select pg_advisory_xact_lock(hashtextextended($1, 0))",
    [`commerce:lesson-settlement:${lessonId}`],
  );
  const existing = await loadLessonSettlementFacts(client, lessonId);
  if (existing && !input?.correction) {
    if (input) {
      await assertExistingLessonSettlementDecision(client, existing, input);
    }
    return existing;
  }
  const source = await loadLessonSettlementSource(client, lessonId);
  assertLessonSettleable(source, input?.context);
  if (input) {
    await insertConfiguredLessonSettlementFacts(client, source, input);
  } else {
    await insertLegacyLessonSettlementFacts(client, source);
  }
  return requireCompleteLessonSettlement(client, lessonId);
}

async function requireCompleteLessonSettlement(
  client: PoolClient,
  lessonId: string,
): Promise<LessonSettlementResult> {
  const settled = await loadLessonSettlementFacts(client, lessonId);
  if (settled) return settled;
  throw new ConflictException({
    code: "LESSON_SETTLEMENT_INCOMPLETE",
    lessonId,
  });
}

async function insertConfiguredLessonSettlementFacts(
  client: PoolClient,
  source: LessonSettlementSource,
  input: LessonSettlementInput,
): Promise<void> {
  assertLessonSettlementReason(input.reasonText);
  const catalog = await loadLessonSettlementCatalog(
    client,
    source.branch_id,
    input.configurationRevisionIds,
  );
  const clientDecisions = mapUniqueClientDecisions(input);
  const charges = await loadLessonSettlementCharges(client, source.lesson_id);
  await assertKnownLessonClients(
    client,
    source.lesson_id,
    charges,
    clientDecisions,
  );
  const clientFacts = calculateConfiguredClientFacts(
    source,
    input,
    catalog,
    charges,
    clientDecisions,
  );
  const superseded = await loadSupersededLessonFacts(
    client,
    source.lesson_id,
    Boolean(input.correction),
  );
  await assertAndReserveSubscriptionCapacity(
    client,
    source.lesson_id,
    clientFacts,
    Boolean(input.correction),
  );
  await insertConfiguredLessonClientFacts(client, {
    lessonId: source.lesson_id,
    facts: clientFacts,
    configurationRevisionId: catalog.settlement_revision_id,
    correctionId: input.correction?.id ?? null,
    supersededFactIds: superseded.clientFactIds,
  });
  const teacherFact = calculateConfiguredTeacherFact(source, input, catalog);
  await insertConfiguredLessonTeacherFact(client, {
    source,
    fact: teacherFact,
    configurationRevisionId: catalog.compensation_revision_id,
    correctionId: input.correction?.id ?? null,
    supersededFactId: superseded.teacherFactId,
  });
}

function assertLessonSettlementReason(reasonText?: string): void {
  if (reasonText && reasonText.trim().length > 500) {
    invalidLessonSettlementDecision("REASON_TOO_LONG", "reasonText");
  }
}

type ClientDecision = NonNullable<
  LessonSettlementInput["decision"]["clientDecisions"]
>[number];

function mapUniqueClientDecisions(
  input: LessonSettlementInput,
): Map<string, ClientDecision> {
  const decisions = new Map<string, ClientDecision>();
  for (const decision of input.decision.clientDecisions ?? []) {
    if (decisions.has(decision.clientId)) {
      invalidLessonSettlementDecision(
        "DUPLICATE_CLIENT_DECISION",
        "clientDecisions",
      );
    }
    decisions.set(decision.clientId, decision);
  }
  return decisions;
}

async function assertKnownLessonClients(
  client: PoolClient,
  lessonId: string,
  charges: LessonSettlementChargeSource[],
  decisions: Map<string, ClientDecision>,
): Promise<void> {
  const knownClients = new Set(charges.map((row) => row.client_id));
  const excludedClients = await loadExcludedLessonParticipantIds(
    client,
    lessonId,
  );
  const hasUnknown = [...decisions.keys()].some(
    (id) => !knownClients.has(id) && !excludedClients.has(id),
  );
  if (hasUnknown) {
    invalidLessonSettlementDecision(
      "UNKNOWN_LESSON_CLIENT",
      "clientDecisions",
    );
  }
}

function calculateConfiguredClientFacts(
  source: LessonSettlementSource,
  input: LessonSettlementInput,
  catalog: LessonSettlementCatalog,
  charges: LessonSettlementChargeSource[],
  decisions: Map<string, ClientDecision>,
): CalculatedLessonClientFact[] {
  const settlementTypes = new Map(
    catalog.settlement_types
      .filter((type) => type.active)
      .map((type) => [type.stableKey, type]),
  );
  return charges.map((charge) =>
    calculateConfiguredClientFact(
      source,
      input,
      charge,
      decisions.get(charge.client_id),
      settlementTypes,
    ),
  );
}

function calculateConfiguredClientFact(
  source: LessonSettlementSource,
  input: LessonSettlementInput,
  charge: LessonSettlementChargeSource,
  decision: ClientDecision | undefined,
  settlementTypes: Map<
    string,
    LessonSettlementCatalog["settlement_types"][number]
  >,
): CalculatedLessonClientFact {
  const settlementKey =
    decision?.settlementTypeKey ?? input.decision.settlementTypeKey;
  const settlement = settlementTypes.get(settlementKey);
  if (!settlement || !settlement.allowedContexts.includes(input.context)) {
    invalidLessonSettlementDecision(
      "SETTLEMENT_TYPE_NOT_ALLOWED",
      "settlementTypeKey",
    );
  }
  const subscriptionId = decision?.subscriptionId ?? charge.subscription_id;
  const chargeType: ClientChargeFactType = subscriptionId
    ? "subscription"
    : charge.charge_type;
  let calculation;
  try {
    calculation = calculateClientSettlement({
      durationMinutes: source.duration_minutes!,
      hourShareBasisPoints: settlement.hourShareBasisPoints,
      fixedPenaltyMinor: settlement.fixedPenaltyMinor ?? "0",
      chargeType,
      baseChargeMinor:
        chargeType === "personal_account"
          ? rublesToMinor(charge.charge_value)
          : 0n,
    });
  } catch (error) {
    rethrowLessonSettlementCalculation(error);
  }
  return {
    charge,
    chargeType,
    subscriptionId: chargeType === "subscription" ? subscriptionId : null,
    settlement,
    calculation,
  };
}

async function assertAndReserveSubscriptionCapacity(
  client: PoolClient,
  lessonId: string,
  facts: CalculatedLessonClientFact[],
  correction: boolean,
): Promise<void> {
  if (correction) {
    await assertCorrectionSubscriptionCapacity(client, lessonId, facts);
    return;
  }
  await reserveLessonSettlementSubscriptions(client, lessonId, facts);
}

function calculateConfiguredTeacherFact(
  source: LessonSettlementSource,
  input: LessonSettlementInput,
  catalog: LessonSettlementCatalog,
): CalculatedLessonTeacherFact {
  const rule = catalog.compensation_rules.find(
    (candidate) =>
      candidate.active &&
      candidate.stableKey === input.decision.teacherCompensationRuleKey,
  );
  if (!rule) {
    invalidLessonSettlementDecision(
      "TEACHER_COMPENSATION_RULE_NOT_FOUND",
      "teacherCompensationRuleKey",
    );
  }
  let calculation;
  try {
    calculation = calculateTeacherCompensation({
      durationMinutes: source.duration_minutes!,
      legacyType: source.teacher_compensation_type!,
      legacyRateRubles: source.teacher_compensation_value!,
      mode: rule.mode,
      configuredValue: rule.value,
      overrideValue: input.decision.teacherCompensationValueMinor,
      overrideReason: input.reasonText,
    });
  } catch (error) {
    rethrowLessonSettlementCalculation(error);
  }
  return { rule, calculation };
}

async function assertExistingLessonSettlementDecision(
  client: PoolClient,
  existing: LessonSettlementResult,
  input: LessonSettlementInput,
): Promise<void> {
  const excludedClients = await loadExcludedLessonParticipantIds(
    client,
    existing.lessonId,
  );
  const clients = new Map(
    (input.decision.clientDecisions ?? [])
      .filter((decision) => !excludedClients.has(decision.clientId))
      .map((decision) => [decision.clientId, decision]),
  );
  const existingClientIds = new Set(
    existing.clientFacts.map((fact) => fact.clientId),
  );
  const matches =
    [...clients.keys()].every((id) => existingClientIds.has(id)) &&
    existing.clientFacts.every((fact) => {
      const decision = clients.get(fact.clientId);
      return (
        fact.settlementTypeKey ===
          (decision?.settlementTypeKey ?? input.decision.settlementTypeKey) &&
        (!decision?.subscriptionId ||
          decision.subscriptionId === fact.subscriptionId)
      );
    }) &&
    existing.teacherFact.compensationRuleKey ===
      input.decision.teacherCompensationRuleKey &&
    (!input.decision.teacherCompensationValueMinor ||
      existing.teacherFact.compensationActualValue ===
        input.decision.teacherCompensationValueMinor);
  if (!matches) {
    throw new ConflictException({
      code: "LESSON_ALREADY_SETTLED_WITH_DIFFERENT_DECISION",
      lessonId: existing.lessonId,
    });
  }
}

export function assertLessonSettleable(
  source: LessonSettlementSource,
  context?: LessonSettlementInput["context"],
): void {
  const expectedState = expectedSettlementLifecycleState(context);
  if (source.lifecycle_state !== expectedState) {
    throw new ConflictException({
      code: "LESSON_NOT_IN_SETTLEMENT_STATE",
      lessonId: source.lesson_id,
      state: source.lifecycle_state,
      expectedState,
    });
  }
  if (!hasCompleteLessonSettlementSnapshot(source)) {
    throw new ConflictException({
      code: "LESSON_SETTLEMENT_SNAPSHOT_INCOMPLETE",
      lessonId: source.lesson_id,
    });
  }
}

function expectedSettlementLifecycleState(
  context?: LessonSettlementInput["context"],
): string {
  if (context === "reschedule") return "rescheduled";
  if (context === "cancel") return "cancelled";
  return "successfully_completed";
}

function hasCompleteLessonSettlementSnapshot(
  source: LessonSettlementSource,
): boolean {
  if (source.validation_state !== "valid") return false;
  if (!source.teacher_id) return false;
  if (!source.client_charge_type) return false;
  if (source.client_charge_value === null) return false;
  if (!source.teacher_compensation_type) return false;
  if (source.teacher_compensation_value === null) return false;
  if (!source.duration_minutes) return false;
  if (source.group_id) return Number(source.participant_count) > 0;
  return Boolean(source.client_type && source.client_id);
}
