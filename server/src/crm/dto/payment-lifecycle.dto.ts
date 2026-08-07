import { Type } from "class-transformer";
import {
  IsDateString,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
} from "class-validator";

export class CreatePaymentRecordDto {
  @IsOptional()
  @IsUUID()
  issuedSubscriptionId?: string;

  @IsOptional()
  @IsUUID()
  installmentId?: string;

  @IsString()
  @Matches(/^[1-9]\d*$/)
  amountMinor: string;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Z]{3}$/)
  currencyCode?: string;

  @IsIn(["unpaid", "posted_pending", "paid"])
  status: "unpaid" | "posted_pending" | "paid";

  @IsOptional()
  @IsDateString()
  dueAt?: string;

  @IsOptional()
  @IsIn(["cash", "cashless"])
  method?: "cash" | "cashless";

  @IsOptional()
  @IsString()
  @MaxLength(120)
  externalIdentifier?: string;

  @IsOptional()
  @IsDateString()
  occurredAt?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  verificationNote?: string;

  @IsString()
  @MaxLength(1000)
  reason: string;
}

export class TransitionPaymentRecordDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion: number;

  @IsIn(["unpaid", "posted_pending", "paid"])
  targetStatus: "unpaid" | "posted_pending" | "paid";

  @IsOptional()
  @IsIn(["cash", "cashless"])
  method?: "cash" | "cashless";

  @IsOptional()
  @IsString()
  @MaxLength(120)
  externalIdentifier?: string;

  @IsOptional()
  @IsDateString()
  occurredAt?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  verificationNote?: string;

  @IsString()
  @MaxLength(1000)
  reason: string;
}

export class PreviewPaymentReversalDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion: number;
}

export class ReversePaymentDto {
  @IsString()
  @MaxLength(16384)
  previewToken: string;

  @IsBoolean()
  confirm: boolean;

  @IsString()
  @MaxLength(1000)
  reason: string;
}
