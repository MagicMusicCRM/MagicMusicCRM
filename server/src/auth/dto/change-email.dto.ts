import { IsEmail, IsString, MaxLength, MinLength } from "class-validator";

export class ChangeEmailDto {
  @IsEmail()
  @MaxLength(255)
  email!: string;

  @IsString()
  @MinLength(10)
  @MaxLength(128)
  currentPassword!: string;
}
