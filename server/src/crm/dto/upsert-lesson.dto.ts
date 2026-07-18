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
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";

/**
 * Contract 7 (правки №2): the pinned attendee reference shape. A lesson's
 * subject may be a STUDENT or a LEAD (leads attend trial lessons). Mapped
 * server-side onto studentId/leadId — both legacy fields stay accepted.
 */
export class LessonClientRefDto {
  @IsIn(["lead", "student"])
  type!: "lead" | "student";

  @IsUUID()
  id!: string;
}

export class UpsertLessonDto {
  @IsOptional()
  @IsUUID()
  studentId?: string;

  @IsOptional()
  @IsUUID()
  groupId?: string;

  @IsOptional()
  @IsUUID()
  leadId?: string;

  @IsOptional()
  @IsUUID()
  teacherId?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsUUID()
  roomId?: string;

  @IsOptional()
  @IsDateString()
  scheduledAt?: string;

  @IsOptional()
  @IsInt()
  @Min(15)
  @Max(360)
  durationMinutes?: number;

  @IsOptional()
  @IsIn(["scheduled", "completed", "cancelled", "missed"])
  status?: string;

  @IsOptional()
  @IsBoolean()
  isTrial?: boolean;

  // Contract 2: admin+ override — create/move the lesson even though the
  // teacher or the room is busy at that time (the 409 pre-flight showed why).
  @IsOptional()
  @IsBoolean()
  force?: boolean;

  // Contract 7: pinned attendee shape {type:'lead'|'student', id}. Optional —
  // studentId/leadId keep working for existing callers.
  @IsOptional()
  @ValidateNested()
  @Type(() => LessonClientRefDto)
  clientRef?: LessonClientRefDto;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;

  // Поурочная ставка педагога за это занятие (₽/час). Приоритетнее групповой и
  // историчной ставки при расчёте зарплаты.
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100000)
  teacherRate?: number;
}
