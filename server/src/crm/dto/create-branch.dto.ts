import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";
import { BranchWeeklyHoursDto } from "../schedule/availability.dto";

export class CreateBranchDto {
  @IsString()
  @MaxLength(200)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  address?: string;

  // UTC offset in minutes. Russia spans UTC+2..UTC+12 and observes no DST, so a
  // fixed per-branch offset is sufficient. Bounded to a sane global range.
  // Defaults to 180 (UTC+3, Moscow) when omitted.
  @IsOptional()
  @IsInt()
  @Min(-720)
  @Max(840)
  utcOffsetMinutes?: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  timezone?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(7)
  @ValidateNested({ each: true })
  @Type(() => BranchWeeklyHoursDto)
  weeklyHours!: BranchWeeklyHoursDto[];
}
