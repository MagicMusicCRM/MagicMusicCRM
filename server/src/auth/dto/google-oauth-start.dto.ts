import { IsOptional, IsString, MaxLength } from 'class-validator';

export class GoogleOAuthStartDto {
  @IsOptional()
  @IsString()
  @MaxLength(512)
  redirectUri?: string;
}
