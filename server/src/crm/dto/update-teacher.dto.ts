import { Type } from "class-transformer";
import {
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsEmail,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
} from "class-validator";

export class UpdateTeacherDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  lastName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  phone?: string;

  @IsOptional()
  @IsEmail()
  @MaxLength(255)
  email?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  status?: string;

  // KVA-238: патч custom-полей карточки педагога (birthday, workStartDate,
  // level, category, isPartTime, isBlacklisted) — merge, как у учеников
  // (updateStudent.customDataPatch).
  @IsOptional()
  @IsObject()
  customDataPatch?: Record<string, unknown>;

  // KVA-238: оклад (фиксированная часть, ₽/мес). Меняется только ролями с
  // доступом к payroll — проверка в сервисе.
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  salary?: number;

  // KVA-238: мультивыбор дисциплин (m2m app.teacher_disciplines).
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayUnique()
  @IsUUID("all", { each: true })
  disciplineIds?: string[];

  // KVA-238: явная привязка к филиалам (m2m app.teacher_branches).
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayUnique()
  @IsUUID("all", { each: true })
  branchIds?: string[];
}
