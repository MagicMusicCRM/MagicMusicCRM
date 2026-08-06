import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Matches,
} from "class-validator";

export class RecordActualPaymentDto {
  @IsUUID()
  issuedSubscriptionId: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsString()
  @Matches(/^[1-9]\d*$/)
  amountMinor: string;

  @IsIn(["cash", "cashless"])
  method: "cash" | "cashless";

  @IsDateString()
  occurredAt: string;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Z]{3}$/)
  currencyCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  comment?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  invoiceIdentifier?: string;
}
