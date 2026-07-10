import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateIf
} from 'class-validator';
import { UserRole } from '../../common/security/actor-context';
import { NotificationChannel } from '../notifications.types';

export class AdminSendNotificationDto {
  @IsIn(['users', 'role', 'all'])
  target: 'users' | 'role' | 'all';

  @ValidateIf((dto: AdminSendNotificationDto) => dto.target === 'users')
  @IsArray()
  @ArrayNotEmpty()
  @ArrayMaxSize(200)
  @IsUUID('4', { each: true })
  userIds?: string[];

  @ValidateIf((dto: AdminSendNotificationDto) => dto.target === 'role')
  @IsIn(['client', 'teacher', 'manager', 'admin', 'director', 'system_admin'])
  role?: UserRole;

  @IsString()
  @MaxLength(80)
  title: string;

  @IsString()
  @MaxLength(1000)
  body: string;

  @IsOptional()
  @IsObject()
  data?: Record<string, unknown>;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(3)
  @IsIn(['in_app', 'email', 'push'], { each: true })
  channels?: NotificationChannel[];
}
