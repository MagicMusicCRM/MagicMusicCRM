import {
  IsEmail,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from "class-validator";
import { MIN_PASSWORD_LENGTH } from "../../auth/password-policy";

export class ProvisionPersonAccessDto {
  @IsOptional()
  @IsEmail()
  @MaxLength(255)
  email?: string;

  @IsOptional()
  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(128)
  password?: string;
}
