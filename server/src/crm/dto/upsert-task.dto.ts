import {
  IsBoolean,
  IsDateString,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class UpsertTaskDto {
  @IsOptional()
  @IsIn(['student', 'teacher', 'group', 'lesson', 'lead', 'profile'])
  entityType?: string;

  @IsOptional()
  @IsUUID()
  entityId?: string;

  @IsOptional()
  @IsUUID()
  assignedTo?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @IsOptional()
  @IsIn(['open', 'in_progress', 'done', 'cancelled'])
  status?: string;

  @IsOptional()
  @IsDateString()
  dueAt?: string;

  @IsOptional()
  @IsIn(['low', 'medium', 'high'])
  priority?: string;

  // true → the due date carries no meaningful time (an «all-day» deadline).
  @IsOptional()
  @IsBoolean()
  dueAllDay?: boolean;
}
