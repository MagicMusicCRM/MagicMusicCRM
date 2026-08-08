import {
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from "class-validator";

export class ProvisionPersonAccessDto {
  @IsEmail()
  @MaxLength(255)
  email!: string;

  @IsString()
  @MinLength(10)
  @MaxLength(128)
  password!: string;

  @IsOptional()
  @IsIn(["teacher", "admin", "manager", "director", "system_admin"])
  role?: "teacher" | "admin" | "manager" | "director" | "system_admin";
}
