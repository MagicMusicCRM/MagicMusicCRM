import { IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export class CreateChannelPostDto {
  @IsString()
  @MaxLength(5000)
  content: string;

  @IsOptional()
  @IsUUID()
  attachmentFileId?: string;
}
