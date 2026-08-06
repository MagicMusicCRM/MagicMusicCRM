import { ClientProjectionProfile } from "../../access-control/actor-client-projection.factory";

export interface CommerceProjectionScope {
  studentId: string;
  branchId: string | null;
  accessVersion: number;
  scopeKey: string;
}

export interface CommerceAccountDto {
  currencyCode: string;
  actualPaymentsMinor: string;
  adjustmentsMinor: string;
  obligationDebitsMinor: string;
  obligationCreditsMinor: string;
  writeOffsMinor: string;
  balanceMinor: string;
  debtMinor: string;
}

export type CommerceDiscountDto =
  | { type: "none" }
  | {
      type: "percent";
      percentBasisPoints: number;
      reason?: string;
    }
  | {
      type: "fixed";
      fixedMinor: string;
      reason?: string;
    };

export type CommerceSurchargeDto =
  | { type: "none" }
  | { type: "fixed"; amountMinor: string; reason?: string };

export interface CommerceInstallmentDto {
  installmentNumber: number;
  dueAt: string;
  amountMinor: string;
  currencyCode: string;
  status: string;
}

export interface CommerceSubscriptionDto {
  id: string;
  status: string;
  startsAt: string;
  expiresAt: string | null;
  units: {
    total: string;
    used: string;
    reserved: string;
    paid: string;
    available: string;
    remaining: string;
  };
  financial: {
    actualPaidMinor: string;
    obligationMinor: string;
    debtMinor: string;
    overpaymentMinor: string;
    nextPaymentAt: string | null;
  };
  terms: {
    displayName: string;
    validityDays: number | null;
    basePriceMinor: string;
    finalPriceMinor: string;
    currencyCode: string;
    discount: CommerceDiscountDto;
    surcharge?: CommerceSurchargeDto;
  };
  installments: CommerceInstallmentDto[];
}

export type CommerceMovementKind =
  | "payment"
  | "refund"
  | "adjustment"
  | "obligation"
  | "lesson_charge";

export interface CommerceMovementDto {
  id: string;
  kind: CommerceMovementKind;
  direction: "credit" | "debit";
  amountMinor: string;
  currencyCode: string;
  occurredAt: string;
  method: "cash" | "cashless" | null;
  factType: string | null;
  chargeType: string | null;
  branchId?: string | null;
  branchName?: string | null;
  comment?: string | null;
  invoiceIdentifier?: string | null;
  status?: "paid" | "pending" | "void" | null;
  acceptedByName?: string | null;
  issuedSubscriptionId?: string | null;
  subscriptionName?: string | null;
  sourcePaymentId?: string | null;
}

export interface CommerceLessonBalanceDto {
  activeSubscriptionCount: number;
  total: string;
  used: string;
  reserved: string;
  paid: string;
  available: string;
  debts: { currencyCode: string; amountMinor: string }[];
  nextPaymentAt: string | null;
  expiresAt: string | null;
}

export interface CommerceStudentDto {
  studentId: string;
  accounts: CommerceAccountDto[];
  subscriptions: CommerceSubscriptionDto[];
  movements: CommerceMovementDto[];
  lessonBalance: CommerceLessonBalanceDto;
}

export interface CommerceProjectionSource {
  studentId: string;
  accounts: CommerceAccountDto[];
  subscriptions: CommerceSubscriptionDto[];
  movements: CommerceMovementDto[];
  scope: CommerceProjectionScope;
}

export interface CommerceSelfResponse {
  projection: ClientProjectionProfile;
  students: CommerceStudentDto[];
}

export interface CommerceStudentResponse {
  projection: ClientProjectionProfile;
  student: CommerceStudentDto;
}
