import {
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateIf,
} from "class-validator";

export class SendMessageDto {
  @IsOptional()
  @IsIn(["text", "file", "image", "voice"])
  messageType?: string;

  @ValidateIf((dto: SendMessageDto) => !dto.attachmentFileId)
  @IsString()
  @MaxLength(5000)
  content?: string;

  @IsOptional()
  @IsUUID()
  attachmentFileId?: string;

  @IsOptional()
  @IsUUID()
  replyToId?: string;

  @IsOptional()
  @IsUUID()
  forwardedFromId?: string;
}
