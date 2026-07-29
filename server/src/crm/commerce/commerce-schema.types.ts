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

export interface IssuedCommercialSnapshot {
  snapshotVersion: number;
  packageVersion: number;
  displayName: string;
  unitCount: string;
  validityDays: number | null;
  basePriceMinor: string;
  currencyCode: CurrencyCode;
  discount: IssuedDiscountSnapshot;
  finalPriceMinor: string;
  commercialRules: Record<string, unknown>;
}

export interface IssuedSubscriptionEntity {
  id: string;
  studentId: string;
  packageId: string;
  status: string;
  version: number;
  commercialSnapshot: IssuedCommercialSnapshot;
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
