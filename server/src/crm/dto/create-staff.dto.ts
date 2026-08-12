import {
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsEmail,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from "class-validator";
import { MIN_PASSWORD_LENGTH } from "../../auth/password-policy";

export class CreateStaffDto {
  @IsString()
  @MaxLength(100)
  firstName!: string;

  @IsString()
  @MaxLength(100)
  lastName!: string;

  @IsOptional()
  @IsEmail()
  @MaxLength(255)
  email?: string;

  @IsOptional()
  @IsString()
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(128)
  password?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  phone?: string;

  /**
   * New staff cards always start with the least-privileged staff role.
   * Elevation is intentionally available only through Settings -> Access.
   */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayUnique()
  @IsUUID("all", { each: true })
  branchIds!: string[];
}
