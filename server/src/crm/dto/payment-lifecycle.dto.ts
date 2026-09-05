import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import {
  Equals,
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
  @ApiPropertyOptional({ type: String, format: "uuid" })
  lessonId?: string;

  @IsOptional()
  @IsUUID()
  @ApiPropertyOptional({ type: String, format: "uuid" })
  issuedSubscriptionId?: string;

  @IsOptional()
  @IsUUID()
  @ApiPropertyOptional({ type: String, format: "uuid" })
  installmentId?: string;

  @IsString()
  @Matches(/^[1-9]\d*$/)
  @ApiProperty({ type: String, pattern: "^[1-9][0-9]*$", maxLength: 12, description: "Integer minor units encoded as a decimal string." })
  amountMinor: string;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Z]{3}$/)
  @ApiPropertyOptional({ type: String, pattern: "^[A-Z]{3}$" })
  currencyCode?: string;

  @IsIn(["unpaid", "posted_pending", "paid"])
  @ApiProperty({ type: String, enum: ["unpaid", "posted_pending", "paid"] })
  status: "unpaid" | "posted_pending" | "paid";

  @IsOptional()
  @IsDateString()
  @ApiPropertyOptional({ type: String, description: "ISO 8601 due date." })
  dueAt?: string;

  @IsOptional()
  @IsIn(["cash", "cashless"])
  @ApiPropertyOptional({ type: String, enum: ["cash", "cashless"], description: "Required when status is paid." })
  method?: "cash" | "cashless";

  @IsOptional()
  @IsString()
  @MaxLength(120)
  @ApiPropertyOptional({ type: String, maxLength: 120, description: "Receipt or transaction identifier; required when paid." })
  externalIdentifier?: string;

  @IsOptional()
  @IsDateString()
  @ApiPropertyOptional({ type: String, description: "ISO 8601 receipt date; required when paid." })
  occurredAt?: string;

  @IsOptional()
  @IsUUID()
  @ApiPropertyOptional({ type: String, format: "uuid", description: "Must match the student branch." })
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  @ApiPropertyOptional({ type: String, maxLength: 1000 })
  verificationNote?: string;

  @IsString()
  @MaxLength(500)
  @ApiProperty({ type: String, maxLength: 500 })
  reason: string;
}

export class TransitionPaymentRecordDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @ApiProperty({ type: "integer", minimum: 1 })
  expectedVersion: number;

  @IsIn(["unpaid", "posted_pending", "paid"])
  @ApiProperty({ type: String, enum: ["unpaid", "posted_pending", "paid"] })
  targetStatus: "unpaid" | "posted_pending" | "paid";

  @IsOptional()
  @IsIn(["cash", "cashless"])
  @ApiPropertyOptional({ type: String, enum: ["cash", "cashless"], description: "Required when status is paid." })
  method?: "cash" | "cashless";

  @IsOptional()
  @IsString()
  @MaxLength(120)
  @ApiPropertyOptional({ type: String, maxLength: 120, description: "Receipt or transaction identifier; required when paid." })
  externalIdentifier?: string;

  @IsOptional()
  @IsDateString()
  @ApiPropertyOptional({ type: String, description: "ISO 8601 receipt date; required when paid." })
  occurredAt?: string;

  @IsOptional()
  @IsUUID()
  @ApiPropertyOptional({ type: String, format: "uuid", description: "Must match the student branch." })
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  @ApiPropertyOptional({ type: String, maxLength: 1000 })
  verificationNote?: string;

  @IsString()
  @MaxLength(500)
  @ApiProperty({ type: String, maxLength: 500 })
  reason: string;
}

export class PreviewPaymentReversalDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @ApiProperty({ type: "integer", minimum: 1 })
  expectedVersion: number;
}

export class ReversePaymentDto {
  @IsString()
  @MaxLength(16384)
  @ApiProperty({ type: String, maxLength: 16384 })
  previewToken: string;

  @IsBoolean()
  @ApiProperty({ type: Boolean, enum: [true] })
  confirm: boolean;

  @IsString()
  @MaxLength(500)
  @ApiProperty({ type: String, maxLength: 500 })
  reason: string;
}

export class PreviewPaymentCorrectionDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @ApiProperty({ type: "integer", minimum: 1 })
  expectedVersion: number;

  @IsString()
  @Matches(/^[1-9]\d*$/)
  @ApiProperty({ type: String, pattern: "^[1-9][0-9]*$", maxLength: 12 })
  amountMinor: string;

  @IsIn(["unpaid", "posted_pending", "paid"])
  @ApiProperty({ type: String, enum: ["unpaid", "posted_pending", "paid"] })
  status: "unpaid" | "posted_pending" | "paid";

  @IsOptional()
  @IsDateString()
  @ApiPropertyOptional({ type: String, description: "ISO 8601 date." })
  dueAt?: string;

  @IsOptional()
  @IsIn(["cash", "cashless"])
  @ApiPropertyOptional({ type: String, enum: ["cash", "cashless"] })
  method?: "cash" | "cashless";

  @IsOptional()
  @IsString()
  @MaxLength(120)
  @ApiPropertyOptional({ type: String, maxLength: 120 })
  externalIdentifier?: string;

  @IsOptional()
  @IsDateString()
  @ApiPropertyOptional({ type: String, description: "ISO 8601 receipt date." })
  occurredAt?: string;

  @IsOptional()
  @IsUUID()
  @ApiPropertyOptional({ type: String, format: "uuid" })
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  @ApiPropertyOptional({ type: String, maxLength: 1000 })
  verificationNote?: string;
}

export class CorrectPaymentDto {
  @IsString()
  @MaxLength(16384)
  @ApiProperty({ type: String, maxLength: 16384 })
  previewToken: string;

  @IsBoolean()
  @Equals(true)
  @ApiProperty({ type: Boolean, enum: [true] })
  confirm: true;

  @IsString()
  @MaxLength(500)
  @ApiProperty({ type: String, maxLength: 500 })
  reason: string;
}
