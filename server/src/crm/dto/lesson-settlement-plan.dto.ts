import { Type } from "class-transformer";
import {
  Equals,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from "class-validator";
import { ConfiguredLessonFinancialDecisionDto } from "./lesson-financial-decision.dto";
import { LessonResourcesDto } from "./lesson-resources.dto";

export class LessonSettlementPlanPreviewDto {
  @IsOptional()
  @ValidateNested()
  @Type(() => LessonResourcesDto)
  resources?: LessonResourcesDto;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision!: ConfiguredLessonFinancialDecisionDto;

  @IsString()
  @MinLength(3)
  @MaxLength(500)
  reasonText!: string;
}

export class LessonSettlementPlanCommandDto
  extends LessonSettlementPlanPreviewDto {
  @IsString()
  @MaxLength(16384)
  previewToken!: string;

  @IsBoolean()
  @Equals(true)
  confirm!: boolean;
}
