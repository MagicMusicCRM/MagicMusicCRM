import { IsIn } from 'class-validator';
import { UserRole } from '../../common/security/actor-context';

export class UpdateRoleDto {
  @IsIn(['client', 'teacher', 'manager', 'admin', 'director', 'system_admin'])
  role: UserRole;
}
