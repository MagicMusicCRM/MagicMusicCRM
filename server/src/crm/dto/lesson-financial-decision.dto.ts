import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  ValidateNested,
} from "class-validator";

const stableKey = /^[A-Za-z0-9._:-]{1,120}$/;

export class LessonClientFinancialDecisionDto {
  @IsUUID()
  clientId!: string;

  @IsOptional()
  @IsString()
  @Matches(stableKey)
  settlementTypeKey?: string;

  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @IsOptional()
  @IsUUID()
  payerStudentId?: string;
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
  @IsString()
  @Matches(stableKey)
  teacherCompensationRuleKey!: string;

  @IsOptional()
  @IsString()
  @MaxLength(19)
  @Matches(/^\d+$/)
  teacherCompensationValueMinor?: string;
}
