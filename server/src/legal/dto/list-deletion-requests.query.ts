import { IsIn, IsInt, IsOptional, Min } from 'class-validator';
import { Transform } from 'class-transformer';
import { AccountDeletionStatus } from '../legal.types';

export class ListDeletionRequestsQuery {
  @IsOptional()
  @IsIn(['pending', 'processing', 'completed', 'rejected', 'cancelled'])
  status?: AccountDeletionStatus;

  @IsOptional()
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  limit?: number;
}
