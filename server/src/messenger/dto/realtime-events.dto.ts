import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class JoinRoomPayload {
  @IsIn(['chat', 'user', 'channel'])
  roomType: 'chat' | 'user' | 'channel';

  @IsString()
  @MaxLength(120)
  roomId: string;
}

export class TypingPayload {
  @IsUUID()
  chatId: string;
}

export class PresencePayload {
  @IsOptional()
  @IsIn(['online', 'away', 'busy'])
  status?: string;
}
