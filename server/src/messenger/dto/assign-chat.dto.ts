import { IsOptional, IsUUID } from 'class-validator';

export class AssignChatDto {
  @IsOptional()
  @IsUUID()
  userId?: string;
}
