import { Type } from "class-transformer";
import {
  IsDateString,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  MaxLength,
  Min,
} from "class-validator";

class TeacherPayrollHistoryMutationDto {
  @Type(() => Number)
  @IsInt()
  @Min(0)
  expectedVersion: number;

  @IsString()
  @MaxLength(500)
  reasonText: string;
}

export class UpdateTeacherRateEntryDto extends TeacherPayrollHistoryMutationDto {
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(1000000)
  rate: number;

  @IsDateString()
  effectiveFrom: string;
}

export class UpdateTeacherPayoutEntryDto extends TeacherPayrollHistoryMutationDto {
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

  @IsDateString()
  paidAt: string;
}

export class DeleteTeacherPayrollEntryDto extends TeacherPayrollHistoryMutationDto {}
