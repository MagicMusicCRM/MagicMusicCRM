import { IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class ResetPasswordDto {
  @IsString()
  @Matches(/^\d{6}$/)
  token: string;

  @IsString()
  @MinLength(10)
  @MaxLength(128)
  password: string;
}
