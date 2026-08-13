import { Type } from "class-transformer";
import {
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsDateString,
  IsEmail,
  IsIn,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
} from "class-validator";
import { MIN_PASSWORD_LENGTH } from "../../auth/password-policy";

export class CreateTeacherDto {
  @IsString()
  @MaxLength(100)
  firstName!: string;

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
  @MinLength(MIN_PASSWORD_LENGTH)
  @MaxLength(128)
  password?: string;

  @IsOptional()
  @IsIn(["teacher", "admin", "manager", "director"])
  accessRole?: "teacher" | "admin" | "manager" | "director";

  @IsOptional()
  @IsString()
  @MaxLength(50)
  status?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayUnique()
  @IsUUID("all", { each: true })
  branchIds!: string[];

  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsUUID("all", { each: true })
  disciplineIds?: string[];

  @IsOptional()
  @IsObject()
  customDataPatch?: Record<string, unknown>;

  /** Fixed monthly salary metadata. It is not a lesson accrual rule. */
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  salary?: number;

  /** Base rate per astronomical hour. Zero means that lessons enter salary. */
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(1000000)
  rate?: number;

  @IsOptional()
  @IsDateString()
  rateEffectiveFrom?: string;
}
