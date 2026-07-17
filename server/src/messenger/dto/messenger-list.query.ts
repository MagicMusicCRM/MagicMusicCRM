import { Type } from 'class-transformer';
import {
  IsDateString,
  IsInt,
  IsOptional,
  IsUUID,
  Max,
  Min,
} from 'class-validator';

export class MessengerListQuery {
  @IsOptional()
  @IsDateString()
  before?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  // Filter to chats whose client belongs to this branch. A client with no
  // branch assigned yet is shown under EVERY branch filter (owner rule:
  // «если филиал не назначен — показывается для всех»).
  @IsOptional()
  @IsUUID()
  branchId?: string;
}
