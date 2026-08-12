import { IsString, MaxLength, MinLength } from "class-validator";
import { MIN_PASSWORD_LENGTH } from "../password-policy";

export class SetPasswordDto {
  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(128)
  password: string;
}
