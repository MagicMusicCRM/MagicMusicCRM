import {
  IsEmail,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from "class-validator";
import { MIN_PASSWORD_LENGTH } from "../password-policy";

export class SignupDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(128)
  password: string;

  @IsString()
  @MinLength(2)
  @MaxLength(160)
  fullName: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  phone?: string;
}
