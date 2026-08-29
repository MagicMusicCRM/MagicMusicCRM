import { Transform, Type } from "class-transformer";
import {
  ArrayMinSize,
  Equals,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from "class-validator";
import { ConfiguredLessonFinancialDecisionDto } from "./lesson-financial-decision.dto";

export class SchedulePlanRowDto {
  @IsOptional()
  @IsUUID()
  seriesId?: string;

  @IsUUID()
  teacherId!: string;

  @IsUUID()
  roomId!: string;

  @IsUUID()
  branchId!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(7)
  weekday!: number;

  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/)
  beginTime!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(15)
  @Max(480)
  durationMinutes?: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;

  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision!: ConfiguredLessonFinancialDecisionDto;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  plannedSettlementReason?: string;
}

export class SchedulePlanParticipantDto {
  @IsUUID()
  studentId!: string;

  @IsUUID()
  subscriptionId!: string;
}

export class CreateSchedulePlanDto {
  @IsIn(["individual", "group"])
  kind!: "individual" | "group";

  @IsString()
  @MaxLength(160)
  title!: string;

  @IsOptional()
  @IsUUID()
  studentId?: string;

  @IsOptional()
  @IsUUID()
  groupId?: string;

  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @IsDateString()
  activeFrom!: string;

  @IsOptional()
  @IsDateString()
  activeUntil?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(16_384)
  previewToken?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  confirmHistorical?: boolean;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SchedulePlanRowDto)
  rows!: SchedulePlanRowDto[];

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SchedulePlanParticipantDto)
  participants?: SchedulePlanParticipantDto[];
}

export class SchedulePlanConstraintPreviewDto extends CreateSchedulePlanDto {}

export class UpdateSchedulePlanDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsDateString()
  effectiveFrom!: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  title?: string;

  @IsOptional()
  @IsDateString()
  activeUntil?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(16_384)
  previewToken?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  confirmHistorical?: boolean;

  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => SchedulePlanRowDto)
  rows!: SchedulePlanRowDto[];

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SchedulePlanParticipantDto)
  participants?: SchedulePlanParticipantDto[];
}

export class SchedulePlanQuery {
  @IsOptional()
  @IsUUID()
  studentId?: string;

  @IsOptional()
  @IsUUID()
  groupId?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  includeEnded?: boolean;
}

export class SchedulePlanEndPreviewDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsDateString()
  lastDate!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reasonText!: string;
}

export class SchedulePlanEndCommandDto extends SchedulePlanEndPreviewDto {
  @IsString()
  @MaxLength(16_384)
  previewToken!: string;

  @Equals(true)
  confirm!: true;
}

export class SchedulePlanTrayQuery {
  @IsOptional()
  @IsString()
  @MaxLength(512)
  @Matches(/^[A-Za-z0-9_-]+$/)
  cursor?: string;

  @IsOptional()
  @IsIn(["previous", "next"])
  direction?: "previous" | "next";

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(40)
  limit?: number;
}
