import { IsString, Matches, MaxLength, MinLength } from "class-validator";
import { MIN_PASSWORD_LENGTH } from "../password-policy";

export class ResetPasswordDto {
  @IsString()
  @Matches(/^\d{6}$/)
  token: string;

  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(128)
  password: string;
}
