export interface SubscriptionLifecycleMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface ReplacementResultRef extends Record<string, unknown> {
  sourceId: string;
  sourceVersion: number;
  resultId: string;
  resultVersion: number;
  payerStudentId: string;
  newPackageId: string;
  newPackageVersion: number;
  usedUnits: string;
  transferredReservationCount: number;
  transferredReservationUnits: string;
  releasedReservationCount: number;
  releasedReservationUnits: string;
  deltaMinor: string;
  positionKind: "debt" | "overpayment" | "settled";
  positionMinor: string;
  ccy: string;
  obligationFactId: string | null;
}

export interface CancellationResultRef extends Record<string, unknown> {
  sourceId: string;
  resultVersion: number;
  state: "cancelled";
  payerStudentId: string;
  releasedCount: number;
  releasedUnits: string;
  futureCount: number;
  closedRecordCount: number;
  confirmedFundedMinor: string;
  previousRefundMinor: string;
  unusedUnits: string;
  unfundedCancellationMinor: string;
  chosenRefundMinor: string;
  totalCreditMinor: string;
  creditFactId: string | null;
}

export interface LifecycleWarning {
  code: string;
  count?: number;
  units?: string;
  message: string;
}
