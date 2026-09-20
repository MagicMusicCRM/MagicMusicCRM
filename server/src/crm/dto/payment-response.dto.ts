import { ApiExtraModels, ApiProperty, getSchemaPath } from '@nestjs/swagger';
import { ClientPaymentStatus } from '../commerce/commerce-schema.types';

/** Transport types only; PaymentLifecycleService owns all state transitions. */
export class PaymentActorDto {
  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  userId!: string | null;

  @ApiProperty({ type: String, nullable: true })
  name!: string | null;

}

export class PaymentRecordResponseDto {
  @ApiProperty({ type: String, format: 'uuid' })
  id!: string;

  @ApiProperty({ type: String, format: 'uuid' })
  studentId!: string;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  issuedSubscriptionId!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  installmentId!: string | null;

  @ApiProperty({ type: String, pattern: '^[1-9][0-9]*$' })
  amountMinor!: string;

  @ApiProperty({ type: String })
  currencyCode!: string;

  @ApiProperty({ type: String, enum: ['unpaid', 'posted_pending', 'paid'] })
  status!: ClientPaymentStatus;

  @ApiProperty({ type: String, format: 'date-time', nullable: true })
  dueAt!: string | Date | null;

  @ApiProperty({ type: String, enum: ['cash', 'cashless', null], nullable: true })
  method!: string | null;

  @ApiProperty({ type: String, nullable: true })
  externalIdentifier!: string | null;

  @ApiProperty({ type: String, nullable: true })
  verificationNote!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  actualPaymentId!: string | null;

  @ApiProperty({ type: 'integer', minimum: 1 })
  version!: number;

  @ApiProperty({ type: PaymentActorDto })
  createdBy!: PaymentActorDto;

  @ApiProperty({ type: PaymentActorDto })
  verifiedBy!: PaymentActorDto;

  @ApiProperty({ type: String, format: 'date-time', nullable: true })
  verifiedAt!: string | Date | null;

  @ApiProperty({ type: String, nullable: true })
  subscriptionName!: string | null;

  @ApiProperty({ type: String, format: 'uuid' })
  recipientStudentId!: string;

  @ApiProperty({ type: String, format: 'date-time' })
  createdAt!: string | Date;

  @ApiProperty({ type: String, format: 'date-time' })
  updatedAt!: string | Date;

}

export class PaymentStatusEventDto {
  @ApiProperty({ type: String, format: 'uuid' })
  id!: string;

  @ApiProperty({ type: String, enum: ['unpaid', 'posted_pending', 'paid', null], nullable: true })
  beforeStatus!: ClientPaymentStatus | null;

  @ApiProperty({ type: String, enum: ['unpaid', 'posted_pending', 'paid'] })
  afterStatus!: ClientPaymentStatus;

  @ApiProperty({ type: String })
  reason!: string;

  @ApiProperty({ type: PaymentActorDto })
  actor!: PaymentActorDto;

  @ApiProperty({ type: 'integer', minimum: 1 })
  version!: number;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  actualPaymentId!: string | null;

  @ApiProperty({ type: String, format: 'date-time' })
  occurredAt!: string | Date;

}

export class ActualPaymentResponseDto {
  @ApiProperty({ type: String, format: 'uuid' })
  id!: string;

  @ApiProperty({ type: String, format: 'uuid' })
  studentId!: string;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  issuedSubscriptionId!: string | null;

  @ApiProperty({ type: String, pattern: '^[1-9][0-9]*$' })
  amountMinor!: string;

  @ApiProperty({ type: String })
  currencyCode!: string;

  @ApiProperty({ type: String, enum: ['cash', 'cashless'] })
  method!: string;

  @ApiProperty({ type: String, format: 'date-time' })
  occurredAt!: string | Date;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  branchId!: string | null;

  @ApiProperty({ type: String, nullable: true })
  branchName!: string | null;

  @ApiProperty({ type: String, nullable: true })
  comment!: string | null;

  @ApiProperty({ type: String, nullable: true })
  invoiceIdentifier!: string | null;

  @ApiProperty({ type: String, enum: ['paid'] })
  status!: 'paid';

  @ApiProperty({ type: PaymentActorDto })
  acceptedBy!: PaymentActorDto;

  @ApiProperty({ type: 'integer', minimum: 1 })
  version!: number;

  @ApiProperty({ type: String, format: 'date-time' })
  createdAt!: string | Date;

}

@ApiExtraModels(ActualPaymentResponseDto)
export class PaymentCommandResponseDto {
  @ApiProperty({ type: PaymentRecordResponseDto })
  paymentRecord!: PaymentRecordResponseDto;

  @ApiProperty({ type: [PaymentStatusEventDto] })
  statusHistory!: PaymentStatusEventDto[];

  @ApiProperty({ oneOf: [
    { $ref: getSchemaPath(ActualPaymentResponseDto) },
    { type: 'object', nullable: true, enum: [null] },
  ] })
  actualPayment!: ActualPaymentResponseDto | null;

}
