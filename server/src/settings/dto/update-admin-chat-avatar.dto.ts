import { IsOptional, IsString, MaxLength } from "class-validator";

export class UpdateAdminChatAvatarDto {
  @IsOptional()
  @IsString()
  @MaxLength(2048)
  url?: string | null;
}
