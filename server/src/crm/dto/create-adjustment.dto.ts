import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Matches,
} from 'class-validator';

export class RecordPaymentAdjustmentDto {
  @IsUUID()
  sourcePaymentId: string;

  @IsIn(['refund', 'correction'])
  kind: 'refund' | 'correction';

  @IsString()
  @Matches(/^[1-9]\d*$/)
  amountMinor: string;

  @IsOptional()
  @IsIn(['income', 'outcome'])
  direction?: 'income' | 'outcome';

  @IsString()
  @MaxLength(1000)
  reason: string;

  @IsDateString()
  occurredAt: string;
}
