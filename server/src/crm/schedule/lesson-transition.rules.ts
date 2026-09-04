import { UnprocessableEntityException } from "@nestjs/common";
import { createHash } from "node:crypto";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import type { LessonFinancialDecision } from "../commerce/lesson-settlement.port";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import type {
  BulkFingerprintItem,
  BulkTransitionDto,
  BulkTransitionItem,
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

const assertBulkItem = (
  item: BulkTransitionItem,
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
    !validId || !validVersion || !validOperation || !item.financialDecision ||
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
  return [...dto.items].sort((left, right) =>
    left.lessonId.localeCompare(right.lessonId)
  );
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

export const normalizedTransitionDecision = (dto: TransitionPreviewDto) => ({
  settlementTypeKey: dto.financialDecision.settlementTypeKey,
  clientDecisions: [...(dto.financialDecision.clientDecisions ?? [])]
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
    dto.financialDecision.teacherCompensationRuleKey,
  teacherCompensationValueMinor:
    nullableDecisionValue(dto.financialDecision.teacherCompensationValueMinor),
  teacherCreditedDurationMinutes:
    nullableDecisionValue(
      dto.financialDecision.teacherCreditedDurationMinutes,
    ),
  teacherCompensationSource:
    nullableDecisionValue(dto.financialDecision.teacherCompensationSource),
});

export function transitionFingerprint(input: TransitionFingerprintInput): string {
  return fingerprintPayload({
    operation: input.operation,
    source: sourceProjection(input.source),
    successor: input.successor ? draftProjection(input.successor) : null,
    reasonCode: transitionReasonCode(input.dto),
    reasonText: input.dto.reasonText?.trim() ?? null,
    financialDecision: normalizedTransitionDecision(input.dto),
    coverage: input.coverage,
    financial: input.financial,
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
    financialDecision: item.financialDecision,
  };
  return item.operation === "reschedule"
    ? { ...common, successor: item.successor! }
    : common;
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
  (dto.financialDecision.clientDecisions ?? [])
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

export const effectiveTransitionDto = (
  source: TransitionSource,
  dto: TransitionPreviewDto,
  operation: TransitionOperation,
): TransitionPreviewDto =>
  operation === "reschedule" && source.lifecycleState === "successfully_completed"
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
