import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class SignupDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(10)
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
