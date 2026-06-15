import { IsOptional, IsUUID } from 'class-validator';

export class MarkReadDto {
  @IsOptional()
  @IsUUID()
  lastReadMessageId?: string;
}
