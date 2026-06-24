import { Transform, Type } from "class-transformer";
import {
  IsBoolean,
  IsDateString,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export class StudentSearchQuery {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  q?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  status?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsUUID()
  groupId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  discipline?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  level?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  category?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  linkedUser?: boolean;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  noEmail?: boolean;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  noOpenTasks?: boolean;

  // Board filter for the «Без филиала» column: students with no branch at all
  // (neither the branch_id FK nor a legacy custom_data branch key).
  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  noBranch?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  limit?: number;
}
