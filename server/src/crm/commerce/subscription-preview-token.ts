import { createHmac, timingSafeEqual } from "node:crypto";

const TOKEN_VERSION = "v1";
const REPLACE_TOKEN_DOMAIN =
  "magicmusiccrm:subscription-replace-preview:v1";
const CANCEL_TOKEN_DOMAIN =
  "magicmusiccrm:subscription-cancel-preview:v1";
const PURCHASE_TOKEN_DOMAIN =
  "magicmusiccrm:subscription-purchase-preview:v1";
const PAYMENT_REVERSAL_TOKEN_DOMAIN =
  "magicmusiccrm:payment-reversal-preview:v1";
const LESSON_TRANSITION_TOKEN_DOMAIN =
  "magicmusiccrm:lesson-transition-preview:v1";
const SCHEDULE_PLAN_END_TOKEN_DOMAIN =
  "magicmusiccrm:schedule-plan-end-preview:v1";

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

export interface LessonTransitionPreviewTokenPayload {
  kind: "lesson.transition";
  operation: "reschedule" | "cancel" | "settle" | "bulk";
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
  | "PREVIEW_TOKEN_INVALID"
  | "PREVIEW_TOKEN_EXPIRED";

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
  return signPayload(
    secret,
    CANCEL_TOKEN_DOMAIN,
    payload,
    assertCancelPayload,
  );
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

function assertSchedulePlanEndPayload(
  value: unknown,
): asserts value is SchedulePlanEndPreviewTokenPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const payload = value as Record<string, unknown>;
  const exactKeys = [
    "kind",
    "actorUserId",
    "planId",
    "expectedVersion",
    "lastDate",
    "impactFingerprint",
    "issuedAtSeconds",
    "expiresAtSeconds",
  ];
  if (
    Object.keys(payload).length !== exactKeys.length ||
    exactKeys.some((key) => !(key in payload)) ||
    payload.kind !== "schedule.plan.end" ||
    !isUuid(payload.actorUserId) ||
    !isUuid(payload.planId) ||
    !isPositiveInteger(payload.expectedVersion) ||
    typeof payload.lastDate !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(payload.lastDate) ||
    typeof payload.impactFingerprint !== "string" ||
    !/^[a-f0-9]{64}$/.test(payload.impactFingerprint) ||
    !isPositiveInteger(payload.issuedAtSeconds) ||
    !isPositiveInteger(payload.expiresAtSeconds) ||
    payload.expiresAtSeconds < payload.issuedAtSeconds
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
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
  return createHmac("sha256", secret)
    .update(`${domain}.${body}`)
    .digest();
}

function decodeBase64Url(value: string): Buffer {
  if (!/^[A-Za-z0-9_-]{43}$/.test(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  return Buffer.from(value, "base64url");
}

function assertSecret(secret: string): void {
  if (Buffer.byteLength(secret, "utf8") < 32) {
    throw new Error("Subscription preview token secret must be at least 32 bytes.");
  }
}

function assertReplacePayload(
  value: unknown,
): asserts value is SubscriptionReplacePreviewTokenPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const payload = value as Record<string, unknown>;
  const exactKeys = [
    "kind",
    "actorUserId",
    "studentId",
    "payerStudentId",
    "issuedSubscriptionId",
    "expectedVersion",
    "newPackageId",
    "newPackageVersion",
    "currencyCode",
    "usedUnits",
    "reservedLessonCount",
    "reservedUnits",
    "transferableReservationCount",
    "transferableReservationUnits",
    "releasedReservationCount",
    "releasedReservationUnits",
    "reservationPlanFingerprint",
    "futureLessonCount",
    "futureUnits",
    "oldFinalMinor",
    "newFinalMinor",
    "actualPaidMinor",
    "deltaMinor",
    "positionKind",
    "positionMinor",
    "issuedAtSeconds",
    "expiresAtSeconds",
  ];
  if (
    Object.keys(payload).length !== exactKeys.length ||
    exactKeys.some((key) => !(key in payload)) ||
    payload.kind !== "subscription.replace" ||
    !isUuid(payload.actorUserId) ||
    !isUuid(payload.studentId) ||
    !isUuid(payload.payerStudentId) ||
    !isUuid(payload.issuedSubscriptionId) ||
    !isPositiveInteger(payload.expectedVersion) ||
    !isUuid(payload.newPackageId) ||
    !isPositiveInteger(payload.newPackageVersion) ||
    typeof payload.currencyCode !== "string" ||
    !/^[A-Z]{3}$/.test(payload.currencyCode) ||
    !isUnits(payload.usedUnits) ||
    !isNonnegativeInteger(payload.reservedLessonCount) ||
    !isUnits(payload.reservedUnits) ||
    !isNonnegativeInteger(payload.transferableReservationCount) ||
    !isUnits(payload.transferableReservationUnits) ||
    !isNonnegativeInteger(payload.releasedReservationCount) ||
    !isUnits(payload.releasedReservationUnits) ||
    typeof payload.reservationPlanFingerprint !== "string" ||
    !/^[a-f0-9]{64}$/.test(payload.reservationPlanFingerprint) ||
    !isNonnegativeInteger(payload.futureLessonCount) ||
    !isUnits(payload.futureUnits) ||
    !isMinor(payload.oldFinalMinor) ||
    !isMinor(payload.newFinalMinor) ||
    !isMinor(payload.actualPaidMinor) ||
    !isSignedMinor(payload.deltaMinor) ||
    !["debt", "overpayment", "settled"].includes(
      payload.positionKind as string,
    ) ||
    !isMinor(payload.positionMinor) ||
    !isPositiveInteger(payload.issuedAtSeconds) ||
    !isPositiveInteger(payload.expiresAtSeconds) ||
    payload.expiresAtSeconds < payload.issuedAtSeconds
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
}

function assertCancelPayload(
  value: unknown,
): asserts value is SubscriptionCancelPreviewTokenPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const payload = value as Record<string, unknown>;
  const exactKeys = [
    "kind",
    "actorUserId",
    "studentId",
    "payerStudentId",
    "issuedSubscriptionId",
    "expectedVersion",
    "packageId",
    "packageVersion",
    "unitCount",
    "usedUnits",
    "currencyCode",
    "finalMinor",
    "actualPaidMinor",
    "fundingMode",
    "previousRefundMinor",
    "writeoffMinor",
    "balanceMinor",
    "openPaymentRecordCount",
    "openPaymentRecordMinor",
    "futureLessonCount",
    "reservedLessonCount",
    "reservedUnits",
    "impactFingerprint",
    "issuedAtSeconds",
    "expiresAtSeconds",
  ];
  if (
    Object.keys(payload).length !== exactKeys.length ||
    exactKeys.some((key) => !(key in payload)) ||
    payload.kind !== "subscription.cancel" ||
    !isUuid(payload.actorUserId) ||
    !isUuid(payload.studentId) ||
    !isUuid(payload.payerStudentId) ||
    !isUuid(payload.issuedSubscriptionId) ||
    !isPositiveInteger(payload.expectedVersion) ||
    !isUuid(payload.packageId) ||
    !isPositiveInteger(payload.packageVersion) ||
    !isUnits(payload.unitCount) ||
    !isUnits(payload.usedUnits) ||
    typeof payload.currencyCode !== "string" ||
    !/^[A-Z]{3}$/.test(payload.currencyCode) ||
    !isMinor(payload.finalMinor) ||
    !isMinor(payload.actualPaidMinor) ||
    !["personal_account", "installment", "legacy"].includes(
      payload.fundingMode as string,
    ) ||
    !isMinor(payload.previousRefundMinor) ||
    !isMinor(payload.writeoffMinor) ||
    !isSignedMinor(payload.balanceMinor) ||
    !isNonnegativeInteger(payload.openPaymentRecordCount) ||
    !isMinor(payload.openPaymentRecordMinor) ||
    !isNonnegativeInteger(payload.futureLessonCount) ||
    !isNonnegativeInteger(payload.reservedLessonCount) ||
    !isUnits(payload.reservedUnits) ||
    typeof payload.impactFingerprint !== "string" ||
    !/^[a-f0-9]{64}$/.test(payload.impactFingerprint) ||
    !isPositiveInteger(payload.issuedAtSeconds) ||
    !isPositiveInteger(payload.expiresAtSeconds) ||
    payload.expiresAtSeconds < payload.issuedAtSeconds
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
}

function assertPurchasePayload(
  value: unknown,
): asserts value is SubscriptionPurchasePreviewTokenPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const payload = value as Record<string, unknown>;
  const exactKeys = [
    "kind",
    "actorUserId",
    "recipientStudentId",
    "payerStudentId",
    "recipientVersion",
    "payerVersion",
    "recipientBranchId",
    "payerBranchId",
    "packageId",
    "packageVersion",
    "currencyCode",
    "finalPriceMinor",
    "payerBalanceMinor",
    "fundingMode",
    "purchaseFingerprint",
    "issuedAtSeconds",
    "expiresAtSeconds",
  ];
  if (
    Object.keys(payload).length !== exactKeys.length ||
    exactKeys.some((key) => !(key in payload)) ||
    payload.kind !== "subscription.purchase" ||
    !isUuid(payload.actorUserId) ||
    !isUuid(payload.recipientStudentId) ||
    !isUuid(payload.payerStudentId) ||
    !isPositiveInteger(payload.recipientVersion) ||
    !isPositiveInteger(payload.payerVersion) ||
    (payload.recipientBranchId !== null &&
      !isUuid(payload.recipientBranchId)) ||
    (payload.payerBranchId !== null && !isUuid(payload.payerBranchId)) ||
    !isUuid(payload.packageId) ||
    !isPositiveInteger(payload.packageVersion) ||
    typeof payload.currencyCode !== "string" ||
    !/^[A-Z]{3}$/.test(payload.currencyCode) ||
    !isMinor(payload.finalPriceMinor) ||
    !isSignedMinor(payload.payerBalanceMinor) ||
    !["personal_account", "installment"].includes(
      payload.fundingMode as string,
    ) ||
    typeof payload.purchaseFingerprint !== "string" ||
    !/^[a-f0-9]{64}$/.test(payload.purchaseFingerprint) ||
    !isPositiveInteger(payload.issuedAtSeconds) ||
    !isPositiveInteger(payload.expiresAtSeconds) ||
    payload.expiresAtSeconds < payload.issuedAtSeconds
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
}

function assertPaymentReversalPayload(
  value: unknown,
): asserts value is PaymentReversalPreviewTokenPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const payload = value as Record<string, unknown>;
  const exactKeys = [
    "kind",
    "actorUserId",
    "studentId",
    "recipientStudentId",
    "paymentRecordId",
    "expectedVersion",
    "status",
    "actualPaymentId",
    "issuedSubscriptionId",
    "amountMinor",
    "currencyCode",
    "walletBalanceMinor",
    "resultingBalanceMinor",
    "issuedAtSeconds",
    "expiresAtSeconds",
  ];
  if (
    Object.keys(payload).length !== exactKeys.length ||
    exactKeys.some((key) => !(key in payload)) ||
    payload.kind !== "payment.reversal" ||
    !isUuid(payload.actorUserId) ||
    !isUuid(payload.studentId) ||
    !isUuid(payload.recipientStudentId) ||
    !isUuid(payload.paymentRecordId) ||
    !isPositiveInteger(payload.expectedVersion) ||
    !["unpaid", "posted_pending", "paid"].includes(payload.status as string) ||
    (payload.actualPaymentId !== null && !isUuid(payload.actualPaymentId)) ||
    (payload.issuedSubscriptionId !== null &&
      !isUuid(payload.issuedSubscriptionId)) ||
    !isMinor(payload.amountMinor) ||
    payload.amountMinor === "0" ||
    typeof payload.currencyCode !== "string" ||
    !/^[A-Z]{3}$/.test(payload.currencyCode) ||
    !isSignedMinor(payload.walletBalanceMinor) ||
    !isSignedMinor(payload.resultingBalanceMinor) ||
    !isPositiveInteger(payload.issuedAtSeconds) ||
    !isPositiveInteger(payload.expiresAtSeconds) ||
    payload.expiresAtSeconds < payload.issuedAtSeconds
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
}

function assertLessonTransitionPayload(
  value: unknown,
): asserts value is LessonTransitionPreviewTokenPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
  const payload = value as Record<string, unknown>;
  const exactKeys = [
    "kind",
    "operation",
    "actorUserId",
    "lessonId",
    "expectedVersion",
    "transitionFingerprint",
    "issuedAtSeconds",
    "expiresAtSeconds",
  ];
  if (
    Object.keys(payload).length !== exactKeys.length ||
    exactKeys.some((key) => !(key in payload)) ||
    payload.kind !== "lesson.transition" ||
    !["reschedule", "cancel", "settle", "bulk"].includes(
      payload.operation as string,
    ) ||
    !isUuid(payload.actorUserId) ||
    !isUuid(payload.lessonId) ||
    !isPositiveInteger(payload.expectedVersion) ||
    typeof payload.transitionFingerprint !== "string" ||
    !/^[a-f0-9]{64}$/.test(payload.transitionFingerprint) ||
    !isPositiveInteger(payload.issuedAtSeconds) ||
    !isPositiveInteger(payload.expiresAtSeconds) ||
    payload.expiresAtSeconds < payload.issuedAtSeconds
  ) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_INVALID");
  }
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
  return (
    typeof value === "string" &&
    /^(0|[1-9]\d*)(\.\d{1,2})?$/.test(value)
  );
}
