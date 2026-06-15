import { IsIn, IsUUID } from 'class-validator';

export class LinkProfileCrmDto {
  @IsIn(['student', 'lead', 'teacher', 'staff'])
  entityType: 'student' | 'lead' | 'teacher' | 'staff';

  @IsUUID()
  entityId: string;
}
