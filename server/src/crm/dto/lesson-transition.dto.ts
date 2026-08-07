import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  Equals,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from "class-validator";
import { ConfiguredLessonFinancialDecisionDto } from "./lesson-financial-decision.dto";
import { UpsertLessonDto } from "./upsert-lesson.dto";

export class LessonCancelPreviewDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reasonText!: string;

  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision!: ConfiguredLessonFinancialDecisionDto;
}

export class LessonCancelCommandDto extends LessonCancelPreviewDto {
  @IsString()
  @MaxLength(16_384)
  previewToken!: string;

  @Equals(true)
  confirm!: true;
}

export class LessonReschedulePreviewDto extends LessonCancelPreviewDto {
  @ValidateNested()
  @Type(() => UpsertLessonDto)
  successor!: UpsertLessonDto;
}

export class LessonRescheduleCommandDto extends LessonReschedulePreviewDto {
  @IsString()
  @MaxLength(16_384)
  previewToken!: string;

  @Equals(true)
  confirm!: true;
}

export class LessonSettlePreviewDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reasonText?: string;

  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision!: ConfiguredLessonFinancialDecisionDto;
}

export class LessonSettleCommandDto extends LessonSettlePreviewDto {
  @IsString()
  @MaxLength(16_384)
  previewToken!: string;

  @Equals(true)
  confirm!: true;
}

export class LessonBulkTransitionItemDto {
  @IsUUID()
  lessonId!: string;

  @IsIn(["reschedule", "cancel", "settle"])
  operation!: "reschedule" | "cancel" | "settle";

  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision!: ConfiguredLessonFinancialDecisionDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => UpsertLessonDto)
  successor?: UpsertLessonDto;
}

export class LessonBulkTransitionPreviewDto {
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reasonText!: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => LessonBulkTransitionItemDto)
  items!: LessonBulkTransitionItemDto[];
}

export class LessonBulkTransitionCommandDto extends LessonBulkTransitionPreviewDto {
  @IsString()
  @MaxLength(16_384)
  previewToken!: string;

  @Equals(true)
  confirm!: true;
}
