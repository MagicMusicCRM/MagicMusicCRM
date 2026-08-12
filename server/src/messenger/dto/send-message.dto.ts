import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
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
  @IsInt()
  @Min(1)
  @Max(3_600_000)
  voiceDurationMs?: number;

  @IsOptional()
  @IsUUID()
  replyToId?: string;

  @IsOptional()
  @IsUUID()
  forwardedFromId?: string;
}
