import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsEmail,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";
import { Type } from "class-transformer";
import { ClientCustomFieldInputDto } from "./client-config.dto";

export class UpdateStudentDto {
  // Optional at the HTTP boundary while pre-201 desktop clients remain supported.
  @IsOptional()
  @IsInt()
  @Min(1)
  expectedVersion?: number;

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
  @IsUUID()
  sourceId?: string;

  @IsOptional()
  @IsObject()
  customDataPatch?: Record<string, unknown>;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => ClientCustomFieldInputDto)
  customFields?: ClientCustomFieldInputDto[];

  // Students retain their legacy custom_data ownership surface. Clearing must
  // be explicit because customDataPatch is a merge-patch for compatibility.
  @IsOptional()
  @IsBoolean()
  clearResponsible?: boolean;
}
