import { Type } from "class-transformer";
import {
  IsDateString,
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
} from "class-validator";

// KVA-238: выплата преподавателю. amount всегда положительный; смысл задаёт
// kind: payout — выплата задолженности, bonus — доплата, deduction — вычет.
export class CreateTeacherPayoutDto {
  @IsIn(["payout", "bonus", "deduction"])
  kind: "payout" | "bonus" | "deduction";

  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  amount: number;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  comment?: string;

  @IsOptional()
  @IsDateString()
  paidAt?: string;
}
