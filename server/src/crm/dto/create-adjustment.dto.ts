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

  // «№ Счёта» — колонка личного счёта в HolliHop.
  @IsOptional()
  @IsString()
  @MaxLength(80)
  invoiceNumber?: string;

  // «Статус». По умолчанию 'paid': запись заводят уже свершившейся.
  // 'void' здесь недоступен — отмена идёт через DELETE, чтобы у неё был
  // отдельный автор и время.
  @IsOptional()
  @IsIn(['paid', 'pending'])
  status?: 'paid' | 'pending';
}

/**
 * Правка записи личного счёта. Все поля необязательны — меняют обычно одно.
 * `kind` не меняется: возврат, ставший корректировкой, — это другая операция,
 * её заводят заново.
 */
export class UpdateAdjustmentDto {
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  amount?: number;

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

  @IsOptional()
  @IsString()
  @MaxLength(80)
  invoiceNumber?: string;

  @IsOptional()
  @IsIn(['paid', 'pending'])
  status?: 'paid' | 'pending';
}
