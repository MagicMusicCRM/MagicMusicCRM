import { Type } from "class-transformer";
import {
  IsDateString,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  MaxLength,
  Matches,
} from "class-validator";

/**
 * Move money from one client's personal account to another's.
 *
 * Deliberately NOT exposed as a payment adjustment: a transfer is two
 * rows (transfer_out on the payer, transfer_in on the receiver) and a caller
 * able to post one of them alone could make money appear from nowhere.
 */
export class CreateTransferDto {
  /** Receiving student. The payer comes from the route. */
  @IsUUID()
  toStudentId!: string;

  /** Always positive; the service signs each leg. */
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  amount!: number;

  @IsOptional()
  @Matches(/^[A-Z]{3}$/)
  currencyCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsDateString()
  occurredAt?: string;
}
