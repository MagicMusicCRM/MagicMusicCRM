import { Type } from "class-transformer";
import {
  Equals,
  IsBoolean,
  IsInt,
  IsString,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from "class-validator";
import { ConfiguredLessonFinancialDecisionDto } from "./lesson-financial-decision.dto";

export class LessonSettlementCorrectionPreviewDto {
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

export class LessonSettlementCorrectionCommandDto
  extends LessonSettlementCorrectionPreviewDto {
  @IsString()
  @MaxLength(16384)
  previewToken!: string;

  @IsBoolean()
  @Equals(true)
  confirm!: boolean;
}
