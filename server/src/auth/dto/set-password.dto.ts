import { IsString, MaxLength, MinLength } from "class-validator";

export class SetPasswordDto {
  @IsString()
  @MinLength(10)
  @MaxLength(128)
  password: string;
}
