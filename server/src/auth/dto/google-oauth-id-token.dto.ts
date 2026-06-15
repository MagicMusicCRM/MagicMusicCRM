import { IsString, MaxLength, MinLength } from 'class-validator';

export class GoogleOAuthIdTokenDto {
  @IsString()
  @MinLength(20)
  @MaxLength(8192)
  idToken: string;
}
