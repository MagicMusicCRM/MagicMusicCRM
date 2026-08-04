import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
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
import { Type } from "class-transformer";

export const STUDENT_FUNNEL_STYLES = [
  "cyan",
  "green",
  "amber",
  "slate",
  "gray",
  "red",
] as const;

export class StudentFunnelQuery {
  @IsOptional()
  @IsUUID()
  branchId?: string;
}

export class StudentFunnelStageDto {
  @IsString()
  @Matches(/^[a-z][a-z0-9_-]{0,63}$/)
  key: string;

  @IsString()
  @MaxLength(80)
  label: string;

  @IsString()
  @IsIn(STUDENT_FUNNEL_STYLES)
  style: (typeof STUDENT_FUNNEL_STYLES)[number];

  @IsBoolean()
  active: boolean;

  @IsArray()
  @ArrayMaxSize(30)
  @IsString({ each: true })
  allowedTransitions: string[];
}

export class PublishStudentFunnelDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsInt()
  @Min(0)
  expectedVersion: number;

  @IsString()
  @MaxLength(500)
  reason: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(30)
  @ValidateNested({ each: true })
  @Type(() => StudentFunnelStageDto)
  stages: StudentFunnelStageDto[];
}

export class RollbackStudentFunnelDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsInt()
  @Min(0)
  expectedVersion: number;

  @IsInt()
  @Min(1)
  targetVersion: number;

  @IsString()
  @MaxLength(500)
  reason: string;
}
