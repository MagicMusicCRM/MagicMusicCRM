export type CurrencyCode = string;

export interface SubscriptionPackageEntity {
  id: string;
  name: string;
  unitCount: string;
  validityDays: number | null;
  basePriceMinor: string;
  currencyCode: CurrencyCode;
  active: boolean;
  version: number;
}

export type IssuedDiscountSnapshot =
  | { type: "none" }
  | {
      type: "percent";
      percentBasisPoints: number;
      reason: string;
    }
  | {
      type: "fixed";
      fixedMinor: string;
      reason: string;
    };

export type IssuedSurchargeSnapshot =
  | { type: "none" }
  | { type: "fixed"; amountMinor: string; reason: string };

export interface IssuedCommercialSnapshot {
  snapshotVersion: number;
  packageVersion: number;
  displayName: string;
  unitCount: string;
  validityDays: number | null;
  basePriceMinor: string;
  currencyCode: CurrencyCode;
  discount: IssuedDiscountSnapshot;
  surcharge?: IssuedSurchargeSnapshot;
  finalPriceMinor: string;
  installments?: {
    installmentNumber: number;
    dueAt: string;
    amountMinor: string;
  }[];
  paymentMethod?: "cash" | "cashless" | null;
  commercialRules: Record<string, unknown>;
}

export interface IssuedSubscriptionEntity {
  id: string;
  studentId: string;
  payerStudentId?: string | null;
  fundingMode?: SubscriptionFundingMode | null;
  purchaseReason?: string | null;
  packageId: string;
  status: string;
  version: number;
  commercialSnapshot: IssuedCommercialSnapshot;
}

export type SubscriptionFundingMode =
  | "personal_account"
  | "installment"
  | "legacy";

export type ClientPaymentStatus = "unpaid" | "posted_pending" | "paid";

export interface ClientPaymentRecordEntity {
  id: string;
  studentId: string;
  issuedSubscriptionId: string | null;
  installmentId: string | null;
  amountMinor: string;
  currencyCode: CurrencyCode;
  status: ClientPaymentStatus;
  dueAt: Date | null;
  method: string | null;
  externalIdentifier: string | null;
  verificationNote: string | null;
  actualPaymentId: string | null;
  version: number;
  createdBy: string | null;
  verifiedBy: string | null;
  verifiedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface ClientPaymentStatusEventEntity {
  id: string;
  paymentRecordId: string;
  beforeStatus: ClientPaymentStatus | null;
  afterStatus: ClientPaymentStatus;
  reason: string;
  actorUserId: string | null;
  aggregateVersion: number;
  actualPaymentId: string | null;
  occurredAt: Date;
}

export type CommerceReportingSourceKind =
  | "payment"
  | "payment_record"
  | "account_adjustment";

export interface CommerceReportingExclusionEntity {
  id: string;
  sourceKind: CommerceReportingSourceKind;
  sourceId: string;
  counterpartKind: CommerceReportingSourceKind | null;
  counterpartId: string | null;
  reason: string;
  actorUserId: string;
  auditEventId: string | null;
  occurredAt: Date;
}

export interface SubscriptionInstallmentEntity {
  id: string;
  issuedSubscriptionId: string;
  installmentNumber: number;
  dueAt: Date;
  amountMinor: string;
  currencyCode: CurrencyCode;
  status: "pending" | "paid" | "void";
  version: number;
}

export interface ActualPaymentEntity {
  id: string;
  studentId: string;
  issuedSubscriptionId: string | null;
  amountMinor: string;
  currencyCode: CurrencyCode;
  method: "cash" | "cashless";
  occurredAt: Date;
  idempotencyRef: string;
  requestFingerprint: string;
}

export type ObligationFactType =
  | "issue"
  | "installment"
  | "replacement_debt"
  | "replacement_overpayment"
  | "adjustment"
  | "reversal";

export interface ObligationFactEntity {
  id: string;
  studentId: string;
  issuedSubscriptionId: string | null;
  factType: ObligationFactType;
  direction: "debit" | "credit";
  amountMinor: string;
  currencyCode: CurrencyCode;
  sourceType: string;
  sourceRef: string;
  occurredAt: Date;
}

export type SubscriptionLifecycleEventType = "issue" | "replace" | "cancel";

export interface SubscriptionLifecycleEventEntity {
  id: string;
  issuedSubscriptionId: string;
  eventType: SubscriptionLifecycleEventType;
  beforeIssuedSubscriptionId: string | null;
  afterIssuedSubscriptionId: string | null;
  actorUserId: string | null;
  reason: string;
  aggregateVersion: number;
  occurredAt: Date;
}
