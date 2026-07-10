import { Type } from "class-transformer";
import {
  IsDateString,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
} from "class-validator";

// KVA-236: серия постоянного расписания. student ИЛИ group — проверяется в
// сервисе (как lessons_student_or_group_check).
export class CreateScheduleSeriesDto {
  @IsOptional()
  @IsUUID()
  studentId?: string;

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
  validUntil?: string;

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
  validUntil?: string;

  // С какой даты действует правка; по умолчанию — завтра.
  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}
