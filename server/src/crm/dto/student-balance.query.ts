import { Transform, Type } from "class-transformer";
import { IsBoolean, IsInt, IsOptional, IsUUID, Max, Min } from "class-validator";

export class StudentBalanceQuery {
  @IsOptional()
  @IsUUID()
  studentId?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  debtOnly?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
