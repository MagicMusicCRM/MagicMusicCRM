import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from "class-validator";

export class UpdateBranchDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  address?: string;

  // UTC offset in minutes. Russia spans UTC+2..UTC+12 and observes no DST, so a
  // fixed per-branch offset is sufficient. Bounded to a sane global range.
  @IsOptional()
  @IsInt()
  @Min(-720)
  @Max(840)
  utcOffsetMinutes?: number;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  timezone?: string;
}
