import { Transform, Type } from "class-transformer";
import {
  ArrayMinSize,
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
  ValidateNested,
} from "class-validator";

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
