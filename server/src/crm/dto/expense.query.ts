import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";
import { Type } from "class-transformer";
import {
  IsISO8601,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export class ExpenseQuery {
  @IsOptional()
  @IsString()
  @MaxLength(512)
  @ApiPropertyOptional({ type: String, maxLength: 512 })
  cursor?: string;

  @IsOptional()
  @IsUUID()
  @ApiPropertyOptional({ type: String, format: "uuid", nullable: true })
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  @ApiPropertyOptional({ type: String, maxLength: 64 })
  category?: string;

  @IsOptional()
  @IsISO8601()
  @ApiPropertyOptional({ type: String, description: "Inclusive ISO 8601 lower bound." })
  from?: string;

  @IsOptional()
  @IsISO8601()
  @ApiPropertyOptional({ type: String, description: "Exclusive ISO 8601 upper bound." })
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(500)
  @ApiPropertyOptional({ type: "integer", minimum: 1, maximum: 500, default: 100 })
  limit?: number;
}

export class ExpenseVersionQuery {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @ApiProperty({ type: "integer", minimum: 1 })
  expectedVersion!: number;
}
