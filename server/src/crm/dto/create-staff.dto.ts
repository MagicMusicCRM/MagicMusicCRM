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
  @MinLength(10)
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
