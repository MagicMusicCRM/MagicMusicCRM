import { ArrayMaxSize, ArrayUnique, IsArray, IsString, IsUUID, MaxLength } from 'class-validator';

export class CreateGroupChatDto {
  @IsString()
  @MaxLength(120)
  name: string;

  @IsArray()
  @ArrayMaxSize(100)
  @ArrayUnique()
  @IsUUID('4', { each: true })
  memberUserIds: string[];
}
