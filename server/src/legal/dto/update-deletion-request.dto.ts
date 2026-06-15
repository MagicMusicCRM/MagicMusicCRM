import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { AccountDeletionStatus } from '../legal.types';

export class UpdateDeletionRequestDto {
  @IsIn(['processing', 'completed', 'rejected', 'cancelled'])
  status: Exclude<AccountDeletionStatus, 'pending'>;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  resolutionNote?: string;
}
