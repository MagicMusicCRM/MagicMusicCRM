import { createHmac, timingSafeEqual } from "node:crypto";

const TOKEN_VERSION = "v1";
const REPLACE_TOKEN_DOMAIN = "magicmusiccrm:subscription-replace-preview:v1";
const CANCEL_TOKEN_DOMAIN = "magicmusiccrm:subscription-cancel-preview:v1";
const PURCHASE_TOKEN_DOMAIN = "magicmusiccrm:subscription-purchase-preview:v1";
const PAYMENT_REVERSAL_TOKEN_DOMAIN =
  "magicmusiccrm:payment-reversal-preview:v1";
const PAYMENT_CORRECTION_TOKEN_DOMAIN =
  "magicmusiccrm:payment-correction-preview:v1";
const ACCOUNT_ADJUSTMENT_REVERSAL_TOKEN_DOMAIN =
  "magicmusiccrm:account-adjustment-reversal-preview:v1";
const LESSON_TRANSITION_TOKEN_DOMAIN =
  "magicmusiccrm:lesson-transition-preview:v1";
const SCHEDULE_PLAN_END_TOKEN_DOMAIN =
  "magicmusiccrm:schedule-plan-end-preview:v1";
const SCHEDULE_PLAN_ROW_REMOVAL_TOKEN_DOMAIN =
  "magicmusiccrm:schedule-plan-row-removal-preview:v1";
const SCHEDULE_PLAN_HISTORY_TOKEN_DOMAIN =
  "magicmusiccrm:schedule-plan-history-preview:v1";

export interface SchedulePlanHistoryPreviewTokenPayload {
  kind: "schedule.plan.history";
  operation: "create" | "update";
  actorUserId: string;
  planId: string | null;
  expectedVersion: number;
  activeFrom: string;
  activeUntil: string | null;
  clientFingerprint: string;
  draftFingerprint: string;
  historyFingerprint: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface SchedulePlanEndPreviewTokenPayload {
  kind: "schedule.plan.end";
  actorUserId: string;
  planId: string;
  expectedVersion: number;
  lastDate: string;
  impactFingerprint: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface SchedulePlanRowRemovalPreviewTokenPayload {
  kind: "schedule.plan.row.remove";
  actorUserId: string;
  planId: string;
  seriesId: string;
  expectedVersion: number;
  effectiveFrom: string;
  impactFingerprint: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface LessonTransitionPreviewTokenPayload {
  kind: "lesson.transition";
  operation:
    | "reschedule"
    | "cancel"
    | "settle"
    | "bulk"
    | "correct"
    | "planned-settlement";
  actorUserId: string;
  lessonId: string;
  expectedVersion: number;
  transitionFingerprint: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface PaymentReversalPreviewTokenPayload {
  kind: "payment.reversal";
  actorUserId: string;
  studentId: string;
  recipientStudentId: string;
  paymentRecordId: string;
  expectedVersion: number;
  status: "unpaid" | "posted_pending" | "paid";
  actualPaymentId: string | null;
  issuedSubscriptionId: string | null;
  amountMinor: string;
  currencyCode: string;
  walletBalanceMinor: string;
  resultingBalanceMinor: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface PaymentCorrectionPreviewTokenPayload {
  kind: "payment.correction";
  actorUserId: string;
  studentId: string;
  recipientStudentId: string;
  paymentRecordId: string;
  expectedVersion: number;
  oldStatus: "unpaid" | "posted_pending" | "paid";
  oldActualPaymentId: string | null;
  issuedSubscriptionId: string | null;
  installmentId: string | null;
  oldAmountMinor: string;
  currencyCode: string;
  amountMinor: string;
  status: "unpaid" | "posted_pending" | "paid";
  dueAt: string | null;
  method: "cash" | "cashless" | null;
  externalIdentifier: string | null;
  occurredAt: string | null;
  branchId: string | null;
  verificationNote: string | null;
  walletBalanceMinor: string;
  resultingBalanceMinor: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface AccountAdjustmentReversalPreviewTokenPayload {
  kind: "account.adjustment.reversal";
  actorUserId: string;
  studentId: string;
  adjustmentId: string;
  expectedVersion: number;
  sourcePaymentId: string;
  amountMinor: string;
  currencyCode: string;
  walletBalanceMinor: string;
  resultingBalanceMinor: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface SubscriptionPurchasePreviewTokenPayload {
  kind: "subscription.purchase";
  actorUserId: string;
  recipientStudentId: string;
  payerStudentId: string;
  recipientVersion: number;
  payerVersion: number;
  recipientBranchId: string | null;
  payerBranchId: string | null;
  packageId: string;
  packageVersion: number;
  currencyCode: string;
  finalPriceMinor: string;
  payerBalanceMinor: string;
  fundingMode: "personal_account" | "installment";
  purchaseFingerprint: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface SubscriptionReplacePreviewTokenPayload {
  kind: "subscription.replace";
  actorUserId: string;
  studentId: string;
  payerStudentId: string;
  issuedSubscriptionId: string;
  expectedVersion: number;
  newPackageId: string;
  newPackageVersion: number;
  currencyCode: string;
  usedUnits: string;
  reservedLessonCount: number;
  reservedUnits: string;
  transferableReservationCount: number;
  transferableReservationUnits: string;
  releasedReservationCount: number;
  releasedReservationUnits: string;
  reservationPlanFingerprint: string;
  futureLessonCount: number;
  futureUnits: string;
  oldFinalMinor: string;
  newFinalMinor: string;
  actualPaidMinor: string;
  deltaMinor: string;
  positionKind: "debt" | "overpayment" | "settled";
  positionMinor: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export interface SubscriptionCancelPreviewTokenPayload {
  kind: "subscription.cancel";
  actorUserId: string;
  studentId: string;
  payerStudentId: string;
  issuedSubscriptionId: string;
  expectedVersion: number;
  packageId: string;
  packageVersion: number;
  unitCount: string;
  usedUnits: string;
  currencyCode: string;
  finalMinor: string;
  actualPaidMinor: string;
  fundingMode: "personal_account" | "installment" | "legacy";
  previousRefundMinor: string;
  writeoffMinor: string;
  balanceMinor: string;
  openPaymentRecordCount: number;
  openPaymentRecordMinor: string;
  futureLessonCount: number;
  reservedLessonCount: number;
  reservedUnits: string;
  impactFingerprint: string;
  issuedAtSeconds: number;
  expiresAtSeconds: number;
}

export type SubscriptionPreviewTokenErrorCode =
  "PREVIEW_TOKEN_INVALID" | "PREVIEW_TOKEN_EXPIRED";

export class SubscriptionPreviewTokenError extends Error {
  constructor(readonly code: SubscriptionPreviewTokenErrorCode) {
    super(code);
    this.name = "SubscriptionPreviewTokenError";
  }
}

export function signSubscriptionReplacePreview(
  secret: string,
  payload: SubscriptionReplacePreviewTokenPayload,
): string {
  return signPayload(
    secret,
    REPLACE_TOKEN_DOMAIN,
    payload,
    assertReplacePayload,
  );
}

export function verifySubscriptionReplacePreview(
  secret: string,
  token: string,
  nowSeconds: number,
): SubscriptionReplacePreviewTokenPayload {
  return verifyPayload(
    secret,
    REPLACE_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertReplacePayload,
  );
}

export function signSubscriptionCancelPreview(
  secret: string,
  payload: SubscriptionCancelPreviewTokenPayload,
): string {
  return signPayload(secret, CANCEL_TOKEN_DOMAIN, payload, assertCancelPayload);
}

export function verifySubscriptionCancelPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): SubscriptionCancelPreviewTokenPayload {
  return verifyPayload(
    secret,
    CANCEL_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertCancelPayload,
  );
}

export function signSubscriptionPurchasePreview(
  secret: string,
  payload: SubscriptionPurchasePreviewTokenPayload,
): string {
  return signPayload(
    secret,
    PURCHASE_TOKEN_DOMAIN,
    payload,
    assertPurchasePayload,
  );
}

export function verifySubscriptionPurchasePreview(
  secret: string,
  token: string,
  nowSeconds: number,
): SubscriptionPurchasePreviewTokenPayload {
  return verifyPayload(
    secret,
    PURCHASE_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertPurchasePayload,
  );
}

export function signPaymentReversalPreview(
  secret: string,
  payload: PaymentReversalPreviewTokenPayload,
): string {
  return signPayload(
    secret,
    PAYMENT_REVERSAL_TOKEN_DOMAIN,
    payload,
    assertPaymentReversalPayload,
  );
}

export function verifyPaymentReversalPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): PaymentReversalPreviewTokenPayload {
  return verifyPayload(
    secret,
    PAYMENT_REVERSAL_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertPaymentReversalPayload,
  );
}

export function signPaymentCorrectionPreview(
  secret: string,
  payload: PaymentCorrectionPreviewTokenPayload,
): string {
  return signPayload(
    secret,
    PAYMENT_CORRECTION_TOKEN_DOMAIN,
    payload,
    assertPaymentCorrectionPayload,
  );
}

export function verifyPaymentCorrectionPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): PaymentCorrectionPreviewTokenPayload {
  return verifyPayload(
    secret,
    PAYMENT_CORRECTION_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertPaymentCorrectionPayload,
  );
}

export function signAccountAdjustmentReversalPreview(
  secret: string,
  payload: AccountAdjustmentReversalPreviewTokenPayload,
): string {
  return signPayload(
    secret,
    ACCOUNT_ADJUSTMENT_REVERSAL_TOKEN_DOMAIN,
    payload,
    assertAccountAdjustmentReversalPayload,
  );
}

export function verifyAccountAdjustmentReversalPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): AccountAdjustmentReversalPreviewTokenPayload {
  return verifyPayload(
    secret,
    ACCOUNT_ADJUSTMENT_REVERSAL_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertAccountAdjustmentReversalPayload,
  );
}

export function signLessonTransitionPreview(
  secret: string,
  payload: LessonTransitionPreviewTokenPayload,
): string {
  return signPayload(
    secret,
    LESSON_TRANSITION_TOKEN_DOMAIN,
    payload,
    assertLessonTransitionPayload,
  );
}

export function verifyLessonTransitionPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): LessonTransitionPreviewTokenPayload {
  return verifyPayload(
    secret,
    LESSON_TRANSITION_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertLessonTransitionPayload,
  );
}

export function signSchedulePlanEndPreview(
  secret: string,
  payload: SchedulePlanEndPreviewTokenPayload,
): string {
  return signPayload(
    secret,
    SCHEDULE_PLAN_END_TOKEN_DOMAIN,
    payload,
    assertSchedulePlanEndPayload,
  );
}

export function verifySchedulePlanEndPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): SchedulePlanEndPreviewTokenPayload {
  return verifyPayload(
    secret,
    SCHEDULE_PLAN_END_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertSchedulePlanEndPayload,
  );
}

export function signSchedulePlanRowRemovalPreview(
  secret: string,
  payload: SchedulePlanRowRemovalPreviewTokenPayload,
): string {
  return signPayload(
    secret,
    SCHEDULE_PLAN_ROW_REMOVAL_TOKEN_DOMAIN,
    payload,
    assertSchedulePlanRowRemovalPayload,
  );
}

export function verifySchedulePlanRowRemovalPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): SchedulePlanRowRemovalPreviewTokenPayload {
  return verifyPayload(
    secret,
    SCHEDULE_PLAN_ROW_REMOVAL_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertSchedulePlanRowRemovalPayload,
  );
}

export function signSchedulePlanHistoryPreview(
  secret: string,
  payload: SchedulePlanHistoryPreviewTokenPayload,
): string {
  return signPayload(
    secret,
    SCHEDULE_PLAN_HISTORY_TOKEN_DOMAIN,
    payload,
    assertSchedulePlanHistoryPayload,
  );
}

export function verifySchedulePlanHistoryPreview(
  secret: string,
  token: string,
  nowSeconds: number,
): SchedulePlanHistoryPreviewTokenPayload {
  return verifyPayload(
    secret,
    SCHEDULE_PLAN_HISTORY_TOKEN_DOMAIN,
    token,
    nowSeconds,
    assertSchedulePlanHistoryPayload,
  );
}

type PreviewPayload = Record<string, unknown>;

type PreviewPayloadRule = readonly [
  key: string,
  isInvalid: (payload: PreviewPayload) => boolean,
];

function asPreviewPayload(value: unknown): PreviewPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  return value as PreviewPayload;
}

function assertExactPayload(
  value: unknown,
  expectedKind: string,
  rules: readonly PreviewPayloadRule[],
): void {
  const payload = asPreviewPayload(value);
  const exactKeys = [
    "kind",
    ...rules.map((rule) => rule[0]),
    "issuedAtSeconds",
    "expiresAtSeconds",
  ];
  if (
    Object.keys(payload).length !== exactKeys.length ||
    exactKeys.some((key) => !(key in payload)) ||
    payload.kind !== expectedKind ||
    rules.some((rule) => rule[1](payload)) ||
    !isPositiveInteger(payload.issuedAtSeconds) ||
    !isPositiveInteger(payload.expiresAtSeconds) ||
    payload.expiresAtSeconds < payload.issuedAtSeconds
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
}

const schedulePlanEndRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["planId", (payload) => !isUuid(payload.planId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  [
    "lastDate",
    (payload) =>
      typeof payload.lastDate !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(payload.lastDate),
  ],
  [
    "impactFingerprint",
    (payload) =>
      typeof payload.impactFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/.test(payload.impactFingerprint),
  ],
];

function assertSchedulePlanEndPayload(
  value: unknown,
): asserts value is SchedulePlanEndPreviewTokenPayload {
  assertExactPayload(value, "schedule.plan.end", schedulePlanEndRules);
}

const schedulePlanRowRemovalRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["planId", (payload) => !isUuid(payload.planId)],
  ["seriesId", (payload) => !isUuid(payload.seriesId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  ["effectiveFrom", (payload) => !isDateOnly(payload.effectiveFrom)],
  ["impactFingerprint", (payload) => !isFingerprint(payload.impactFingerprint)],
];

function assertSchedulePlanRowRemovalPayload(
  value: unknown,
): asserts value is SchedulePlanRowRemovalPreviewTokenPayload {
  assertExactPayload(
    value,
    "schedule.plan.row.remove",
    schedulePlanRowRemovalRules,
  );
}

const schedulePlanHistoryRules: readonly PreviewPayloadRule[] = [
  [
    "operation",
    (payload) => !["create", "update"].includes(payload.operation as string),
  ],
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["planId", (payload) => payload.planId !== null && !isUuid(payload.planId)],
  [
    "expectedVersion",
    (payload) => !isNonnegativeInteger(payload.expectedVersion),
  ],
  ["activeFrom", (payload) => !isDateOnly(payload.activeFrom)],
  [
    "activeUntil",
    (payload) =>
      payload.activeUntil !== null && !isDateOnly(payload.activeUntil),
  ],
  ["clientFingerprint", (payload) => !isFingerprint(payload.clientFingerprint)],
  ["draftFingerprint", (payload) => !isFingerprint(payload.draftFingerprint)],
  [
    "historyFingerprint",
    (payload) => !isFingerprint(payload.historyFingerprint),
  ],
];

function assertSchedulePlanHistoryPayload(
  value: unknown,
): asserts value is SchedulePlanHistoryPreviewTokenPayload {
  assertExactPayload(value, "schedule.plan.history", schedulePlanHistoryRules);
}

function signPayload<T>(
  secret: string,
  domain: string,
  payload: T,
  assert: (value: unknown) => asserts value is T,
): string {
  assertSecret(secret);
  assert(payload);
  const body = Buffer.from(JSON.stringify(payload), "utf8").toString(
    "base64url",
  );
  return [
    TOKEN_VERSION,
    body,
    signature(secret, domain, body).toString("base64url"),
  ].join(".");
}

function verifyPayload<T>(
  secret: string,
  domain: string,
  token: string,
  nowSeconds: number,
  assert: (value: unknown) => asserts value is T & {
    expiresAtSeconds: number;
  },
): T {
  assertSecret(secret);
  if (token.length > 16_384) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== TOKEN_VERSION) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const body = parts[1]!;
  const provided = decodeBase64Url(parts[2]!);
  const expected = signature(secret, domain, body);
  if (
    provided.length !== expected.length ||
    !timingSafeEqual(provided, expected)
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  let payload: unknown;
  try {
    payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  } catch {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  assert(payload);
  if (payload.expiresAtSeconds < nowSeconds) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_EXPIRED");
  }
  return payload;
}

function signature(secret: string, domain: string, body: string): Buffer {
  return createHmac("sha256", secret).update(`${domain}.${body}`).digest();
}

function decodeBase64Url(value: string): Buffer {
  if (!/^[A-Za-z0-9_-]{43}$/.test(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  return Buffer.from(value, "base64url");
}

function assertSecret(secret: string): void {
  if (Buffer.byteLength(secret, "utf8") < 32) {
    throw new Error(
      "Subscription preview token secret must be at least 32 bytes.",
    );
  }
}

const replaceRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["studentId", (payload) => !isUuid(payload.studentId)],
  ["payerStudentId", (payload) => !isUuid(payload.payerStudentId)],
  ["issuedSubscriptionId", (payload) => !isUuid(payload.issuedSubscriptionId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  ["newPackageId", (payload) => !isUuid(payload.newPackageId)],
  [
    "newPackageVersion",
    (payload) => !isPositiveInteger(payload.newPackageVersion),
  ],
  [
    "currencyCode",
    (payload) =>
      typeof payload.currencyCode !== "string" ||
      !/^[A-Z]{3}$/.test(payload.currencyCode),
  ],
  ["usedUnits", (payload) => !isUnits(payload.usedUnits)],
  [
    "reservedLessonCount",
    (payload) => !isNonnegativeInteger(payload.reservedLessonCount),
  ],
  ["reservedUnits", (payload) => !isUnits(payload.reservedUnits)],
  [
    "transferableReservationCount",
    (payload) => !isNonnegativeInteger(payload.transferableReservationCount),
  ],
  [
    "transferableReservationUnits",
    (payload) => !isUnits(payload.transferableReservationUnits),
  ],
  [
    "releasedReservationCount",
    (payload) => !isNonnegativeInteger(payload.releasedReservationCount),
  ],
  [
    "releasedReservationUnits",
    (payload) => !isUnits(payload.releasedReservationUnits),
  ],
  [
    "reservationPlanFingerprint",
    (payload) =>
      typeof payload.reservationPlanFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/.test(payload.reservationPlanFingerprint),
  ],
  [
    "futureLessonCount",
    (payload) => !isNonnegativeInteger(payload.futureLessonCount),
  ],
  ["futureUnits", (payload) => !isUnits(payload.futureUnits)],
  ["oldFinalMinor", (payload) => !isMinor(payload.oldFinalMinor)],
  ["newFinalMinor", (payload) => !isMinor(payload.newFinalMinor)],
  ["actualPaidMinor", (payload) => !isMinor(payload.actualPaidMinor)],
  ["deltaMinor", (payload) => !isSignedMinor(payload.deltaMinor)],
  [
    "positionKind",
    (payload) =>
      !["debt", "overpayment", "settled"].includes(
        payload.positionKind as string,
      ),
  ],
  ["positionMinor", (payload) => !isMinor(payload.positionMinor)],
];

function assertReplacePayload(
  value: unknown,
): asserts value is SubscriptionReplacePreviewTokenPayload {
  assertExactPayload(value, "subscription.replace", replaceRules);
}

const cancelRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["studentId", (payload) => !isUuid(payload.studentId)],
  ["payerStudentId", (payload) => !isUuid(payload.payerStudentId)],
  ["issuedSubscriptionId", (payload) => !isUuid(payload.issuedSubscriptionId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  ["packageId", (payload) => !isUuid(payload.packageId)],
  ["packageVersion", (payload) => !isPositiveInteger(payload.packageVersion)],
  ["unitCount", (payload) => !isUnits(payload.unitCount)],
  ["usedUnits", (payload) => !isUnits(payload.usedUnits)],
  [
    "currencyCode",
    (payload) =>
      typeof payload.currencyCode !== "string" ||
      !/^[A-Z]{3}$/.test(payload.currencyCode),
  ],
  ["finalMinor", (payload) => !isMinor(payload.finalMinor)],
  ["actualPaidMinor", (payload) => !isMinor(payload.actualPaidMinor)],
  [
    "fundingMode",
    (payload) =>
      !["personal_account", "installment", "legacy"].includes(
        payload.fundingMode as string,
      ),
  ],
  ["previousRefundMinor", (payload) => !isMinor(payload.previousRefundMinor)],
  ["writeoffMinor", (payload) => !isMinor(payload.writeoffMinor)],
  ["balanceMinor", (payload) => !isSignedMinor(payload.balanceMinor)],
  [
    "openPaymentRecordCount",
    (payload) => !isNonnegativeInteger(payload.openPaymentRecordCount),
  ],
  [
    "openPaymentRecordMinor",
    (payload) => !isMinor(payload.openPaymentRecordMinor),
  ],
  [
    "futureLessonCount",
    (payload) => !isNonnegativeInteger(payload.futureLessonCount),
  ],
  [
    "reservedLessonCount",
    (payload) => !isNonnegativeInteger(payload.reservedLessonCount),
  ],
  ["reservedUnits", (payload) => !isUnits(payload.reservedUnits)],
  [
    "impactFingerprint",
    (payload) =>
      typeof payload.impactFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/.test(payload.impactFingerprint),
  ],
];

function assertCancelPayload(
  value: unknown,
): asserts value is SubscriptionCancelPreviewTokenPayload {
  assertExactPayload(value, "subscription.cancel", cancelRules);
}

const purchaseRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["recipientStudentId", (payload) => !isUuid(payload.recipientStudentId)],
  ["payerStudentId", (payload) => !isUuid(payload.payerStudentId)],
  [
    "recipientVersion",
    (payload) => !isPositiveInteger(payload.recipientVersion),
  ],
  ["payerVersion", (payload) => !isPositiveInteger(payload.payerVersion)],
  [
    "recipientBranchId",
    (payload) =>
      payload.recipientBranchId !== null && !isUuid(payload.recipientBranchId),
  ],
  [
    "payerBranchId",
    (payload) =>
      payload.payerBranchId !== null && !isUuid(payload.payerBranchId),
  ],
  ["packageId", (payload) => !isUuid(payload.packageId)],
  ["packageVersion", (payload) => !isPositiveInteger(payload.packageVersion)],
  [
    "currencyCode",
    (payload) =>
      typeof payload.currencyCode !== "string" ||
      !/^[A-Z]{3}$/.test(payload.currencyCode),
  ],
  ["finalPriceMinor", (payload) => !isMinor(payload.finalPriceMinor)],
  ["payerBalanceMinor", (payload) => !isSignedMinor(payload.payerBalanceMinor)],
  [
    "fundingMode",
    (payload) =>
      !["personal_account", "installment"].includes(
        payload.fundingMode as string,
      ),
  ],
  [
    "purchaseFingerprint",
    (payload) =>
      typeof payload.purchaseFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/.test(payload.purchaseFingerprint),
  ],
];

function assertPurchasePayload(
  value: unknown,
): asserts value is SubscriptionPurchasePreviewTokenPayload {
  assertExactPayload(value, "subscription.purchase", purchaseRules);
}

const paymentReversalRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["studentId", (payload) => !isUuid(payload.studentId)],
  ["recipientStudentId", (payload) => !isUuid(payload.recipientStudentId)],
  ["paymentRecordId", (payload) => !isUuid(payload.paymentRecordId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  [
    "status",
    (payload) =>
      !["unpaid", "posted_pending", "paid"].includes(payload.status as string),
  ],
  [
    "actualPaymentId",
    (payload) =>
      payload.actualPaymentId !== null && !isUuid(payload.actualPaymentId),
  ],
  [
    "issuedSubscriptionId",
    (payload) =>
      payload.issuedSubscriptionId !== null &&
      !isUuid(payload.issuedSubscriptionId),
  ],
  [
    "amountMinor",
    (payload) => !isMinor(payload.amountMinor) || payload.amountMinor === "0",
  ],
  [
    "currencyCode",
    (payload) =>
      typeof payload.currencyCode !== "string" ||
      !/^[A-Z]{3}$/.test(payload.currencyCode),
  ],
  [
    "walletBalanceMinor",
    (payload) => !isSignedMinor(payload.walletBalanceMinor),
  ],
  [
    "resultingBalanceMinor",
    (payload) => !isSignedMinor(payload.resultingBalanceMinor),
  ],
];

function assertPaymentReversalPayload(
  value: unknown,
): asserts value is PaymentReversalPreviewTokenPayload {
  assertExactPayload(value, "payment.reversal", paymentReversalRules);
}

const paymentCorrectionRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["studentId", (payload) => !isUuid(payload.studentId)],
  ["recipientStudentId", (payload) => !isUuid(payload.recipientStudentId)],
  ["paymentRecordId", (payload) => !isUuid(payload.paymentRecordId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  [
    "oldStatus",
    (payload) =>
      !["unpaid", "posted_pending", "paid"].includes(
        payload.oldStatus as string,
      ),
  ],
  [
    "oldActualPaymentId",
    (payload) =>
      payload.oldActualPaymentId !== null &&
      !isUuid(payload.oldActualPaymentId),
  ],
  [
    "issuedSubscriptionId",
    (payload) =>
      payload.issuedSubscriptionId !== null &&
      !isUuid(payload.issuedSubscriptionId),
  ],
  [
    "installmentId",
    (payload) =>
      payload.installmentId !== null && !isUuid(payload.installmentId),
  ],
  [
    "oldAmountMinor",
    (payload) =>
      !isMinor(payload.oldAmountMinor) || payload.oldAmountMinor === "0",
  ],
  [
    "currencyCode",
    (payload) =>
      typeof payload.currencyCode !== "string" ||
      !/^[A-Z]{3}$/.test(payload.currencyCode),
  ],
  [
    "amountMinor",
    (payload) => !isMinor(payload.amountMinor) || payload.amountMinor === "0",
  ],
  [
    "status",
    (payload) =>
      !["unpaid", "posted_pending", "paid"].includes(payload.status as string),
  ],
  [
    "dueAt",
    (payload) => payload.dueAt !== null && typeof payload.dueAt !== "string",
  ],
  [
    "method",
    (payload) =>
      payload.method !== null &&
      !["cash", "cashless"].includes(payload.method as string),
  ],
  [
    "externalIdentifier",
    (payload) =>
      payload.externalIdentifier !== null &&
      typeof payload.externalIdentifier !== "string",
  ],
  [
    "occurredAt",
    (payload) =>
      payload.occurredAt !== null && typeof payload.occurredAt !== "string",
  ],
  [
    "branchId",
    (payload) => payload.branchId !== null && !isUuid(payload.branchId),
  ],
  [
    "verificationNote",
    (payload) =>
      payload.verificationNote !== null &&
      typeof payload.verificationNote !== "string",
  ],
  [
    "walletBalanceMinor",
    (payload) => !isSignedMinor(payload.walletBalanceMinor),
  ],
  [
    "resultingBalanceMinor",
    (payload) => !isSignedMinor(payload.resultingBalanceMinor),
  ],
];

function assertPaymentCorrectionPayload(
  value: unknown,
): asserts value is PaymentCorrectionPreviewTokenPayload {
  assertExactPayload(value, "payment.correction", paymentCorrectionRules);
}

const accountAdjustmentReversalRules: readonly PreviewPayloadRule[] = [
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["studentId", (payload) => !isUuid(payload.studentId)],
  ["adjustmentId", (payload) => !isUuid(payload.adjustmentId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  ["sourcePaymentId", (payload) => !isUuid(payload.sourcePaymentId)],
  [
    "amountMinor",
    (payload) =>
      !isSignedMinor(payload.amountMinor) || payload.amountMinor === "0",
  ],
  [
    "currencyCode",
    (payload) =>
      typeof payload.currencyCode !== "string" ||
      !/^[A-Z]{3}$/.test(payload.currencyCode),
  ],
  [
    "walletBalanceMinor",
    (payload) => !isSignedMinor(payload.walletBalanceMinor),
  ],
  [
    "resultingBalanceMinor",
    (payload) => !isSignedMinor(payload.resultingBalanceMinor),
  ],
];

function assertAccountAdjustmentReversalPayload(
  value: unknown,
): asserts value is AccountAdjustmentReversalPreviewTokenPayload {
  assertExactPayload(
    value,
    "account.adjustment.reversal",
    accountAdjustmentReversalRules,
  );
}

const lessonTransitionRules: readonly PreviewPayloadRule[] = [
  [
    "operation",
    (payload) =>
      ![
        "reschedule",
        "cancel",
        "settle",
        "bulk",
        "correct",
        "planned-settlement",
      ].includes(payload.operation as string),
  ],
  ["actorUserId", (payload) => !isUuid(payload.actorUserId)],
  ["lessonId", (payload) => !isUuid(payload.lessonId)],
  ["expectedVersion", (payload) => !isPositiveInteger(payload.expectedVersion)],
  [
    "transitionFingerprint",
    (payload) =>
      typeof payload.transitionFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/.test(payload.transitionFingerprint),
  ],
];

function assertLessonTransitionPayload(
  value: unknown,
): asserts value is LessonTransitionPreviewTokenPayload {
  assertExactPayload(value, "lesson.transition", lessonTransitionRules);
}

function isUuid(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}

function isPositiveInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) > 0;
}

function isNonnegativeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function isMinor(value: unknown): value is string {
  return typeof value === "string" && /^(0|[1-9]\d*)$/.test(value);
}

function isSignedMinor(value: unknown): value is string {
  return typeof value === "string" && /^-?(0|[1-9]\d*)$/.test(value);
}

function isUnits(value: unknown): value is string {
  return typeof value === "string" && /^(0|[1-9]\d*)(\.\d{1,2})?$/.test(value);
}

function isDateOnly(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function isFingerprint(value: unknown): value is string {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}
