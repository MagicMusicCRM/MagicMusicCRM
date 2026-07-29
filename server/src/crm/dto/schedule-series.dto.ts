import { Type } from "class-transformer";
import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";
import { ClientRefDto } from "./client-ref.dto";

// v4 atomic series: one typed Lead/Student client plus an immutable Lesson
// template. Legacy scalar refs remain accepted only as input adapters.
export class CreateScheduleSeriesDto {
  @IsOptional()
  @ValidateNested()
  @Type(() => ClientRefDto)
  clientRef?: ClientRefDto;

  @IsOptional()
  @IsUUID()
  studentId?: string;

  @IsOptional()
  @IsUUID()
  leadId?: string;

  @IsOptional()
  @IsUUID()
  groupId?: string;

  @IsOptional()
  @IsUUID()
  teacherId?: string;

  @IsOptional()
  @IsUUID()
  roomId?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  // ISO: 1 = понедельник … 7 = воскресенье.
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(7)
  weekday!: number;

  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/, { message: "beginTime: ожидается HH:mm" })
  beginTime!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(15)
  @Max(480)
  durationMinutes?: number;

  @IsDateString()
  validFrom!: string;

  // null/не задано = «до бесконечности».
  @IsOptional()
  @IsDateString()
  validUntil?: string | null;

  @IsOptional()
  @IsBoolean()
  isTrial?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  completionType?: string;

  @IsOptional()
  @IsIn(["subscription", "personal_account", "none"])
  clientChargeType?: "subscription" | "personal_account" | "none";

  @IsOptional()
  @IsNumber()
  @Min(0)
  clientChargeValue?: number;

  @IsOptional()
  @IsIn(["fixed", "hourly", "none"])
  teacherCompensationType?: "fixed" | "hourly" | "none";

  @IsOptional()
  @IsNumber()
  @Min(0)
  teacherCompensationValue?: number;

  @IsOptional()
  @IsUUID()
  subscriptionId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}

// «Карандаш»: правка применяется «со следующей даты» (effectiveFrom) —
// старая серия закрывается, создаётся продолжение с новыми параметрами.
export class UpdateScheduleSeriesDto {
  @IsOptional()
  @IsUUID()
  teacherId?: string;

  @IsOptional()
  @IsUUID()
  roomId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(7)
  weekday?: number;

  @IsOptional()
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/, { message: "beginTime: ожидается HH:mm" })
  beginTime?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(15)
  @Max(480)
  durationMinutes?: number;

  @IsOptional()
  @IsDateString()
  validUntil?: string | null;

  // С какой даты действует правка; по умолчанию — завтра.
  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}
