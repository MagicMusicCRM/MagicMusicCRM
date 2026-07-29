import { createHmac, timingSafeEqual } from "node:crypto";

const TOKEN_VERSION = "v1";
const TOKEN_DOMAIN = "magicmusiccrm:subscription-replace-preview:v1";

export interface SubscriptionReplacePreviewTokenPayload {
  kind: "subscription.replace";
  actorUserId: string;
  studentId: string;
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
  assertSecret(secret);
  assertPayload(payload);
  const body = Buffer.from(JSON.stringify(payload), "utf8").toString(
    "base64url",
  );
  return [
    TOKEN_VERSION,
    body,
    signature(secret, body).toString("base64url"),
  ].join(".");
}

export function verifySubscriptionReplacePreview(
  secret: string,
  token: string,
  nowSeconds: number,
): SubscriptionReplacePreviewTokenPayload {
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
  const expected = signature(secret, body);
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
  assertPayload(payload);
  if (payload.expiresAtSeconds < nowSeconds) {
    throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_EXPIRED");
  }
  return payload;
}

function signature(secret: string, body: string): Buffer {
  return createHmac("sha256", secret)
    .update(`${TOKEN_DOMAIN}.${body}`)
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

function assertPayload(
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
