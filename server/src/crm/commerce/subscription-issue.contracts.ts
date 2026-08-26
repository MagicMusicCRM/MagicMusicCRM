import {
  IssuedCommercialSnapshot,
  IssuedDiscountSnapshot,
  IssuedSurchargeSnapshot,
} from "./commerce-schema.types";
import {
  IssueDiscountColumns,
  PlannedInstallment,
} from "./subscription-issue.repository";
import { SubscriptionPurchasePreviewTokenPayload } from "./subscription-preview-token";

export interface CommerceMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface IssueMutationResult extends Record<string, unknown> {
  entityId: string;
  version: number;
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
