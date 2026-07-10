import { Type } from "class-transformer";
import {
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from "class-validator";

// KVA-238: частичное обновление группы (PATCH), в т.ч. из drill-down отчёта
// «Статистика преподавателей». teacherRate: null — сбросить переопределение
// (использовать ставку педагога), 0 — «входит в оклад». Отличие «поле не
// передано» от «передан null» сервис определяет по dto.teacherRate !== undefined.
export class UpdateGroupDto {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

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
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(1000000)
  pricePerLesson?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(1000000)
  teacherRate?: number | null;
}
