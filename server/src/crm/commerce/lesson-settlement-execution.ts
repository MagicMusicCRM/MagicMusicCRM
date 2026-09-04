import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { assertLessonPayers, resolveLessonFunding } from "./lesson-funding";
import {
  ConflictException,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import {
  calculateClientSettlement,
  calculateTeacherCompensation,
  durationShareBasisPoints,
  minorToRubles,
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
  projectConfiguredLessonClientFact,
  projectConfiguredLessonTeacherFact,
  type CalculatedLessonClientFact,
  type CalculatedLessonTeacherFact,
  type LessonSettlementChargeSource,
  type LessonSettlementSource,
} from "./lesson-settlement-facts.persistence";
import type {
  LessonSettlementInput,
  LessonSettlementResult,
  LessonSettlementPreview,
} from "./lesson-settlement.port";
import { resolveSettlementPolicy } from "./lesson-settlement-policy";
import {
  assertCorrectionSubscriptionCapacity,
  assertLessonSubscriptionSelection,
  reserveLessonSettlementSubscriptions,
} from "./lesson-settlement-subscription-capacity";
import { acquireLessonSettlementLocks } from "./lesson-settlement-locks";

export async function settleLesson(
  client: PoolClient,
  lessonId: string,
  input?: LessonSettlementInput,
): Promise<LessonSettlementResult> {
  await acquireLessonSettlementLocks(client, [lessonId]);
  const existing = await loadLessonSettlementFacts(client, lessonId);
  if (existing && !input?.correction) {
    if (input) {
      await assertExistingLessonSettlementDecision(client, existing, input);
    }
    return existing;
  }
  const source = await loadLessonSettlementSource(client, lessonId);
  if (input?.decision.teacherRateSnapshot) {
    source.teacher_compensation_type = input.decision.teacherRateSnapshot.type;
    source.teacher_compensation_value = input.decision.teacherRateSnapshot.value;
  }
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

/** Calculates a planned settlement without reserving capacity or writing financial facts. */
export async function previewLessonSettlement(
  client: PoolClient,
  lessonId: string,
  input: LessonSettlementInput,
): Promise<LessonSettlementPreview> {
  const source = await loadLessonSettlementSource(client, lessonId);
  if (input.decision.teacherRateSnapshot) {
    source.teacher_compensation_type = input.decision.teacherRateSnapshot.type;
    source.teacher_compensation_value = input.decision.teacherRateSnapshot.value;
  }
  assertLessonSettleable(source, input.context);
  const { catalog, clientFacts, teacherFact } = await calculateConfiguredLessonSettlement(client, source, input);
  await assertLessonSubscriptionSelection(client, clientFacts);
  return {
    clientFacts: clientFacts.map((fact) => projectConfiguredLessonClientFact(fact, catalog.settlement_revision_id)),
    teacherFact: projectConfiguredLessonTeacherFact(source, teacherFact, catalog.compensation_revision_id),
  };
}

async function calculateConfiguredLessonSettlement(
  client: PoolClient,
  source: LessonSettlementSource,
  input: LessonSettlementInput,
) {
  assertLessonSettlementReason(input.reasonText);
  const catalog = await loadLessonSettlementCatalog(
    client,
    source.branch_id,
    input.configurationRevisionIds,
  );
  const clientDecisions = mapUniqueClientDecisions(input);
  await assertLessonPayers(client, input.decision);
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
  return { catalog, clientFacts, teacherFact: calculateConfiguredTeacherFact(source, input, catalog) };
}

async function insertConfiguredLessonSettlementFacts(
  client: PoolClient,
  source: LessonSettlementSource,
  input: LessonSettlementInput,
): Promise<void> {
  const { catalog, clientFacts, teacherFact } = await calculateConfiguredLessonSettlement(client, source, input);
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
  return charges.map((charge) =>
    calculateConfiguredClientFact(
      source,
      input,
      charge,
      decisions.get(charge.client_id),
      catalog,
    ),
  );
}

function calculateConfiguredClientFact(
  source: LessonSettlementSource,
  input: LessonSettlementInput,
  charge: LessonSettlementChargeSource,
  decision: ClientDecision | undefined,
  catalog: LessonSettlementCatalog,
): CalculatedLessonClientFact {
  const settlementKey =
    decision?.settlementTypeKey ?? input.decision.settlementTypeKey;
  const settlement = catalog.settlement_types.find(
    (item) => item.active && item.stableKey === settlementKey,
  );
  if (!settlement || !settlement.allowedContexts.includes(input.context)) {
    invalidLessonSettlementDecision(
      "SETTLEMENT_TYPE_NOT_ALLOWED",
      "settlementTypeKey",
    );
  }
  const policy = resolveSettlementPolicy(catalog, settlementKey);
  if (
    policy.clientDurationMode === "manual" &&
    decision?.chargeDurationMinutes === undefined &&
    decision !== undefined
  ) {
    invalidLessonSettlementDecision(
      "CLIENT_PARTIAL_DURATION_REQUIRED",
      `clientDecisions.${charge.client_id}.chargeDurationMinutes`,
    );
  }
  const funding = resolveLessonFunding(charge, decision);
  const { chargeType, subscriptionId } = funding;
  let calculation;
  try {
    calculation = calculateClientSettlement({
      durationMinutes: source.duration_minutes!,
      hourShareBasisPoints: decision?.chargeDurationMinutes === undefined
        ? settlement.hourShareBasisPoints
        : durationShareBasisPoints(
            decision.chargeDurationMinutes,
            source.duration_minutes!,
          ),
      fixedPenaltyMinor: settlement.fixedPenaltyMinor ?? "0",
      chargeType,
      baseChargeMinor: funding.baseChargeMinor,
    });
  } catch (error) {
    rethrowLessonSettlementCalculation(error);
  }
  return {
    charge,
    chargeType,
    subscriptionId: chargeType === "subscription" ? subscriptionId : null,
    payerStudentId: funding.payerStudentId,
    pricingSnapshot: funding.pricingSnapshot,
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
      overrideValue:
        rule.mode === "percent" &&
          input.decision.teacherCreditedDurationMinutes !== undefined
          ? durationShareBasisPoints(
              input.decision.teacherCreditedDurationMinutes,
              source.duration_minutes!,
            ).toString()
          : input.decision.teacherCompensationValueMinor,
      overrideReason: input.reasonText,
    });
  } catch (error) {
    rethrowLessonSettlementCalculation(error);
  }
  return {
    rule,
    calculation,
    compensationSource:
      input.decision.teacherCompensationSource ?? "automatic",
  };
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
  const ownerBySubscription = await loadExistingSubscriptionOwners(
    client,
    existing,
    clients,
  );
  assertExistingSubscriptionOwners(existing, clients, ownerBySubscription);
  const existingClientIds = new Set(
    existing.clientFacts.map((fact) => fact.clientId),
  );
  const matches =
    [...clients.keys()].every((id) => existingClientIds.has(id)) &&
    existing.clientFacts.every((fact) => {
      const decision = clients.get(fact.clientId);
      const subscriptionOwner = fact.subscriptionId
        ? ownerBySubscription.get(fact.subscriptionId)
        : undefined;
      const requiresExplicitPayer =
        fact.subscriptionId !== null && subscriptionOwner !== fact.clientId;
      const funding = resolveLessonFunding({
        client_type: fact.clientType,
        client_id: fact.clientId,
        charge_type: fact.chargeType,
        charge_value: fact.pricingSnapshot
          ? minorToRubles(BigInt(fact.pricingSnapshot.basePriceMinor))
          : fact.snapshotValue,
        subscription_id: fact.subscriptionId,
      }, decision);
      const pricingMatches = !decision ||
        (decision.basePriceMinor === undefined && !decision.discount && !decision.surcharge) ||
        fingerprintPayload(funding.pricingSnapshot) === fingerprintPayload(fact.pricingSnapshot);
      const requestedHourShareBasisPoints =
        decision?.chargeDurationMinutes === undefined
          ? undefined
          : durationShareBasisPoints(
              decision.chargeDurationMinutes,
              existing.teacherFact.durationMinutes,
            );
      return (
        funding.chargeType === fact.chargeType &&
        funding.subscriptionId === fact.subscriptionId &&
        (funding.payerStudentId ?? fact.clientId) === (fact.payerStudentId ?? subscriptionOwner ?? fact.clientId) &&
        pricingMatches &&
        (requestedHourShareBasisPoints === undefined ||
          requestedHourShareBasisPoints === fact.hourShareBasisPoints) &&
        fact.settlementTypeKey ===
          (decision?.settlementTypeKey ?? input.decision.settlementTypeKey) &&
        (requiresExplicitPayer
          ? Boolean(
              subscriptionOwner &&
                decision?.subscriptionId === fact.subscriptionId &&
                decision.payerStudentId === subscriptionOwner,
            )
          : !decision?.subscriptionId ||
            decision.subscriptionId === fact.subscriptionId)
      );
    }) &&
    existing.teacherFact.compensationRuleKey ===
      input.decision.teacherCompensationRuleKey &&
    (input.decision.teacherCompensationSource === undefined ||
      existing.teacherFact.compensationSource ===
        input.decision.teacherCompensationSource) &&
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

async function loadExistingSubscriptionOwners(
  client: PoolClient,
  existing: LessonSettlementResult,
  decisions: Map<string, ClientDecision>,
): Promise<Map<string, string>> {
  const selected = [...decisions.values()].filter(
    (decision): decision is ClientDecision & { subscriptionId: string } =>
      Boolean(decision.subscriptionId),
  );
  const subscriptionIds = [
    ...new Set([
      ...existing.clientFacts.flatMap((fact) =>
        fact.subscriptionId ? [fact.subscriptionId] : [],
      ),
      ...selected.map((decision) => decision.subscriptionId),
    ]),
  ];
  if (subscriptionIds.length === 0) return new Map();
  const owners = await client.query<{ id: string; student_id: string }>(
    `select id, student_id from app.subscriptions
     where id = any($1::uuid[])`,
    [subscriptionIds],
  );
  return new Map(
    owners.rows.map((row) => [row.id, row.student_id]),
  );
}

function assertExistingSubscriptionOwners(
  existing: LessonSettlementResult,
  decisions: Map<string, ClientDecision>,
  ownerBySubscription: Map<string, string>,
): void {
  const selected = [...decisions.values()].filter(
    (decision): decision is ClientDecision & { subscriptionId: string } =>
      Boolean(decision.subscriptionId),
  );
  for (const decision of selected) {
    const expectedOwner = decision.payerStudentId ?? decision.clientId;
    if (ownerBySubscription.get(decision.subscriptionId) === expectedOwner) {
      continue;
    }
    const fact = existing.clientFacts.find(
      (candidate) => candidate.clientId === decision.clientId,
    );
    throw new UnprocessableEntityException({
      code: "SUBSCRIPTION_CAPACITY",
      subscriptionId: decision.subscriptionId,
      clientId: decision.clientId,
      payerStudentId: decision.payerStudentId ?? null,
      requestedUnits: fact?.units ?? "0.00",
      availableUnits: "0",
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
