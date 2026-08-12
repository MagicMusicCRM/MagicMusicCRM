import { Type } from "class-transformer";
import {
  IsDateString,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Min,
  MaxLength,
} from "class-validator";

// KVA-238: выплата преподавателю. amount всегда положительный; смысл задаёт
// kind: payout — выплата задолженности, bonus — доплата, deduction — вычет.
export class CreateTeacherPayoutDto {
  @Type(() => Number)
  @IsInt()
  @Min(0)
  expectedVersion: number;

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

  @IsString()
  @MaxLength(500)
  reasonText: string;

  @IsOptional()
  @IsDateString()
  paidAt?: string;
}
