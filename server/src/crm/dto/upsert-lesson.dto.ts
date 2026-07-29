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
import { ClientRefDto } from "./client-ref.dto";

/**
 * Contract 7 (правки №2): the pinned attendee reference shape. A lesson's
 * subject may be a STUDENT or a LEAD (leads attend trial lessons). Mapped
 * server-side onto studentId/leadId — both legacy fields stay accepted.
 */
export { ClientRefDto as LessonClientRefDto } from "./client-ref.dto";

export class UpsertLessonDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  expectedVersion?: number;

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
  // Compatibility-only create value. Terminal lifecycle changes are performed
  // exclusively by the server worker or explicit cancel/reschedule commands.
  @IsIn(["scheduled"])
  status?: string;

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

  // Legacy compatibility field. The unified v4 command rejects `true`;
  // constraint override is not available through create/edit/drag routes.
  @IsOptional()
  @IsBoolean()
  force?: boolean;

  // Contract 7: pinned attendee shape {type:'lead'|'student', id}. Optional —
  // studentId/leadId keep working for existing callers.
  @IsOptional()
  @ValidateNested()
  @Type(() => ClientRefDto)
  clientRef?: ClientRefDto;

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
