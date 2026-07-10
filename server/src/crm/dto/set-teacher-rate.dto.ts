import { Type } from "class-transformer";
import { IsDateString, IsNumber, IsOptional, Max, Min } from "class-validator";

// KVA-238: новая ставка педагога (₽ за астрономический час) с датой начала
// действия. rate = 0 — «входит в оклад». История сохраняется в
// app.teacher_rates: начисления — проекция, поэтому смена ставки задним
// числом пересчитывает прошлые занятия автоматически.
export class SetTeacherRateDto {
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(1000000)
  rate: number;

  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;
}
