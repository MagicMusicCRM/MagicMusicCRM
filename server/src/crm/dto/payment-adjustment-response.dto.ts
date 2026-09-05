import { ApiProperty } from '@nestjs/swagger';

/** Wire contracts for the existing preview/commit payment commands. */
export class PaymentCorrectionValuesDto {
  @ApiProperty({ type: String, pattern: '^[1-9][0-9]*$' })
  amountMinor!: string;

  @ApiProperty({ type: String, enum: ['unpaid', 'posted_pending', 'paid'] })
  status!: string;

  @ApiProperty({ type: String, format: 'date-time', nullable: true })
  dueAt!: string | null;

  @ApiProperty({ type: String, nullable: true })
  method!: string | null;

  @ApiProperty({ type: String, nullable: true })
  externalIdentifier!: string | null;

  @ApiProperty({ type: String, format: 'date-time', nullable: true })
  occurredAt!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  branchId!: string | null;

  @ApiProperty({ type: String, nullable: true })
  verificationNote!: string | null;

}

export class PaymentCorrectionPreviewDto {
  @ApiProperty({ type: String, format: 'uuid' })
  paymentRecordId!: string;

  @ApiProperty({ type: 'integer', minimum: 1 })
  expectedVersion!: number;

  @ApiProperty({ type: String })
  currencyCode!: string;

  @ApiProperty({ type: PaymentCorrectionValuesDto })
  before!: PaymentCorrectionValuesDto;

  @ApiProperty({ type: PaymentCorrectionValuesDto })
  after!: PaymentCorrectionValuesDto;

  @ApiProperty({ type: String, pattern: '^-?(0|[1-9][0-9]*)$' })
  walletDeltaMinor!: string;

  @ApiProperty({ type: String, pattern: '^-?(0|[1-9][0-9]*)$' })
  walletBalanceMinor!: string;

  @ApiProperty({ type: String, pattern: '^-?(0|[1-9][0-9]*)$' })
  resultingBalanceMinor!: string;

  @ApiProperty({ type: Boolean })
  negativeBalanceWarning!: boolean;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  issuedSubscriptionId!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  installmentId!: string | null;

  @ApiProperty({ type: String })
  previewToken!: string;

  @ApiProperty({ type: String, format: 'date-time' })
  expiresAt!: string;

}

export class PaymentReversalPreviewDto {
  @ApiProperty({ type: String, format: 'uuid' })
  paymentRecordId!: string;

  @ApiProperty({ type: String, enum: ['unpaid', 'posted_pending', 'paid'] })
  status!: string;

  @ApiProperty({ type: String, pattern: '^[1-9][0-9]*$' })
  amountMinor!: string;

  @ApiProperty({ type: String })
  currencyCode!: string;

  @ApiProperty({ type: String, pattern: '^-?(0|[1-9][0-9]*)$' })
  walletDeltaMinor!: string;

  @ApiProperty({ type: String, pattern: '^-?(0|[1-9][0-9]*)$' })
  walletBalanceMinor!: string;

  @ApiProperty({ type: String, pattern: '^-?(0|[1-9][0-9]*)$' })
  resultingBalanceMinor!: string;

  @ApiProperty({ type: Boolean })
  negativeBalanceWarning!: boolean;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  issuedSubscriptionId!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  installmentId!: string | null;

  @ApiProperty({ type: String, enum: ['monetary_reversal', 'technical_void'] })
  operation!: string;

  @ApiProperty({ type: String })
  previewToken!: string;

  @ApiProperty({ type: String, format: 'date-time' })
  expiresAt!: string;

}

export class PaymentCorrectionFactDto {
  @ApiProperty({ type: String, format: 'uuid' })
  id!: string;

  @ApiProperty({ type: String, format: 'uuid' })
  sourcePaymentRecordId!: string;

  @ApiProperty({ type: String, format: 'uuid' })
  replacementPaymentRecordId!: string;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  reversalAdjustmentId!: string | null;

  @ApiProperty({ type: String })
  reason!: string;

  @ApiProperty({ type: String, format: 'date-time' })
  occurredAt!: string;

}

export class PaymentReplacementSummaryDto {
  @ApiProperty({ type: String, format: 'uuid' })
  id!: string;

  @ApiProperty({ type: String, pattern: '^[1-9][0-9]*$' })
  amountMinor!: string;

  @ApiProperty({ type: String })
  currencyCode!: string;

  @ApiProperty({ type: String, enum: ['unpaid', 'posted_pending', 'paid'] })
  status!: string;

  @ApiProperty({ type: 'integer', minimum: 1 })
  version!: number;

}

export class PaymentCorrectionResponseDto {
  @ApiProperty({ type: PaymentCorrectionFactDto })
  correction!: PaymentCorrectionFactDto;

  @ApiProperty({ type: PaymentReplacementSummaryDto })
  replacement!: PaymentReplacementSummaryDto;

  @ApiProperty({ type: String, pattern: '^-?(0|[1-9][0-9]*)$' })
  resultingBalanceMinor!: string;

  @ApiProperty({ type: Boolean })
  replayed!: boolean;

  @ApiProperty({ type: String, format: 'uuid' })
  auditId!: string;

  @ApiProperty({ type: String, format: 'uuid' })
  eventId!: string;

}

export class PaymentExclusionDto {
  @ApiProperty({ type: String, format: 'uuid' })
  id!: string;

  @ApiProperty({ type: String, enum: ['payment', 'payment_record'] })
  sourceKind!: string;

  @ApiProperty({ type: String, format: 'uuid' })
  sourceId!: string;

  @ApiProperty({ type: String, nullable: true })
  counterpartKind!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  counterpartId!: string | null;

  @ApiProperty({ type: String })
  reason!: string;

  @ApiProperty({ type: String, format: 'uuid' })
  actorUserId!: string;

  @ApiProperty({ type: String, nullable: true })
  actorName!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  auditEventId!: string | null;

  @ApiProperty({ type: String, format: 'date-time' })
  occurredAt!: string;

}

export class PaymentReversalResponseDto {
  @ApiProperty({ type: String, format: 'uuid' })
  paymentRecordId!: string;

  @ApiProperty({ type: String, enum: ['monetary_reversal', 'technical_void'] })
  operation!: string;

  @ApiProperty({ type: PaymentExclusionDto })
  exclusion!: PaymentExclusionDto;

  @ApiProperty({ type: Boolean })
  replayed!: boolean;

}

