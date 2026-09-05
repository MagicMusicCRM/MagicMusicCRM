import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import {
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  IsInt,
  IsDateString,
} from "class-validator";

export class UpdateExpenseDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @ApiProperty({ type: "integer", minimum: 1 })
  expectedVersion?: number;

  @IsOptional()
  @IsDateString()
  @ApiPropertyOptional({ type: String, description: "ISO 8601 date; defaults to server time on create." })
  occurredAt?: string;
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  @ApiPropertyOptional({ type: Number, minimum: 0.01, maximum: 9999999999.99, description: "Rubles, at most two decimal places." })
  amount?: number;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  @ApiPropertyOptional({ type: String, maxLength: 64 })
  category?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  @ApiPropertyOptional({ type: String, maxLength: 1000, nullable: true })
  description?: string;

  @IsOptional()
  @IsUUID()
  @ApiPropertyOptional({ type: String, format: "uuid", nullable: true })
  branchId?: string;
}
