import { IsEmail, IsString, MaxLength, MinLength } from "class-validator";
import { MIN_PASSWORD_LENGTH } from "../password-policy";

export class ChangeEmailDto {
  @IsEmail()
  @MaxLength(255)
  email!: string;

  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(128)
  currentPassword!: string;
}
