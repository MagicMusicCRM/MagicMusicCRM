import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

export class ScheduleReferenceQuery {
  @IsUUID()
  branchId!: string;

  @IsUUID()
  teacherId!: string;

  @IsISO8601({ strict: true })
  from!: string;

  @IsISO8601({ strict: true })
  to!: string;
}

export class BranchWeeklyHoursDto {
  @IsInt()
  @Min(1)
  @Max(7)
  weekday!: number;

  @Matches(TIME_PATTERN)
  open!: string;

  @Matches(TIME_PATTERN)
  close!: string;
}

export class BranchHoursExceptionDto {
  @Matches(DATE_PATTERN)
  date!: string;

  @IsBoolean()
  closed!: boolean;

  @IsOptional()
  @Matches(TIME_PATTERN)
  open?: string;

  @IsOptional()
  @Matches(TIME_PATTERN)
  close?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  reason?: string;
}

export class ReplaceBranchHoursDto {
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsString()
  @MaxLength(80)
  timezone!: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(7)
  @ValidateNested({ each: true })
  @Type(() => BranchWeeklyHoursDto)
  weekly!: BranchWeeklyHoursDto[];

  @IsArray()
  @ArrayMaxSize(366)
  @ValidateNested({ each: true })
  @Type(() => BranchHoursExceptionDto)
  exceptions!: BranchHoursExceptionDto[];
}

export class TeacherBranchAssignmentDto {
  @IsUUID()
  branchId!: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  activeFrom?: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  activeUntil?: string;
}

export class ReplaceTeacherBranchesDto {
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => TeacherBranchAssignmentDto)
  assignments!: TeacherBranchAssignmentDto[];
}

export class TeacherAvailabilityRuleDto {
  @IsIn(["recurring", "interval"])
  kind!: "recurring" | "interval";

  @IsBoolean()
  available!: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  timezone?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(7)
  weekday?: number;

  @IsOptional()
  @Matches(TIME_PATTERN)
  localStart?: string;

  @IsOptional()
  @Matches(TIME_PATTERN)
  localEnd?: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  validFrom?: string;

  @IsOptional()
  @Matches(DATE_PATTERN)
  validUntil?: string;

  @IsOptional()
  @IsISO8601({ strict: true })
  startsAt?: string;

  @IsOptional()
  @IsISO8601({ strict: true })
  endsAt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  reason?: string;
}

export class ReplaceTeacherAvailabilityDto {
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => TeacherAvailabilityRuleDto)
  rules!: TeacherAvailabilityRuleDto[];
}
