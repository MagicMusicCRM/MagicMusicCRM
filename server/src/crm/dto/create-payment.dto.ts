import { Type } from 'class-transformer';
import { IsDateString, IsNumber, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class CreatePaymentDto {
  @IsUUID()
  studentId: string;

  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  amount: number;

  @IsOptional()
  @IsString()
  @MaxLength(32)
  currency?: string;

  @IsDateString()
  paymentDate: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  method?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  externalId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;

  /**
   * Занятие, за которое пришёл платёж (✔ владелец 17.07: «должна быть привязка
   * платежа к занятию»). Необязательно: пополнение счёта авансом ни к какому
   * занятию не относится, и это норма, а не пропуск.
   */
  @IsOptional()
  @IsUUID()
  lessonId?: string;
}
