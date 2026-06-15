import { IsIn, IsOptional, IsUUID } from 'class-validator';

export class CreateDirectChatDto {
  @IsIn(['administration', 'direct'])
  type: 'administration' | 'direct';

  @IsOptional()
  @IsUUID()
  targetUserId?: string;
}
