import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { IssueSubscriptionDiscountDto, IssueSubscriptionSurchargeDto } from "./issue-subscription.dto";

const stableKey = /^[A-Za-z0-9._:-]{1,120}$/;

export class LessonClientFinancialDecisionDto {
  @IsUUID()
  clientId!: string;

  @IsOptional()
  @IsString()
  @Matches(stableKey)
  settlementTypeKey?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  chargeDurationMinutes?: number;

  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @IsOptional()
  @IsUUID()
  payerStudentId?: string;

  @IsOptional()
  @IsIn(["subscription", "personal_account", "none"])
  chargeType?: "subscription" | "personal_account" | "none";

  @IsOptional()
  @IsString()
  @Matches(/^(0|[1-9]\d{0,11})$/)
  basePriceMinor?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => IssueSubscriptionDiscountDto)
  discount?: IssueSubscriptionDiscountDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => IssueSubscriptionSurchargeDto)
  surcharge?: IssueSubscriptionSurchargeDto;
}

export class ConfiguredLessonFinancialDecisionDto {
  @IsString()
  @Matches(stableKey)
  settlementTypeKey!: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(500)
  @ArrayUnique(
    (decision: LessonClientFinancialDecisionDto) => decision.clientId,
  )
  @ValidateNested({ each: true })
  @Type(() => LessonClientFinancialDecisionDto)
  clientDecisions?: LessonClientFinancialDecisionDto[];

  @IsOptional()
  @IsInt()
  @Min(0)
  teacherCreditedDurationMinutes?: number;

  @IsOptional()
  @IsIn(["automatic", "manual"])
  teacherCompensationSource?: "automatic" | "manual";

  @IsOptional()
  @IsString()
  @Matches(stableKey)
  teacherCompensationRuleKey!: string;

  @IsOptional()
  @IsString()
  @MaxLength(19)
  @Matches(/^\d+$/)
  teacherCompensationValueMinor?: string;
}

const canonicalClientDecision = (decision: LessonClientFinancialDecisionDto) => ({
  ...decision,
});

/** Compares rolling-contract aliases without depending on JSON property order. */
export const lessonFinancialDecisionCanonicalHash = (
  decision: ConfiguredLessonFinancialDecisionDto,
): string => fingerprintPayload({
  ...decision,
  clientDecisions: [...(decision.clientDecisions ?? [])]
    .sort((left, right) => left.clientId.localeCompare(right.clientId))
    .map(canonicalClientDecision),
});
