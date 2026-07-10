import { Type } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
} from 'class-validator';

// KVA-235: ручная операция личного счёта. amount всегда положительный в DTO;
// знак определяет сервис по kind (refund -> расход).
export class CreateAdjustmentDto {
  @IsIn(['refund', 'adjustment'])
  kind: 'refund' | 'adjustment';

  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  amount: number;

  // Для 'adjustment': направление операции (по умолчанию приход).
  @IsOptional()
  @IsIn(['income', 'outcome'])
  direction?: 'income' | 'outcome';

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  method?: string;

  @IsOptional()
  @IsDateString()
  occurredAt?: string;
}
