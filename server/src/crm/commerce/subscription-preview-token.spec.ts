import { createHmac } from "node:crypto";
import {
  SubscriptionPreviewTokenError,
  signAccountAdjustmentReversalPreview,
  signLessonTransitionPreview,
  signPaymentCorrectionPreview,
  signPaymentReversalPreview,
  signSchedulePlanEndPreview,
  signSubscriptionCancelPreview,
  signSubscriptionPurchasePreview,
  signSubscriptionReplacePreview,
  verifyAccountAdjustmentReversalPreview,
  verifyLessonTransitionPreview,
  verifyPaymentCorrectionPreview,
  verifyPaymentReversalPreview,
  verifySchedulePlanEndPreview,
  verifySubscriptionCancelPreview,
  verifySubscriptionPurchasePreview,
  verifySubscriptionReplacePreview,
} from "./subscription-preview-token";

const SECRET = "preview-token-characterization-secret-at-least-32-bytes";
const ISSUED = 1_800_000_000;
const EXPIRES = 1_800_000_300;
const NOW = 1_800_000_100;
const UUID_1 = "10000000-0000-4000-8000-000000000001";
const UUID_2 = "10000000-0000-4000-8000-000000000002";
const UUID_3 = "10000000-0000-4000-8000-000000000003";
const UUID_4 = "10000000-0000-4000-8000-000000000004";
const UUID_5 = "10000000-0000-4000-8000-000000000005";
const UUID_6 = "10000000-0000-4000-8000-000000000006";
const FINGERPRINT_A =
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const FINGERPRINT_B =
  "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const UPPERCASE_UUID = "ABCDEFAB-CDEF-4ABC-ADEF-ABCDEFABCDEF";
const ASCII_32_BYTE_SECRET = "12345678901234567890123456789012";
const MULTIBYTE_32_BYTE_SECRET = "я".repeat(16);

type Payload = Record<string, unknown>;
type InvalidKind = keyof typeof INVALID_VALUES;

interface FamilyCase {
  name: string;
  domain: string;
  fixture: Payload;
  fields: ReadonlyArray<readonly [field: string, invalidKind: InvalidKind]>;
  sign: (payload: unknown) => string;
  verify: (token: string, nowSeconds: number) => unknown;
}

type AcceptedAlternativeCase = readonly [
  label: string,
  family: FamilyCase,
  field: string,
  value: unknown,
];

interface PayloadRejectionCase {
  label: string;
  family: FamilyCase;
  payload: unknown;
}

const INVALID_VALUES = {
  kind: [null, "", "wrong.kind", 1],
  uuid: [null, "", "not-a-uuid", UUID_1.toUpperCase().replace("4", "6"), 1],
  positiveInteger: [
    null,
    0,
    -1,
    1.5,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.MAX_SAFE_INTEGER + 1,
    "1",
  ],
  nonnegativeInteger: [
    null,
    -1,
    1.5,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.MAX_SAFE_INTEGER + 1,
    "0",
  ],
  units: [null, "", "01", "1.234", "-1", "1.", 1],
  minor: [null, "", "01", "-1", "1.0", "+1", 1],
  signedMinor: [null, "", "01", "-01", "1.0", "+1", 1],
  nonzeroMinor: [null, "", "0", "01", "-1", "1.0", "+1", 1],
  nonzeroSignedMinor: [null, "", "0", "01", "-01", "1.0", "+1", 1],
  currency: [null, "", "rub", "RUBB", "RU", 1],
  fingerprint: [null, "", FINGERPRINT_A.toUpperCase(), "a".repeat(63), 1],
  dateShape: [null, "", "2026-1-01", "2026/01/01", "not-a-date", 1],
  enum: [null, "", "unsupported", 1],
  nullableUuid: ["not-a-uuid", 1, {}, []],
  nullableString: [1, {}, []],
  nullableEnum: ["unsupported", 1, {}, []],
} as const;

const FAMILIES: readonly FamilyCase[] = [
  {
    name: "subscription replacement",
    domain: "magicmusiccrm:subscription-replace-preview:v1",
    fixture: {
      kind: "subscription.replace",
      actorUserId: UUID_1,
      studentId: UUID_2,
      payerStudentId: UUID_3,
      issuedSubscriptionId: UUID_4,
      expectedVersion: 3,
      newPackageId: UUID_5,
      newPackageVersion: 4,
      currencyCode: "RUB",
      usedUnits: "1.25",
      reservedLessonCount: 2,
      reservedUnits: "2.5",
      transferableReservationCount: 1,
      transferableReservationUnits: "1.25",
      releasedReservationCount: 1,
      releasedReservationUnits: "1.25",
      reservationPlanFingerprint: FINGERPRINT_A,
      futureLessonCount: 3,
      futureUnits: "3.75",
      oldFinalMinor: "10000",
      newFinalMinor: "12000",
      actualPaidMinor: "9000",
      deltaMinor: "-0",
      positionKind: "debt",
      positionMinor: "3000",
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["actorUserId", "uuid"],
      ["studentId", "uuid"],
      ["payerStudentId", "uuid"],
      ["issuedSubscriptionId", "uuid"],
      ["expectedVersion", "positiveInteger"],
      ["newPackageId", "uuid"],
      ["newPackageVersion", "positiveInteger"],
      ["currencyCode", "currency"],
      ["usedUnits", "units"],
      ["reservedLessonCount", "nonnegativeInteger"],
      ["reservedUnits", "units"],
      ["transferableReservationCount", "nonnegativeInteger"],
      ["transferableReservationUnits", "units"],
      ["releasedReservationCount", "nonnegativeInteger"],
      ["releasedReservationUnits", "units"],
      ["reservationPlanFingerprint", "fingerprint"],
      ["futureLessonCount", "nonnegativeInteger"],
      ["futureUnits", "units"],
      ["oldFinalMinor", "minor"],
      ["newFinalMinor", "minor"],
      ["actualPaidMinor", "minor"],
      ["deltaMinor", "signedMinor"],
      ["positionKind", "enum"],
      ["positionMinor", "minor"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) => signSubscriptionReplacePreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifySubscriptionReplacePreview(SECRET, token, nowSeconds),
  },
  {
    name: "subscription cancellation",
    domain: "magicmusiccrm:subscription-cancel-preview:v1",
    fixture: {
      kind: "subscription.cancel",
      actorUserId: UUID_1,
      studentId: UUID_2,
      payerStudentId: UUID_3,
      issuedSubscriptionId: UUID_4,
      expectedVersion: 3,
      packageId: UUID_5,
      packageVersion: 4,
      unitCount: "10",
      usedUnits: "1.25",
      currencyCode: "RUB",
      finalMinor: "10000",
      actualPaidMinor: "9000",
      fundingMode: "legacy",
      previousRefundMinor: "0",
      writeoffMinor: "1000",
      balanceMinor: "-0",
      openPaymentRecordCount: 1,
      openPaymentRecordMinor: "1000",
      futureLessonCount: 3,
      reservedLessonCount: 2,
      reservedUnits: "2.5",
      impactFingerprint: FINGERPRINT_B,
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["actorUserId", "uuid"],
      ["studentId", "uuid"],
      ["payerStudentId", "uuid"],
      ["issuedSubscriptionId", "uuid"],
      ["expectedVersion", "positiveInteger"],
      ["packageId", "uuid"],
      ["packageVersion", "positiveInteger"],
      ["unitCount", "units"],
      ["usedUnits", "units"],
      ["currencyCode", "currency"],
      ["finalMinor", "minor"],
      ["actualPaidMinor", "minor"],
      ["fundingMode", "enum"],
      ["previousRefundMinor", "minor"],
      ["writeoffMinor", "minor"],
      ["balanceMinor", "signedMinor"],
      ["openPaymentRecordCount", "nonnegativeInteger"],
      ["openPaymentRecordMinor", "minor"],
      ["futureLessonCount", "nonnegativeInteger"],
      ["reservedLessonCount", "nonnegativeInteger"],
      ["reservedUnits", "units"],
      ["impactFingerprint", "fingerprint"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) => signSubscriptionCancelPreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifySubscriptionCancelPreview(SECRET, token, nowSeconds),
  },
  {
    name: "subscription purchase",
    domain: "magicmusiccrm:subscription-purchase-preview:v1",
    fixture: {
      kind: "subscription.purchase",
      actorUserId: UUID_1,
      recipientStudentId: UUID_2,
      payerStudentId: UUID_3,
      recipientVersion: 2,
      payerVersion: 3,
      recipientBranchId: null,
      payerBranchId: UUID_4,
      packageId: UUID_5,
      packageVersion: 4,
      currencyCode: "RUB",
      finalPriceMinor: "10000",
      payerBalanceMinor: "-0",
      fundingMode: "personal_account",
      purchaseFingerprint: FINGERPRINT_A,
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["actorUserId", "uuid"],
      ["recipientStudentId", "uuid"],
      ["payerStudentId", "uuid"],
      ["recipientVersion", "positiveInteger"],
      ["payerVersion", "positiveInteger"],
      ["recipientBranchId", "nullableUuid"],
      ["payerBranchId", "nullableUuid"],
      ["packageId", "uuid"],
      ["packageVersion", "positiveInteger"],
      ["currencyCode", "currency"],
      ["finalPriceMinor", "minor"],
      ["payerBalanceMinor", "signedMinor"],
      ["fundingMode", "enum"],
      ["purchaseFingerprint", "fingerprint"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) => signSubscriptionPurchasePreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifySubscriptionPurchasePreview(SECRET, token, nowSeconds),
  },
  {
    name: "payment reversal",
    domain: "magicmusiccrm:payment-reversal-preview:v1",
    fixture: {
      kind: "payment.reversal",
      actorUserId: UUID_1,
      studentId: UUID_2,
      recipientStudentId: UUID_3,
      paymentRecordId: UUID_4,
      expectedVersion: 2,
      status: "paid",
      actualPaymentId: UUID_5,
      issuedSubscriptionId: null,
      amountMinor: "1000",
      currencyCode: "RUB",
      walletBalanceMinor: "-0",
      resultingBalanceMinor: "2000",
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["actorUserId", "uuid"],
      ["studentId", "uuid"],
      ["recipientStudentId", "uuid"],
      ["paymentRecordId", "uuid"],
      ["expectedVersion", "positiveInteger"],
      ["status", "enum"],
      ["actualPaymentId", "nullableUuid"],
      ["issuedSubscriptionId", "nullableUuid"],
      ["amountMinor", "nonzeroMinor"],
      ["currencyCode", "currency"],
      ["walletBalanceMinor", "signedMinor"],
      ["resultingBalanceMinor", "signedMinor"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) => signPaymentReversalPreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifyPaymentReversalPreview(SECRET, token, nowSeconds),
  },
  {
    name: "payment correction",
    domain: "magicmusiccrm:payment-correction-preview:v1",
    fixture: {
      kind: "payment.correction",
      actorUserId: UUID_1,
      studentId: UUID_2,
      recipientStudentId: UUID_3,
      paymentRecordId: UUID_4,
      expectedVersion: 2,
      oldStatus: "paid",
      oldActualPaymentId: null,
      issuedSubscriptionId: UUID_5,
      installmentId: null,
      oldAmountMinor: "1000",
      currencyCode: "RUB",
      amountMinor: "2000",
      status: "posted_pending",
      dueAt: "2026-08-28T12:00:00.000Z",
      method: "cashless",
      externalIdentifier: "external-1",
      occurredAt: null,
      branchId: UUID_6,
      verificationNote: "Проверено",
      walletBalanceMinor: "-0",
      resultingBalanceMinor: "3000",
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["actorUserId", "uuid"],
      ["studentId", "uuid"],
      ["recipientStudentId", "uuid"],
      ["paymentRecordId", "uuid"],
      ["expectedVersion", "positiveInteger"],
      ["oldStatus", "enum"],
      ["oldActualPaymentId", "nullableUuid"],
      ["issuedSubscriptionId", "nullableUuid"],
      ["installmentId", "nullableUuid"],
      ["oldAmountMinor", "nonzeroMinor"],
      ["currencyCode", "currency"],
      ["amountMinor", "nonzeroMinor"],
      ["status", "enum"],
      ["dueAt", "nullableString"],
      ["method", "nullableEnum"],
      ["externalIdentifier", "nullableString"],
      ["occurredAt", "nullableString"],
      ["branchId", "nullableUuid"],
      ["verificationNote", "nullableString"],
      ["walletBalanceMinor", "signedMinor"],
      ["resultingBalanceMinor", "signedMinor"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) => signPaymentCorrectionPreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifyPaymentCorrectionPreview(SECRET, token, nowSeconds),
  },
  {
    name: "account adjustment reversal",
    domain: "magicmusiccrm:account-adjustment-reversal-preview:v1",
    fixture: {
      kind: "account.adjustment.reversal",
      actorUserId: UUID_1,
      studentId: UUID_2,
      adjustmentId: UUID_3,
      expectedVersion: 2,
      sourcePaymentId: UUID_4,
      amountMinor: "-0",
      currencyCode: "RUB",
      walletBalanceMinor: "-1000",
      resultingBalanceMinor: "0",
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["actorUserId", "uuid"],
      ["studentId", "uuid"],
      ["adjustmentId", "uuid"],
      ["expectedVersion", "positiveInteger"],
      ["sourcePaymentId", "uuid"],
      ["amountMinor", "nonzeroSignedMinor"],
      ["currencyCode", "currency"],
      ["walletBalanceMinor", "signedMinor"],
      ["resultingBalanceMinor", "signedMinor"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) =>
      signAccountAdjustmentReversalPreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifyAccountAdjustmentReversalPreview(SECRET, token, nowSeconds),
  },
  {
    name: "lesson transition",
    domain: "magicmusiccrm:lesson-transition-preview:v1",
    fixture: {
      kind: "lesson.transition",
      operation: "planned-settlement",
      actorUserId: UUID_1,
      lessonId: UUID_2,
      expectedVersion: 2,
      transitionFingerprint: FINGERPRINT_A,
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["operation", "enum"],
      ["actorUserId", "uuid"],
      ["lessonId", "uuid"],
      ["expectedVersion", "positiveInteger"],
      ["transitionFingerprint", "fingerprint"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) => signLessonTransitionPreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifyLessonTransitionPreview(SECRET, token, nowSeconds),
  },
  {
    name: "schedule plan end",
    domain: "magicmusiccrm:schedule-plan-end-preview:v1",
    fixture: {
      kind: "schedule.plan.end",
      actorUserId: UUID_1,
      planId: UUID_2,
      expectedVersion: 2,
      lastDate: "2026-08-28",
      impactFingerprint: FINGERPRINT_B,
      issuedAtSeconds: ISSUED,
      expiresAtSeconds: EXPIRES,
    },
    fields: [
      ["kind", "kind"],
      ["actorUserId", "uuid"],
      ["planId", "uuid"],
      ["expectedVersion", "positiveInteger"],
      ["lastDate", "dateShape"],
      ["impactFingerprint", "fingerprint"],
      ["issuedAtSeconds", "positiveInteger"],
      ["expiresAtSeconds", "positiveInteger"],
    ],
    sign: (payload) => signSchedulePlanEndPreview(SECRET, payload as never),
    verify: (token, nowSeconds) =>
      verifySchedulePlanEndPreview(SECRET, token, nowSeconds),
  },
];

const ACCEPTED_ALTERNATIVES: readonly AcceptedAlternativeCase[] = [
  ["subscription replacement positionKind=debt", FAMILIES[0]!, "positionKind", "debt"],
  ["subscription replacement positionKind=overpayment", FAMILIES[0]!, "positionKind", "overpayment"],
  ["subscription replacement positionKind=settled", FAMILIES[0]!, "positionKind", "settled"],
  ["subscription cancellation fundingMode=personal_account", FAMILIES[1]!, "fundingMode", "personal_account"],
  ["subscription cancellation fundingMode=installment", FAMILIES[1]!, "fundingMode", "installment"],
  ["subscription cancellation fundingMode=legacy", FAMILIES[1]!, "fundingMode", "legacy"],
  ["subscription purchase fundingMode=personal_account", FAMILIES[2]!, "fundingMode", "personal_account"],
  ["subscription purchase fundingMode=installment", FAMILIES[2]!, "fundingMode", "installment"],
  ["payment reversal status=unpaid", FAMILIES[3]!, "status", "unpaid"],
  ["payment reversal status=posted_pending", FAMILIES[3]!, "status", "posted_pending"],
  ["payment reversal status=paid", FAMILIES[3]!, "status", "paid"],
  ["payment correction oldStatus=unpaid", FAMILIES[4]!, "oldStatus", "unpaid"],
  ["payment correction oldStatus=posted_pending", FAMILIES[4]!, "oldStatus", "posted_pending"],
  ["payment correction oldStatus=paid", FAMILIES[4]!, "oldStatus", "paid"],
  ["payment correction status=unpaid", FAMILIES[4]!, "status", "unpaid"],
  ["payment correction status=posted_pending", FAMILIES[4]!, "status", "posted_pending"],
  ["payment correction status=paid", FAMILIES[4]!, "status", "paid"],
  ["payment correction method=null", FAMILIES[4]!, "method", null],
  ["payment correction method=cash", FAMILIES[4]!, "method", "cash"],
  ["payment correction method=cashless", FAMILIES[4]!, "method", "cashless"],
  ["lesson transition operation=reschedule", FAMILIES[6]!, "operation", "reschedule"],
  ["lesson transition operation=cancel", FAMILIES[6]!, "operation", "cancel"],
  ["lesson transition operation=settle", FAMILIES[6]!, "operation", "settle"],
  ["lesson transition operation=bulk", FAMILIES[6]!, "operation", "bulk"],
  ["lesson transition operation=correct", FAMILIES[6]!, "operation", "correct"],
  ["lesson transition operation=planned-settlement", FAMILIES[6]!, "operation", "planned-settlement"],
  ["subscription purchase recipientBranchId=null", FAMILIES[2]!, "recipientBranchId", null],
  ["subscription purchase recipientBranchId=uuid", FAMILIES[2]!, "recipientBranchId", UUID_6],
  ["subscription purchase payerBranchId=null", FAMILIES[2]!, "payerBranchId", null],
  ["subscription purchase payerBranchId=uuid", FAMILIES[2]!, "payerBranchId", UUID_6],
  ["payment reversal actualPaymentId=null", FAMILIES[3]!, "actualPaymentId", null],
  ["payment reversal actualPaymentId=uuid", FAMILIES[3]!, "actualPaymentId", UUID_5],
  ["payment reversal issuedSubscriptionId=null", FAMILIES[3]!, "issuedSubscriptionId", null],
  ["payment reversal issuedSubscriptionId=uuid", FAMILIES[3]!, "issuedSubscriptionId", UUID_5],
  ["payment correction oldActualPaymentId=null", FAMILIES[4]!, "oldActualPaymentId", null],
  ["payment correction oldActualPaymentId=uuid", FAMILIES[4]!, "oldActualPaymentId", UUID_5],
  ["payment correction issuedSubscriptionId=null", FAMILIES[4]!, "issuedSubscriptionId", null],
  ["payment correction issuedSubscriptionId=uuid", FAMILIES[4]!, "issuedSubscriptionId", UUID_5],
  ["payment correction installmentId=null", FAMILIES[4]!, "installmentId", null],
  ["payment correction installmentId=uuid", FAMILIES[4]!, "installmentId", UUID_6],
  ["payment correction dueAt=null", FAMILIES[4]!, "dueAt", null],
  ["payment correction dueAt=empty-string", FAMILIES[4]!, "dueAt", ""],
  ["payment correction externalIdentifier=null", FAMILIES[4]!, "externalIdentifier", null],
  ["payment correction externalIdentifier=empty-string", FAMILIES[4]!, "externalIdentifier", ""],
  ["payment correction occurredAt=null", FAMILIES[4]!, "occurredAt", null],
  ["payment correction occurredAt=empty-string", FAMILIES[4]!, "occurredAt", ""],
  ["payment correction branchId=null", FAMILIES[4]!, "branchId", null],
  ["payment correction branchId=uuid", FAMILIES[4]!, "branchId", UUID_6],
  ["payment correction verificationNote=null", FAMILIES[4]!, "verificationNote", null],
  ["payment correction verificationNote=empty-string", FAMILIES[4]!, "verificationNote", ""],
  ["uppercase UUID", FAMILIES[0]!, "actorUserId", UPPERCASE_UUID],
  ["zero units", FAMILIES[0]!, "usedUnits", "0"],
  ["positive integer boundary one", FAMILIES[0]!, "expectedVersion", 1],
  ["positive timestamp boundary one", FAMILIES[0]!, "issuedAtSeconds", 1],
  ["alternate uppercase currency", FAMILIES[0]!, "currencyCode", "USD"],
  ["numeric fingerprint", FAMILIES[0]!, "reservationPlanFingerprint", "0".repeat(64)],
  ["zero unsigned minor", FAMILIES[0]!, "oldFinalMinor", "0"],
  ["positive nonzero adjustment amount", FAMILIES[5]!, "amountMinor", "1"],
  ["negative nonzero adjustment amount", FAMILIES[5]!, "amountMinor", "-1"],
  ["maximum safe positive integer", FAMILIES[0]!, "expectedVersion", Number.MAX_SAFE_INTEGER],
  ["maximum safe nonnegative integer", FAMILIES[0]!, "reservedLessonCount", Number.MAX_SAFE_INTEGER],
  ["UUID version 1 variant 9", FAMILIES[0]!, "actorUserId", "abcdefab-cdef-1abc-9def-abcdefabcdef"],
  ["UUID version 2 variant b", FAMILIES[0]!, "actorUserId", "abcdefab-cdef-2abc-bdef-abcdefabcdef"],
  ["UUID version 3 variant 8", FAMILIES[0]!, "actorUserId", "abcdefab-cdef-3abc-8def-abcdefabcdef"],
  ["UUID version 5 variant b", FAMILIES[0]!, "actorUserId", "abcdefab-cdef-5abc-bdef-abcdefabcdef"],
  ["zero units with one decimal", FAMILIES[0]!, "usedUnits", "0.0"],
  ["zero units with two decimals", FAMILIES[0]!, "usedUnits", "0.00"],
];

const GOLDENS: Readonly<Record<string, string>> = {
  "subscription replacement":
    "v1.eyJraW5kIjoic3Vic2NyaXB0aW9uLnJlcGxhY2UiLCJhY3RvclVzZXJJZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMSIsInN0dWRlbnRJZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMiIsInBheWVyU3R1ZGVudElkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAzIiwiaXNzdWVkU3Vic2NyaXB0aW9uSWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDQiLCJleHBlY3RlZFZlcnNpb24iOjMsIm5ld1BhY2thZ2VJZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwNSIsIm5ld1BhY2thZ2VWZXJzaW9uIjo0LCJjdXJyZW5jeUNvZGUiOiJSVUIiLCJ1c2VkVW5pdHMiOiIxLjI1IiwicmVzZXJ2ZWRMZXNzb25Db3VudCI6MiwicmVzZXJ2ZWRVbml0cyI6IjIuNSIsInRyYW5zZmVyYWJsZVJlc2VydmF0aW9uQ291bnQiOjEsInRyYW5zZmVyYWJsZVJlc2VydmF0aW9uVW5pdHMiOiIxLjI1IiwicmVsZWFzZWRSZXNlcnZhdGlvbkNvdW50IjoxLCJyZWxlYXNlZFJlc2VydmF0aW9uVW5pdHMiOiIxLjI1IiwicmVzZXJ2YXRpb25QbGFuRmluZ2VycHJpbnQiOiJhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiZnV0dXJlTGVzc29uQ291bnQiOjMsImZ1dHVyZVVuaXRzIjoiMy43NSIsIm9sZEZpbmFsTWlub3IiOiIxMDAwMCIsIm5ld0ZpbmFsTWlub3IiOiIxMjAwMCIsImFjdHVhbFBhaWRNaW5vciI6IjkwMDAiLCJkZWx0YU1pbm9yIjoiLTAiLCJwb3NpdGlvbktpbmQiOiJkZWJ0IiwicG9zaXRpb25NaW5vciI6IjMwMDAiLCJpc3N1ZWRBdFNlY29uZHMiOjE4MDAwMDAwMDAsImV4cGlyZXNBdFNlY29uZHMiOjE4MDAwMDAzMDB9.KQUVuYlKNgiA3SFTOUWPqeiAHVV7Vcq9DV4F_ha_LTk",
  "subscription cancellation":
    "v1.eyJraW5kIjoic3Vic2NyaXB0aW9uLmNhbmNlbCIsImFjdG9yVXNlcklkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxIiwic3R1ZGVudElkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAyIiwicGF5ZXJTdHVkZW50SWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDMiLCJpc3N1ZWRTdWJzY3JpcHRpb25JZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwNCIsImV4cGVjdGVkVmVyc2lvbiI6MywicGFja2FnZUlkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA1IiwicGFja2FnZVZlcnNpb24iOjQsInVuaXRDb3VudCI6IjEwIiwidXNlZFVuaXRzIjoiMS4yNSIsImN1cnJlbmN5Q29kZSI6IlJVQiIsImZpbmFsTWlub3IiOiIxMDAwMCIsImFjdHVhbFBhaWRNaW5vciI6IjkwMDAiLCJmdW5kaW5nTW9kZSI6ImxlZ2FjeSIsInByZXZpb3VzUmVmdW5kTWlub3IiOiIwIiwid3JpdGVvZmZNaW5vciI6IjEwMDAiLCJiYWxhbmNlTWlub3IiOiItMCIsIm9wZW5QYXltZW50UmVjb3JkQ291bnQiOjEsIm9wZW5QYXltZW50UmVjb3JkTWlub3IiOiIxMDAwIiwiZnV0dXJlTGVzc29uQ291bnQiOjMsInJlc2VydmVkTGVzc29uQ291bnQiOjIsInJlc2VydmVkVW5pdHMiOiIyLjUiLCJpbXBhY3RGaW5nZXJwcmludCI6ImJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmIiLCJpc3N1ZWRBdFNlY29uZHMiOjE4MDAwMDAwMDAsImV4cGlyZXNBdFNlY29uZHMiOjE4MDAwMDAzMDB9.WCPFH4YnYBMAhwbRTK2gZL6qqHPkFNoJmKq-iaXsd60",
  "subscription purchase":
    "v1.eyJraW5kIjoic3Vic2NyaXB0aW9uLnB1cmNoYXNlIiwiYWN0b3JVc2VySWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJyZWNpcGllbnRTdHVkZW50SWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDIiLCJwYXllclN0dWRlbnRJZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMyIsInJlY2lwaWVudFZlcnNpb24iOjIsInBheWVyVmVyc2lvbiI6MywicmVjaXBpZW50QnJhbmNoSWQiOm51bGwsInBheWVyQnJhbmNoSWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDQiLCJwYWNrYWdlSWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDUiLCJwYWNrYWdlVmVyc2lvbiI6NCwiY3VycmVuY3lDb2RlIjoiUlVCIiwiZmluYWxQcmljZU1pbm9yIjoiMTAwMDAiLCJwYXllckJhbGFuY2VNaW5vciI6Ii0wIiwiZnVuZGluZ01vZGUiOiJwZXJzb25hbF9hY2NvdW50IiwicHVyY2hhc2VGaW5nZXJwcmludCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWEiLCJpc3N1ZWRBdFNlY29uZHMiOjE4MDAwMDAwMDAsImV4cGlyZXNBdFNlY29uZHMiOjE4MDAwMDAzMDB9.oKZkMRSyOqURaIJxAI7Uv00nTLguSZf0YUe5O8du0Rs",
  "payment reversal":
    "v1.eyJraW5kIjoicGF5bWVudC5yZXZlcnNhbCIsImFjdG9yVXNlcklkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxIiwic3R1ZGVudElkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAyIiwicmVjaXBpZW50U3R1ZGVudElkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAzIiwicGF5bWVudFJlY29yZElkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA0IiwiZXhwZWN0ZWRWZXJzaW9uIjoyLCJzdGF0dXMiOiJwYWlkIiwiYWN0dWFsUGF5bWVudElkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA1IiwiaXNzdWVkU3Vic2NyaXB0aW9uSWQiOm51bGwsImFtb3VudE1pbm9yIjoiMTAwMCIsImN1cnJlbmN5Q29kZSI6IlJVQiIsIndhbGxldEJhbGFuY2VNaW5vciI6Ii0wIiwicmVzdWx0aW5nQmFsYW5jZU1pbm9yIjoiMjAwMCIsImlzc3VlZEF0U2Vjb25kcyI6MTgwMDAwMDAwMCwiZXhwaXJlc0F0U2Vjb25kcyI6MTgwMDAwMDMwMH0.U5jOsE-T3fBxGYp7Vvu99nQWb5eOMdCgXA-Tj0wxl0k",
  "payment correction":
    "v1.eyJraW5kIjoicGF5bWVudC5jb3JyZWN0aW9uIiwiYWN0b3JVc2VySWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJzdHVkZW50SWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDIiLCJyZWNpcGllbnRTdHVkZW50SWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDMiLCJwYXltZW50UmVjb3JkSWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDQiLCJleHBlY3RlZFZlcnNpb24iOjIsIm9sZFN0YXR1cyI6InBhaWQiLCJvbGRBY3R1YWxQYXltZW50SWQiOm51bGwsImlzc3VlZFN1YnNjcmlwdGlvbklkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA1IiwiaW5zdGFsbG1lbnRJZCI6bnVsbCwib2xkQW1vdW50TWlub3IiOiIxMDAwIiwiY3VycmVuY3lDb2RlIjoiUlVCIiwiYW1vdW50TWlub3IiOiIyMDAwIiwic3RhdHVzIjoicG9zdGVkX3BlbmRpbmciLCJkdWVBdCI6IjIwMjYtMDgtMjhUMTI6MDA6MDAuMDAwWiIsIm1ldGhvZCI6ImNhc2hsZXNzIiwiZXh0ZXJuYWxJZGVudGlmaWVyIjoiZXh0ZXJuYWwtMSIsIm9jY3VycmVkQXQiOm51bGwsImJyYW5jaElkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDA2IiwidmVyaWZpY2F0aW9uTm90ZSI6ItCf0YDQvtCy0LXRgNC10L3QviIsIndhbGxldEJhbGFuY2VNaW5vciI6Ii0wIiwicmVzdWx0aW5nQmFsYW5jZU1pbm9yIjoiMzAwMCIsImlzc3VlZEF0U2Vjb25kcyI6MTgwMDAwMDAwMCwiZXhwaXJlc0F0U2Vjb25kcyI6MTgwMDAwMDMwMH0.28clrR2t_GuZluUGNAbXc409Aw2wTYPBrgvd8ii4DIA",
  "account adjustment reversal":
    "v1.eyJraW5kIjoiYWNjb3VudC5hZGp1c3RtZW50LnJldmVyc2FsIiwiYWN0b3JVc2VySWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJzdHVkZW50SWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDIiLCJhZGp1c3RtZW50SWQiOiIxMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDMiLCJleHBlY3RlZFZlcnNpb24iOjIsInNvdXJjZVBheW1lbnRJZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwNCIsImFtb3VudE1pbm9yIjoiLTAiLCJjdXJyZW5jeUNvZGUiOiJSVUIiLCJ3YWxsZXRCYWxhbmNlTWlub3IiOiItMTAwMCIsInJlc3VsdGluZ0JhbGFuY2VNaW5vciI6IjAiLCJpc3N1ZWRBdFNlY29uZHMiOjE4MDAwMDAwMDAsImV4cGlyZXNBdFNlY29uZHMiOjE4MDAwMDAzMDB9.WVFX9G7LnIXQlI6aVuyrvCzYsxbG6PtGQJOfRzcHq4o",
  "lesson transition":
    "v1.eyJraW5kIjoibGVzc29uLnRyYW5zaXRpb24iLCJvcGVyYXRpb24iOiJwbGFubmVkLXNldHRsZW1lbnQiLCJhY3RvclVzZXJJZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMSIsImxlc3NvbklkIjoiMTAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAyIiwiZXhwZWN0ZWRWZXJzaW9uIjoyLCJ0cmFuc2l0aW9uRmluZ2VycHJpbnQiOiJhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwiaXNzdWVkQXRTZWNvbmRzIjoxODAwMDAwMDAwLCJleHBpcmVzQXRTZWNvbmRzIjoxODAwMDAwMzAwfQ.46EJXkUzaDTDrF0Dg6rJv3A2JrYesVYU_sr9xRNt5wQ",
  "schedule plan end":
    "v1.eyJraW5kIjoic2NoZWR1bGUucGxhbi5lbmQiLCJhY3RvclVzZXJJZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMSIsInBsYW5JZCI6IjEwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMiIsImV4cGVjdGVkVmVyc2lvbiI6MiwibGFzdERhdGUiOiIyMDI2LTA4LTI4IiwiaW1wYWN0RmluZ2VycHJpbnQiOiJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiIiwiaXNzdWVkQXRTZWNvbmRzIjoxODAwMDAwMDAwLCJleHBpcmVzQXRTZWNvbmRzIjoxODAwMDAwMzAwfQ.4fyLQObIuP_bHrqRxKCRE0LzVEz5iteMDryhacAZJCc",
};

function changed(payload: Payload, field: string, value: unknown): Payload {
  return { ...payload, [field]: value };
}

function without(payload: Payload, field: string): Payload {
  const result = { ...payload };
  delete result[field];
  return result;
}

function expectTokenError(
  run: () => unknown,
  code: "PREVIEW_TOKEN_INVALID" | "PREVIEW_TOKEN_EXPIRED",
  label = `expected ${code}`,
): void {
  let caught: unknown;
  try {
    run();
  } catch (error) {
    caught = error;
  }
  expect({
    label,
    isSubscriptionPreviewTokenError:
      caught instanceof SubscriptionPreviewTokenError,
    name: caught instanceof Error ? caught.name : undefined,
    message: caught instanceof Error ? caught.message : undefined,
    code: (caught as { code?: unknown } | undefined)?.code,
  }).toEqual({
    label,
    isSubscriptionPreviewTokenError: true,
    name: "SubscriptionPreviewTokenError",
    message: code,
    code,
  });
}

function rejectionValueLabel(value: unknown): string {
  if (typeof value === "number") {
    if (Number.isNaN(value)) return "number:NaN";
    if (value === Number.POSITIVE_INFINITY) return "number:Infinity";
    if (value === Number.NEGATIVE_INFINITY) return "number:-Infinity";
  }
  if (Array.isArray(value)) return `array:${JSON.stringify(value)}`;
  return `${value === null ? "null" : typeof value}:${JSON.stringify(value)}`;
}

function buildInvalidPayloadScenarios(): PayloadRejectionCase[] {
  const scenarios: PayloadRejectionCase[] = [];
  for (const family of FAMILIES) {
    for (const [field, invalidKind] of family.fields) {
      scenarios.push({
        label: `${family.name} missing field=${field}`,
        family,
        payload: without(family.fixture, field),
      });
      INVALID_VALUES[invalidKind].forEach((value, index) => {
        scenarios.push({
          label: `${family.name} invalid field=${field} value[${index}]=${rejectionValueLabel(value)}`,
          family,
          payload: changed(family.fixture, field, value),
        });
      });
    }
  }
  return scenarios;
}

function buildUndefinedPayloadScenarios(): PayloadRejectionCase[] {
  return FAMILIES.flatMap((family) =>
    family.fields.map(([field]) => ({
      label: `${family.name} own-present undefined field=${field}`,
      family,
      payload: changed(family.fixture, field, undefined),
    })),
  );
}

const INVALID_PAYLOAD_SCENARIOS = buildInvalidPayloadScenarios();
const UNDEFINED_PAYLOAD_SCENARIOS = buildUndefinedPayloadScenarios();

function tokenForBody(domain: string, body: string): string {
  const signature = createHmac("sha256", SECRET)
    .update(`${domain}.${body}`)
    .digest("base64url");
  return `v1.${body}.${signature}`;
}

function decoderToleratedBoundaryToken(family: FamilyCase): string {
  const json = JSON.stringify(family.fixture);
  const paddedJson = `${json}${" ".repeat(12_252 - Buffer.byteLength(json))}`;
  const canonicalBody = Buffer.from(paddedJson, "utf8").toString("base64url");
  return tokenForBody(family.domain, `${canonicalBody}A`);
}

function validationReadCount(kind: InvalidKind, value: unknown): number {
  if (kind === "currency" || kind === "fingerprint" || kind === "dateShape") {
    return 2;
  }
  if (
    kind === "nullableUuid" ||
    kind === "nullableString" ||
    kind === "nullableEnum"
  ) {
    return value === null ? 1 : 2;
  }
  if (kind === "nonzeroMinor" || kind === "nonzeroSignedMinor") {
    return 2;
  }
  return 1;
}

function expectedAccessTrace(family: FamilyCase): string[] {
  const keys = family.fields.map(([field]) => field);
  const trace = ["ownKeys", ...keys.map((key) => `has:${key}`)];
  trace.push("get:kind");
  for (const [field, kind] of family.fields.slice(1, -2)) {
    for (
      let read = 0;
      read < validationReadCount(kind, family.fixture[field]);
      read += 1
    ) {
      trace.push(`get:${field}`);
    }
  }
  trace.push(
    "get:issuedAtSeconds",
    "get:expiresAtSeconds",
    "get:expiresAtSeconds",
    "get:issuedAtSeconds",
    "get:toJSON",
    "ownKeys",
  );
  trace.push(...keys.map((key) => `get:${key}`));
  return trace;
}

describe("subscription preview token public codec", () => {
  it.each(FAMILIES)(
    "$name has stable bytes and exact round-trip output",
    (family) => {
      const token = family.sign(family.fixture);
      expect(token).toBe(GOLDENS[family.name]);
      expect(family.verify(token, NOW)).toEqual(family.fixture);
    },
  );

  it.each(ACCEPTED_ALTERNATIVES)(
    "%s signs and verifies",
    (_label, family, field, value) => {
      const payload = changed(family.fixture, field, value);
      const token = family.sign(payload);
      expect(family.verify(token, NOW)).toEqual(payload);
    },
  );

  it("covers the complete literal accepted-alternatives table", () => {
    expect(ACCEPTED_ALTERNATIVES).toHaveLength(67);
  });

  it("covers every fixture key with an explicit invalid-value family", () => {
    for (const family of FAMILIES) {
      expect(family.fields.map(([field]) => field)).toEqual(
        Object.keys(family.fixture),
      );
    }
  });

  it.each(INVALID_PAYLOAD_SCENARIOS)("$label", ({ label, family, payload }) => {
    expectTokenError(
      () => family.sign(payload),
      "PREVIEW_TOKEN_INVALID",
      label,
    );
  });

  it("keeps the labeled invalid corpus at 955 scenarios", () => {
    expect(INVALID_PAYLOAD_SCENARIOS).toHaveLength(955);
  });

  it.each(UNDEFINED_PAYLOAD_SCENARIOS)(
    "$label",
    ({ label, family, payload }) => {
      expectTokenError(
        () => family.sign(payload),
        "PREVIEW_TOKEN_INVALID",
        label,
      );
    },
  );

  it("covers own-present undefined for all 136 live fixture keys", () => {
    expect(FAMILIES.map((family) => family.fields.length)).toEqual([
      27, 25, 17, 15, 24, 12, 8, 8,
    ]);
    expect(UNDEFINED_PAYLOAD_SCENARIOS).toHaveLength(136);
  });

  it.each(FAMILIES)("$name rejects extra enumerable keys", (family) => {
    expectTokenError(
      () => family.sign({ ...family.fixture, extra: true }),
      "PREVIEW_TOKEN_INVALID",
    );
  });

  it.each(FAMILIES)("$name rejects null and array roots", (family) => {
    expectTokenError(() => family.sign(null), "PREVIEW_TOKEN_INVALID");
    expectTokenError(() => family.sign([]), "PREVIEW_TOKEN_INVALID");
  });

  it.each(FAMILIES)(
    "$name preserves exact validation and serialization access order",
    (family) => {
      const trace: string[] = [];
      const payload = new Proxy(family.fixture, {
        get(target, property, receiver) {
          trace.push(`get:${String(property)}`);
          return Reflect.get(target, property, receiver);
        },
        has(target, property) {
          trace.push(`has:${String(property)}`);
          return Reflect.has(target, property);
        },
        ownKeys(target) {
          trace.push("ownKeys");
          return Reflect.ownKeys(target);
        },
      });
      family.sign(payload);
      expect(trace).toEqual(expectedAccessTrace(family));
    },
  );

  it.each(FAMILIES)("$name keeps rule short-circuit order", (family) => {
    const [, firstKind] = family.fields[1]!;
    const laterField = family.fields[2]![0];
    const payload = changed(
      family.fixture,
      family.fields[1]![0],
      INVALID_VALUES[firstKind][0],
    );
    Object.defineProperty(payload, laterField, {
      configurable: true,
      enumerable: true,
      get() {
        throw new Error(`read-order:${laterField}`);
      },
    });
    expectTokenError(() => family.sign(payload), "PREVIEW_TOKEN_INVALID");
  });

  it.each(FAMILIES)(
    "$name checks exact key count before kind and domain getters",
    (family) => {
      const payload = { ...family.fixture, extra: true };
      Object.defineProperty(payload, "kind", {
        configurable: true,
        enumerable: true,
        get() {
          throw new Error("kind-read-before-key-count");
        },
      });
      expectTokenError(() => family.sign(payload), "PREVIEW_TOKEN_INVALID");
    },
  );

  it.each(FAMILIES)("$name checks kind before domain getters", (family) => {
    const payload = changed(family.fixture, "kind", "wrong.kind");
    const firstDomainField = family.fields[1]![0];
    Object.defineProperty(payload, firstDomainField, {
      configurable: true,
      enumerable: true,
      get() {
        throw new Error(`domain-read-before-kind:${firstDomainField}`);
      },
    });
    expectTokenError(() => family.sign(payload), "PREVIEW_TOKEN_INVALID");
  });

  it.each(FAMILIES)(
    "$name accepts equal issued and expiry timestamps and the expiry boundary",
    (family) => {
      const payload = {
        ...family.fixture,
        expiresAtSeconds: family.fixture.issuedAtSeconds,
      };
      const token = family.sign(payload);
      expect(family.verify(token, ISSUED)).toEqual(payload);
      expectTokenError(
        () => family.verify(token, ISSUED + 1),
        "PREVIEW_TOKEN_EXPIRED",
      );
    },
  );

  it.each(FAMILIES)("$name rejects reversed timestamps", (family) => {
    expectTokenError(
      () =>
        family.sign({
          ...family.fixture,
          issuedAtSeconds: EXPIRES,
          expiresAtSeconds: ISSUED,
        }),
      "PREVIEW_TOKEN_INVALID",
    );
  });

  it.each(FAMILIES)("$name signs reordered own keys without normalizing", (family) => {
    const reordered = Object.fromEntries(
      Object.entries(family.fixture).reverse(),
    );
    const token = family.sign(reordered);
    expect(token).not.toBe(GOLDENS[family.name]);
    expect(family.verify(token, NOW)).toEqual(family.fixture);
  });

  it.each(FAMILIES)(
    "$name ignores symbol and non-enumerable extra keys",
    (family) => {
      const payload = { ...family.fixture };
      Object.defineProperty(payload, "hiddenExtra", {
        enumerable: false,
        value: true,
      });
      payload[Symbol("extra") as unknown as string] = true;
      expect(family.sign(payload)).toBe(GOLDENS[family.name]);
    },
  );

  it.each(FAMILIES)(
    "$name accepts an inherited required value when own key count is preserved",
    (family) => {
      const inheritedField = family.fields[1]![0];
      const inheritedValue = family.fixture[inheritedField];
      const payload = without(family.fixture, inheritedField);
      payload.extra = true;
      Object.setPrototypeOf(payload, { [inheritedField]: inheritedValue });
      const token = family.sign(payload);
      expectTokenError(
        () => family.verify(token, NOW),
        "PREVIEW_TOKEN_INVALID",
      );
    },
  );

  it("accepts an impossible but YYYY-MM-DD-shaped schedule date", () => {
    const family = FAMILIES[7]!;
    const payload = changed(family.fixture, "lastDate", "2026-02-31");
    expect(family.verify(family.sign(payload), NOW)).toEqual(payload);
  });

  it("accepts numeric -0 for every nonnegative-integer field", () => {
    for (const family of FAMILIES) {
      for (const [field, invalidKind] of family.fields) {
        if (invalidKind !== "nonnegativeInteger") continue;
        const token = family.sign(changed(family.fixture, field, -0));
        expect(family.verify(token, NOW)).toEqual(
          changed(family.fixture, field, 0),
        );
      }
    }
  });

  it("accepts string -0 for every signed-minor field", () => {
    for (const family of FAMILIES) {
      for (const [field, invalidKind] of family.fields) {
        if (
          invalidKind !== "signedMinor" &&
          invalidKind !== "nonzeroSignedMinor"
        ) {
          continue;
        }
        const payload = changed(family.fixture, field, "-0");
        expect(family.verify(family.sign(payload), NOW)).toEqual(payload);
      }
    }
  });

  it.each([
    ["currencyCode", "RUB", "rub", FAMILIES[0]],
    ["impactFingerprint", FINGERPRINT_B, "bad", FAMILIES[7]],
    ["recipientBranchId", UUID_4, "bad", FAMILIES[2]],
    ["dueAt", "2026-08-28", 1, FAMILIES[4]],
    ["amountMinor", "1000", "0", FAMILIES[3]],
  ] as const)(
    "re-reads stateful %s accessors",
    (field, firstValue, secondValue, family) => {
      const payload = { ...family.fixture };
      let reads = 0;
      Object.defineProperty(payload, field, {
        configurable: true,
        enumerable: true,
        get() {
          reads += 1;
          return reads === 1 ? firstValue : secondValue;
        },
      });
      expectTokenError(() => family.sign(payload), "PREVIEW_TOKEN_INVALID");
      expect(reads).toBe(2);
    },
  );

  it("re-reads issued/expires timestamps for the ordering comparison", () => {
    const family = FAMILIES[0]!;
    const payload = { ...family.fixture };
    let issuedReads = 0;
    let expiresReads = 0;
    Object.defineProperties(payload, {
      issuedAtSeconds: {
        configurable: true,
        enumerable: true,
        get() {
          issuedReads += 1;
          return issuedReads === 1 ? ISSUED : EXPIRES + 1;
        },
      },
      expiresAtSeconds: {
        configurable: true,
        enumerable: true,
        get() {
          expiresReads += 1;
          return EXPIRES;
        },
      },
    });
    expectTokenError(() => family.sign(payload), "PREVIEW_TOKEN_INVALID");
    expect({ issuedReads, expiresReads }).toEqual({
      issuedReads: 2,
      expiresReads: 2,
    });
  });

  it.each(FAMILIES)("$name rejects tampering and every cross-domain token", (family) => {
    const token = family.sign(family.fixture);
    const [version, body, signature] = token.split(".");
    const tamperedSignature = `${signature![0] === "A" ? "B" : "A"}${signature!.slice(1)}`;
    const tampered = `${version}.${body}.${tamperedSignature}`;
    expectTokenError(() => family.verify(tampered, NOW), "PREVIEW_TOKEN_INVALID");
    for (const other of FAMILIES) {
      if (other === family) continue;
      expectTokenError(
        () => other.verify(token, NOW),
        "PREVIEW_TOKEN_INVALID",
      );
    }
  });

  it.each([
    ["wrong token version", "v2.body.signature"],
    ["two token parts", "v1.body"],
    ["four token parts", "v1.body.signature.extra"],
    ["42-character signature", `v1.body.${"a".repeat(42)}`],
    ["43-character invalid-alphabet signature", `v1.body.${"a".repeat(42)}*`],
    ["over-limit 16385-character token", "x".repeat(16_385)],
    [
      "correctly signed invalid JSON body",
      tokenForBody(
        FAMILIES[0]!.domain,
        Buffer.from("{", "utf8").toString("base64url"),
      ),
    ],
    [
      "correctly signed valid JSON invalid payload",
      tokenForBody(
        FAMILIES[0]!.domain,
        Buffer.from('{"kind":"subscription.replace"}', "utf8").toString(
          "base64url",
        ),
      ),
    ],
  ] as const)("rejects %s", (label, token) => {
    const family = FAMILIES[0]!;
    expectTokenError(
      () => family.verify(token, NOW),
      "PREVIEW_TOKEN_INVALID",
      label,
    );
  });

  it("accepts a decoder-tolerated noncanonical token at the 16384-character boundary", () => {
    const family = FAMILIES[0]!;
    const token = decoderToleratedBoundaryToken(family);
    expect(token).toHaveLength(16_384);
    expect(family.verify(token, NOW)).toEqual(family.fixture);
  });

  it.each([
    ["exact 32-byte ASCII secret", ASCII_32_BYTE_SECRET],
    ["exact 32-byte multibyte UTF-8 secret", MULTIBYTE_32_BYTE_SECRET],
  ] as const)("signs and verifies with %s", (_label, secret) => {
    const family = FAMILIES[0]!;
    const token = signSubscriptionReplacePreview(
      secret,
      family.fixture as never,
    );
    expect(verifySubscriptionReplacePreview(secret, token, NOW)).toEqual(
      family.fixture,
    );
  });

  it.each([
    ["31-byte ASCII secret", "x".repeat(31)],
    ["31-byte multibyte UTF-8 secret", `${"я".repeat(15)}a`],
  ] as const)("rejects %s", (_label, secret) => {
    const family = FAMILIES[0]!;
    const token = family.sign(family.fixture);
    const error = new Error(
      "Subscription preview token secret must be at least 32 bytes.",
    );
    expect(() =>
      signSubscriptionReplacePreview(
        secret,
        family.fixture as never,
      ),
    ).toThrow(error);
    expect(() =>
      verifySubscriptionReplacePreview(secret, token, NOW),
    ).toThrow(error);
  });
});
