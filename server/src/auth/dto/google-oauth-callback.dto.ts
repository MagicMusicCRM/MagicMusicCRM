import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class GoogleOAuthCallbackDto {
  @IsString()
  @MinLength(8)
  @MaxLength(4096)
  code: string;

  @IsString()
  @MinLength(32)
  @MaxLength(256)
  state: string;

  @IsOptional()
  @IsString()
  @MaxLength(512)
  redirectUri?: string;
}
