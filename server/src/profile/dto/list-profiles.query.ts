import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { UserRole } from '../../common/security/actor-context';

export class ListProfilesQuery {
  @IsOptional()
  @IsIn(['client', 'teacher', 'manager', 'admin', 'system_admin'])
  role?: UserRole;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  q?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
