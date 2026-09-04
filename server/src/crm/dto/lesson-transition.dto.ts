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
import { UnprocessableEntityException } from "@nestjs/common";
import type { NormalizedReschedulePreview } from "../schedule/lesson-transition.types";
import {
  ConfiguredLessonFinancialDecisionDto,
  lessonFinancialDecisionCanonicalHash,
} from "./lesson-financial-decision.dto";
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

export class LessonReschedulePreviewDto {
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
  @Type(() => UpsertLessonDto)
  successor!: UpsertLessonDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  successorFinancialDecision?: ConfiguredLessonFinancialDecisionDto;

  /** Build 210 compatibility alias; normalized as successor-only. */
  @IsOptional()
  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision?: ConfiguredLessonFinancialDecisionDto;
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

  @IsOptional()
  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision?: ConfiguredLessonFinancialDecisionDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  successorFinancialDecision?: ConfiguredLessonFinancialDecisionDto;

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

const zeroSourceDecision = (
  successor: ConfiguredLessonFinancialDecisionDto,
) => ({
  settlementTypeKey: "free_lesson",
  clientDecisions: [...new Set(
    (successor.clientDecisions ?? []).map((decision) => decision.clientId),
  )].sort().map((clientId) => ({
    clientId,
    settlementTypeKey: "free_lesson",
    chargeType: "none" as const,
    chargeDurationMinutes: 0,
  })),
  teacherCompensationRuleKey: "none",
  teacherCreditedDurationMinutes: 0,
});

export function normalizeRescheduleDto(
  dto: LessonReschedulePreviewDto,
): NormalizedReschedulePreview {
  const current = dto.successorFinancialDecision;
  const legacy = dto.financialDecision;
  if (!current && !legacy) {
    throw new UnprocessableEntityException({
      code: "LESSON_RESCHEDULE_SUCCESSOR_DECISION_REQUIRED",
      fields: ["successorFinancialDecision"],
    });
  }
  if (
    current && legacy &&
    lessonFinancialDecisionCanonicalHash(current) !==
      lessonFinancialDecisionCanonicalHash(legacy)
  ) {
    throw new UnprocessableEntityException({
      code: "LESSON_RESCHEDULE_DECISION_AMBIGUOUS",
      fields: ["successorFinancialDecision", "financialDecision"],
    });
  }
  const successorFinancialDecision = current ?? legacy!;
  return {
    operation: "reschedule",
    expectedVersion: dto.expectedVersion,
    reasonCode: dto.reasonCode,
    reasonText: dto.reasonText,
    successor: dto.successor,
    sourceFinancialDecision: zeroSourceDecision(successorFinancialDecision),
    successorFinancialDecision,
  };
}
