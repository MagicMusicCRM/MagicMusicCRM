import { Type } from "class-transformer";
import {
  Equals,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";
import { UpsertLessonDto } from "./upsert-lesson.dto";

export class LessonFinancialDecisionDto {
  @IsBoolean()
  chargeClient!: boolean;

  @IsBoolean()
  compensateTeacher!: boolean;
}

export class LessonCancelPreviewDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reasonText?: string;

  @ValidateNested()
  @Type(() => LessonFinancialDecisionDto)
  financialDecision!: LessonFinancialDecisionDto;
}

export class LessonCancelCommandDto extends LessonCancelPreviewDto {
  @Equals(true)
  confirm!: true;
}

export class LessonReschedulePreviewDto extends LessonCancelPreviewDto {
  @ValidateNested()
  @Type(() => UpsertLessonDto)
  successor!: UpsertLessonDto;
}

export class LessonRescheduleCommandDto extends LessonReschedulePreviewDto {
  @Equals(true)
  confirm!: true;
}
