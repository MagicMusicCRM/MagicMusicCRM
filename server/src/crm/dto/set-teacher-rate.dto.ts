import { Type } from "class-transformer";
import {
  IsDateString,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from "class-validator";

// KVA-238: новая ставка педагога (₽ за астрономический час) с датой начала
// действия. rate = 0 — «входит в оклад». История сохраняется в
// app.teacher_rates. Completed lessons with an effective immutable compensation
// fact keep their snapshot; the history is a fallback for lessons not yet fixed.
export class SetTeacherRateDto {
  @Type(() => Number)
  @IsInt()
  @Min(0)
  expectedVersion: number;

  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(1000000)
  rate: number;

  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;

  @IsString()
  @MaxLength(500)
  reasonText: string;
}
