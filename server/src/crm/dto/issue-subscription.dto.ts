import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateIf,
  ValidateNested,
} from "class-validator";

export class IssueSubscriptionDiscountDto {
  @IsIn(["percent", "fixed"])
  type: "percent" | "fixed";

  @ValidateIf((value: IssueSubscriptionDiscountDto) =>
    value.type === "percent",
  )
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @Max(100)
  percent?: number;

  @ValidateIf((value: IssueSubscriptionDiscountDto) =>
    value.type === "fixed",
  )
  @IsString()
  @Matches(/^(0|[1-9]\d*)$/)
  fixedMinor?: string;

  @IsString()
  @MaxLength(500)
  reason: string;
}

export class IssueSubscriptionInstallmentDto {
  @IsDateString()
  dueAt: string;

  @IsString()
  @Matches(/^[1-9]\d*$/)
  amountMinor: string;
}

export class IssueSubscriptionSurchargeDto {
  @IsString()
  @Matches(/^[1-9]\d*$/)
  amountMinor: string;

  @IsString()
  @MaxLength(500)
  reason: string;
}

export class IssueSubscriptionDto {
  @IsUUID()
  packageId: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => IssueSubscriptionDiscountDto)
  discount?: IssueSubscriptionDiscountDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => IssueSubscriptionSurchargeDto)
  surcharge?: IssueSubscriptionSurchargeDto;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(2)
  @ValidateNested({ each: true })
  @Type(() => IssueSubscriptionInstallmentDto)
  installments?: IssueSubscriptionInstallmentDto[];

  @IsOptional()
  @IsIn(["cash", "cashless"])
  paymentMethod?: "cash" | "cashless";
}
