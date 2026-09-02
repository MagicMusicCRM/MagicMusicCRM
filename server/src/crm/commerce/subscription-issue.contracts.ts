import {
  IssuedCommercialSnapshot,
  IssuedDiscountSnapshot,
  IssuedSurchargeSnapshot,
} from "./commerce-schema.types";
import { SubscriptionPurchasePreviewTokenPayload } from "./subscription-preview-token";

export interface CommerceMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface IssueMutationResult extends Record<string, unknown> {
  entityId: string;
  version: number;
}

export interface IssueDiscountColumns {
  type: "none" | "percent" | "fixed";
  percentBasisPoints: number | null;
  fixedMinor: string | null;
  reason: string | null;
}

export interface PlannedInstallment {
  installmentNumber: number;
  dueAt: Date;
  amountMinor: string;
}

export interface NormalizedDiscount {
  snapshot: IssuedDiscountSnapshot;
  columns: IssueDiscountColumns;
  finalPriceMinor: string;
}

export interface NormalizedSurcharge {
  snapshot: IssuedSurchargeSnapshot;
  amountMinor: string;
}

export interface NormalizedPurchase {
  discount: NormalizedDiscount;
  surcharge: NormalizedSurcharge;
  finalPriceMinor: string;
  installments: PlannedInstallment[];
  snapshot: IssuedCommercialSnapshot;
  purchaseReason: string | null;
  startsAt: string;
  expiresAt: string | null;
  payment: {
    amountMinor: string;
    occurredAt: Date | null;
    method: "cash" | "cashless" | null;
    comment: string | null;
  };
}

export interface NormalizedIssue {
  discount: NormalizedDiscount;
  surcharge: NormalizedSurcharge;
  finalPriceMinor: string;
  installments: PlannedInstallment[];
  snapshot: IssuedCommercialSnapshot;
}

export type UnsignedPurchaseTokenPayload = Omit<
  SubscriptionPurchasePreviewTokenPayload,
  "issuedAtSeconds" | "expiresAtSeconds"
>;
