import {
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
} from "class-validator";

export class RecordActualPaymentDto {
  @IsOptional()
  @IsUUID()
  issuedSubscriptionId?: string;

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
}
