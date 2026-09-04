import { UnprocessableEntityException } from "@nestjs/common";
import { createHash } from "node:crypto";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { rublesToMinor } from "../commerce/lesson-settlement.calculation";
import type { LessonFinancialDecision } from "../commerce/lesson-settlement.port";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import type {
  BulkFingerprintItem,
  BulkTransitionDto,
  BulkTransitionInputItem,
  BulkTransitionItem,
  PlannedSettlementProjection,
  TransitionFinancialProjection,
  TransitionFingerprintInput,
  TransitionOperation,
  TransitionPreviewDto,
  TransitionSource,
  TransitionSuccessor,
  TerminalTransitionState,
} from "./lesson-transition.types";

const invalidDraft = (code: string, fields: string[]): never => {
  throw new UnprocessableEntityException({
    code,
    fields: [...new Set(fields)].sort(),
  });
};

export function targetTransitionState(
  operation: TransitionOperation,
): TerminalTransitionState {
  if (operation === "reschedule") return "rescheduled";
  if (operation === "cancel") return "cancelled";
  return "successfully_completed";
}

export function transitionReasonCode(dto: TransitionPreviewDto): string {
  return dto.reasonCode?.trim() || "manual";
}

export function assertTransitionReason(
  dto: TransitionPreviewDto,
  operation: TransitionOperation,
): void {
  const reasonCode = transitionReasonCode(dto);
  if (!/^[A-Za-z0-9._:-]{1,120}$/.test(reasonCode)) {
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_REASON_CODE_INVALID",
      fields: ["reasonCode"],
    });
  }
  const reasonText = dto.reasonText?.trim();
  const requiredReasonMissing = operation !== "settle" && !reasonText;
  const suppliedReasonInvalid = dto.reasonText !== undefined &&
    (!reasonText || reasonText.length > 500 || reasonText.includes("\0"));
  if (requiredReasonMissing || suppliedReasonInvalid) {
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_REASON_REQUIRED",
      fields: ["reasonText"],
    });
  }
}

export function assertTransitionConfirmed(confirm: true): void {
  if (confirm !== true) {
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_CONFIRMATION_REQUIRED",
    });
  }
}

export function assertTransitionMetadata(metadata: LessonCommandMetadata): void {
  if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
    throw new UnprocessableEntityException({ code: "IDEMPOTENCY_KEY_REQUIRED" });
  }
  if (!metadata.requestId || metadata.requestId.length > 160) {
    throw new UnprocessableEntityException({ code: "REQUEST_ID_REQUIRED" });
  }
}

export function stableTransitionId(seed: string): string {
  const bytes = createHash("sha256").update(seed).digest().subarray(0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x50;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

const assertBulkHeader = (dto: BulkTransitionDto): void => {
  const reasonText = dto.reasonText?.trim();
  const reasonCode = dto.reasonCode?.trim() || "manual";
  const validReason = Boolean(reasonText) && reasonText.length <= 500 &&
    !reasonText.includes("\0");
  const validReasonCode = /^[A-Za-z0-9._:-]{1,120}$/.test(reasonCode);
  const validItems = Array.isArray(dto.items) && dto.items.length >= 1 &&
    dto.items.length <= 500;
  if (!validReason || !validReasonCode || !validItems) {
    invalidDraft("LESSON_BULK_TRANSITION_INVALID", [
      "reasonText",
      "reasonCode",
      "items",
    ]);
  }
};

const hasValidBulkDecision = (item: BulkTransitionInputItem): boolean =>
  item.operation === "reschedule"
    ? Boolean(item.successorFinancialDecision ?? item.financialDecision)
    : Boolean(item.financialDecision) && !item.successorFinancialDecision;

const assertBulkItem = (
  item: BulkTransitionInputItem,
  index: number,
  ids: Set<string>,
): void => {
  const validId =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(item.lessonId);
  const validVersion = Number.isSafeInteger(item.expectedVersion) &&
    item.expectedVersion >= 1;
  const validOperation = ["reschedule", "cancel", "settle"].includes(
    item.operation,
  );
  const validSuccessor = (item.operation === "reschedule") ===
    Boolean(item.successor);
  if (
    !validId || !validVersion || !validOperation || !hasValidBulkDecision(item) ||
    !validSuccessor || ids.has(item.lessonId)
  ) {
    invalidDraft("LESSON_BULK_TRANSITION_INVALID", [`items.${index}`]);
  }
};

export function normalizeBulkTransitionItems(
  dto: BulkTransitionDto,
): BulkTransitionItem[] {
  assertBulkHeader(dto);
  const ids = new Set<string>();
  dto.items.forEach((item, index) => {
    assertBulkItem(item, index, ids);
    ids.add(item.lessonId);
  });
  return dto.items.map((item) => {
    if (item.operation !== "reschedule") {
      return {
        lessonId: item.lessonId,
        operation: item.operation,
        expectedVersion: item.expectedVersion,
        financialDecision: item.financialDecision!,
      };
    }
    const successorFinancialDecision = resolveSuccessorFinancialDecision(item);
    return {
      lessonId: item.lessonId,
      operation: "reschedule" as const,
      expectedVersion: item.expectedVersion,
      successor: item.successor!,
      sourceFinancialDecision: serverOwnedRescheduleSourceDecision(
        successorFinancialDecision.clientDecisions?.map(({ clientId }) => clientId) ?? [],
      ),
      successorFinancialDecision,
    };
  }).sort((left, right) => left.lessonId.localeCompare(right.lessonId));
}

export const sourceProjection = (source: TransitionSource) => ({
  id: source.id,
  version: source.version,
  state: source.lifecycleState,
});

export const draftProjection = (draft: TransitionSuccessor) => ({
  subject: draft.kind === "individual"
    ? { type: draft.clientRef.type, id: draft.clientRef.id }
    : { type: "group", id: draft.groupId },
  teacherId: draft.teacherId,
  branchId: draft.branchId,
  roomId: draft.roomId,
  startAt: draft.scheduledAt,
  endAt: draft.endAt,
});

export const transitionAdvisoryKeys = (
  source: TransitionSource,
  successor: TransitionSuccessor,
): string[] => {
  const clientKeys = successor.kind === "individual"
    ? [`client:${successor.clientRef.type}:${successor.clientRef.id}`]
    : successor.participants.map(
        (participant) => `client:student:${participant.studentId}`,
      );
  const keys = [
    `branch:${successor.branchId}`,
    ...clientKeys,
    `room:${source.roomId}`,
    `room:${successor.roomId}`,
    `teacher:${source.teacherId}`,
    `teacher:${successor.teacherId}`,
  ].filter((key) => !key.endsWith(":null"));
  return [...new Set(keys)].sort();
};

const nullableDecisionValue = <T>(value: T | undefined): T | null =>
  value === undefined ? null : value;

export const normalizedFinancialDecision = (decision: LessonFinancialDecision) => ({
  settlementTypeKey: decision.settlementTypeKey,
  clientDecisions: [...(decision.clientDecisions ?? [])]
    .sort((left, right) => left.clientId.localeCompare(right.clientId))
    .map((decision) => ({
      clientId: decision.clientId,
      settlementTypeKey: nullableDecisionValue(decision.settlementTypeKey),
      subscriptionId: nullableDecisionValue(decision.subscriptionId),
      payerStudentId: nullableDecisionValue(decision.payerStudentId),
      chargeDurationMinutes: nullableDecisionValue(
        decision.chargeDurationMinutes,
      ),
      ...(decision.chargeType === undefined ? {} : { chargeType: decision.chargeType }),
      ...(decision.basePriceMinor === undefined ? {} : { basePriceMinor: decision.basePriceMinor }),
      ...(decision.discount === undefined ? {} : { discount: decision.discount }),
      ...(decision.surcharge === undefined ? {} : { surcharge: decision.surcharge }),
    })),
  teacherCompensationRuleKey:
    decision.teacherCompensationRuleKey,
  teacherCompensationValueMinor:
    nullableDecisionValue(decision.teacherCompensationValueMinor),
  teacherCreditedDurationMinutes:
    nullableDecisionValue(
      decision.teacherCreditedDurationMinutes,
    ),
  teacherCompensationSource:
    nullableDecisionValue(decision.teacherCompensationSource),
});

export const normalizedTransitionDecision = (dto: TransitionPreviewDto) => {
  if (dto.sourceFinancialDecision && dto.successorFinancialDecision) {
    return {
      sourceFinancialDecision: normalizedFinancialDecision(
        dto.sourceFinancialDecision,
      ),
      successorFinancialDecision: normalizedFinancialDecision(
        dto.successorFinancialDecision,
      ),
    };
  }
  if (!dto.financialDecision) {
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_FINANCIAL_DECISION_REQUIRED",
      fields: ["financialDecision"],
    });
  }
  return normalizedFinancialDecision(dto.financialDecision);
};

export const serverOwnedRescheduleSourceDecision = (
  clientIds: string[],
): LessonFinancialDecision => ({
  settlementTypeKey: "free_lesson",
  clientDecisions: [...new Set(clientIds)].sort().map((clientId) => ({
    clientId,
    settlementTypeKey: "free_lesson",
    chargeType: "none",
    chargeDurationMinutes: 0,
  })),
  teacherCompensationRuleKey: "none",
  teacherCreditedDurationMinutes: 0,
});

const decisionFingerprint = (decision: LessonFinancialDecision) =>
  fingerprintPayload(normalizedFinancialDecision(decision));

export const resolveSuccessorFinancialDecision = (
  dto: Pick<
    TransitionPreviewDto,
    "successorFinancialDecision" | "financialDecision"
  >,
): LessonFinancialDecision => {
  const current = dto.successorFinancialDecision;
  const legacy = dto.financialDecision;
  if (!current && !legacy) {
    throw new UnprocessableEntityException({
      code: "LESSON_RESCHEDULE_SUCCESSOR_DECISION_REQUIRED",
      fields: ["successorFinancialDecision"],
    });
  }
  if (
    current && legacy &&
    decisionFingerprint(current) !== decisionFingerprint(legacy)
  ) {
    throw new UnprocessableEntityException({
      code: "LESSON_RESCHEDULE_DECISION_AMBIGUOUS",
      fields: ["successorFinancialDecision", "financialDecision"],
    });
  }
  return current ?? legacy!;
};

const settlementLabels: Record<string, string> = {
  lesson: "Занятие",
  free_lesson: "Бесплатное занятие",
  paid_miss: "Оплачиваемый пропуск",
  partially_paid_lesson: "Частично оплачиваемое занятие",
  partially_paid_miss: "Частично оплачиваемый пропуск",
  unpaid_miss: "Неоплачиваемый пропуск",
};

const compensationLabels: Record<string, string> = {
  none: "Не оплачивать",
  standard: "Стандартная оплата",
  percent: "Процент от стандартной оплаты",
  fixed: "Фиксированная оплата",
  hourly: "Почасовая оплата",
};

export const plannedSettlementProjection = (
  decision: LessonFinancialDecision,
): PlannedSettlementProjection => ({
  financialDecision: decision,
  settlementTypeLabel:
    settlementLabels[decision.settlementTypeKey] ?? "Настроенный тип расчёта",
  teacherCompensationLabel:
    compensationLabels[decision.teacherCompensationRuleKey] ??
      "Настроенное правило оплаты",
});

export function transitionFingerprint(input: TransitionFingerprintInput): string {
  const reschedule = input.dto.sourceFinancialDecision &&
    input.dto.successorFinancialDecision
    ? {
        sourceFinancialDecision: normalizedFinancialDecision(
          input.dto.sourceFinancialDecision,
        ),
        successorFinancialDecision: normalizedFinancialDecision(
          input.dto.successorFinancialDecision,
        ),
      }
    : null;
  return fingerprintPayload({
    operation: input.operation,
    source: sourceProjection(input.source),
    successor: input.successor ? draftProjection(input.successor) : null,
    reasonCode: transitionReasonCode(input.dto),
    reasonText: input.dto.reasonText?.trim() ?? null,
    financialDecision: reschedule ? null : normalizedTransitionDecision(input.dto),
    rescheduleFinancialDecisions: reschedule,
    coverage: input.coverage,
    sourceFinancialProjection: input.financial,
    successorPlannedSettlementProjection: reschedule
      ? input.successorPlannedSettlement ?? plannedSettlementProjection(
          input.dto.successorFinancialDecision!,
        )
      : null,
  });
}

export function bulkTransitionFingerprint(
  dto: BulkTransitionDto,
  items: BulkFingerprintItem[],
): string {
  return fingerprintPayload({
    reasonCode: dto.reasonCode?.trim() || "manual",
    reasonText: dto.reasonText.trim(),
    items: items.map((item) => ({
      lessonId: item.lessonId,
      operation: item.operation,
      transitionFingerprint: item.preview.transitionFingerprint,
    })),
  });
}

export const bulkTransitionItemDto = (
  bulk: BulkTransitionDto,
  item: BulkTransitionItem,
): TransitionPreviewDto => {
  const common = {
    expectedVersion: item.expectedVersion,
    reasonCode: bulk.reasonCode,
    reasonText: bulk.reasonText,
  };
  return item.operation === "reschedule"
    ? {
        ...common,
        operation: "reschedule",
        successor: item.successor!,
        sourceFinancialDecision: item.sourceFinancialDecision!,
        successorFinancialDecision: item.successorFinancialDecision!,
      }
    : {
        ...common,
        operation: item.operation,
        financialDecision: item.financialDecision!,
      };
};

export const bulkTransitionPreviewId = (items: BulkTransitionItem[]) =>
  stableTransitionId(
    `schedule.lesson.bulk-preview\0${fingerprintPayload(items.map((item) => ({
      lessonId: item.lessonId,
      operation: item.operation,
      expectedVersion: item.expectedVersion,
    })))}`,
  );

export const selectedTransitionSubscriptionIds = (dto: TransitionPreviewDto) =>
  ((dto.successorFinancialDecision ?? dto.financialDecision)?.clientDecisions ?? [])
    .map((decision) => decision.subscriptionId)
    .filter((id): id is string => Boolean(id));

export const transitionFinancialProjection = (
  settled: { clientFacts: Array<{ id: string } & Record<string, unknown>>; teacherFact: { id: string } & Record<string, unknown> },
): TransitionFinancialProjection => ({
  clientFacts: settled.clientFacts.map(({ id: _id, ...fact }) => fact) as TransitionFinancialProjection["clientFacts"],
  teacherFact: (({ id: _id, ...fact }) => fact)(settled.teacherFact) as TransitionFinancialProjection["teacherFact"],
});

export const requiredTransitionClientIds = (source: TransitionSource) => {
  const excluded = new Set(source.excludedParticipantIds);
  const ids = source.groupId
    ? source.participants
      .map((participant) => participant.studentId)
      .filter((studentId) => !excluded.has(studentId))
    : source.snapshot
      ? [source.snapshot.clientId]
      : [];
  return [...new Set(ids)].sort();
};

export const completedTransitionReversalDecision = (
  requiredClientIds: string[],
): LessonFinancialDecision => ({
  settlementTypeKey: "free_lesson",
  teacherCompensationRuleKey: "none",
  clientDecisions: requiredClientIds.map((clientId) => ({
    clientId,
    chargeType: "none",
    chargeDurationMinutes: 0,
  })),
});

export const transitionDecisionForResolution = (
  decision: LessonFinancialDecision,
  preservesTeacherDecision: boolean,
): LessonFinancialDecision => {
  const legacyAutomatic =
    decision.teacherCompensationSource === undefined &&
    decision.teacherCompensationValueMinor === undefined &&
    decision.teacherCreditedDurationMinutes === undefined &&
    [undefined, "none", "standard"].includes(
      decision.teacherCompensationRuleKey,
    );
  if (!preservesTeacherDecision || !legacyAutomatic) return decision;
  const {
    teacherCompensationRuleKey: _rule,
    teacherCompensationValueMinor: _value,
    teacherCreditedDurationMinutes: _duration,
    teacherCompensationSource: _source,
    ...clientDecision
  } = decision;
  return clientDecision as LessonFinancialDecision;
};

export const legacyPlanTeacherSource = (
  decision: LessonFinancialDecision,
): "automatic" | "manual" =>
  decision.teacherCompensationValueMinor !== undefined ||
      !["none", "standard"].includes(decision.teacherCompensationRuleKey)
    ? "manual"
    : "automatic";

export const legacySnapshotTeacherDecision = (
  source: TransitionSource,
): Pick<
  LessonFinancialDecision,
  | "teacherCompensationRuleKey"
  | "teacherCompensationValueMinor"
  | "teacherCompensationSource"
> | undefined => {
  const snapshot = source.groupId ? source.groupSnapshot : source.snapshot;
  if (!snapshot) return undefined;
  return {
    teacherCompensationRuleKey: snapshot.teacherCompensationType,
    teacherCompensationValueMinor:
      snapshot.teacherCompensationType === "none"
        ? undefined
        : rublesToMinor(snapshot.teacherCompensationValue.toString()).toString(),
    teacherCompensationSource: "manual",
  };
};

export const effectiveTransitionDto = (
  source: TransitionSource,
  dto: TransitionPreviewDto,
  operation: TransitionOperation,
): TransitionPreviewDto =>
  operation === "reschedule" && source.lifecycleState === "successfully_completed" &&
      !dto.sourceFinancialDecision
    ? {
        ...dto,
        financialDecision: completedTransitionReversalDecision(
          requiredTransitionClientIds(source),
        ),
      }
    : dto;

export const hasTransitionClientCharge = (financial: TransitionFinancialProjection) =>
  financial.clientFacts.some(
    (fact) => BigInt(fact.amountMinor) > 0n || Number(fact.units) > 0,
  );
