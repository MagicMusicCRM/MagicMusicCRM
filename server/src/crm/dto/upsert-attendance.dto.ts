import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";

// KVA-237: 5 типов посещения по HolliHop. Легаси-клиенты шлют status
// (present/absent) — сервис маппит его в kind; новые шлют kind напрямую.
export const ATTENDANCE_KINDS = [
  "attended",
  "unpaid_miss",
  "free_lesson",
  "paid_miss",
  "partially_paid",
] as const;

class AttendanceItemDto {
  @IsUUID()
  studentId!: string;

  @IsOptional()
  @IsIn(["present", "absent"])
  status?: string;

  @IsOptional()
  @IsIn(ATTENDANCE_KINDS as unknown as string[])
  kind?: string;

  // Доля списания для partially_paid (0..1]; для остальных игнорируется.
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0.001)
  @Max(1)
  chargeShare?: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  passReason?: string;

  /**
   * Charge THIS subscription instead of letting the reconciler pick one.
   * Without it the fallback only reaches the student's own subscription or a
   * family member's, so a friend paying for a friend was impossible.
   */
  @IsOptional()
  @IsUUID()
  subscriptionId?: string;
}

export class UpsertAttendanceDto {
  @IsArray()
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => AttendanceItemDto)
  items!: AttendanceItemDto[];

  // «Уведомить об изменениях» (модалка HolliHop): пуш/in-app клиентам занятия.
  @IsOptional()
  @IsBoolean()
  notifyClient?: boolean;
}
