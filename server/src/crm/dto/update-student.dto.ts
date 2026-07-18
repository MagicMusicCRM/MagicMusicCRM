import {
  IsBoolean,
  IsEmail,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
} from "class-validator";

export class UpdateStudentDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  lastName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  phone?: string;

  @IsOptional()
  @IsEmail()
  @MaxLength(255)
  email?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  status?: string;

  @IsOptional()
  @IsObject()
  customDataPatch?: Record<string, unknown>;

  // Students retain their legacy custom_data ownership surface. Clearing must
  // be explicit because customDataPatch is a merge-patch for compatibility.
  @IsOptional()
  @IsBoolean()
  clearResponsible?: boolean;
}
