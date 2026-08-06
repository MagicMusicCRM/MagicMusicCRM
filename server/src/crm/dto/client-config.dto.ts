import { Transform, Type } from "class-transformer";
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsDefined,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";

export const CLIENT_ENTITY_TYPES = ["lead", "student"] as const;
export type ClientEntityType = (typeof CLIENT_ENTITY_TYPES)[number];

export const CLIENT_CUSTOM_VALUE_TYPES = [
  "text",
  "textarea",
  "number",
  "money",
  "duration",
  "boolean",
  "toggle",
  "date",
  "datetime",
  "select",
  "radio",
  "multi_select",
  "checkbox_group",
  "email",
  "phone",
  "url",
] as const;
export type ClientCustomValueType = (typeof CLIENT_CUSTOM_VALUE_TYPES)[number];

export class ClientConfigListQuery {
  @IsOptional()
  @IsIn(CLIENT_ENTITY_TYPES)
  entityType?: ClientEntityType;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  includeArchived?: boolean;
}

export class ExpectedVersionQuery {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  expectedVersion!: number;
}

export class CreateLeadSourceDto {
  @IsString()
  @Matches(/^[a-z][a-z0-9_-]{0,63}$/)
  canonicalName!: string;

  @IsString()
  @MaxLength(120)
  displayName!: string;
}

export class UpdateLeadSourceDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsOptional()
  @IsString()
  @Matches(/^[a-z][a-z0-9_-]{0,63}$/)
  canonicalName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  displayName?: string;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

export class CreateClientCustomFieldDto {
  @IsIn(CLIENT_ENTITY_TYPES)
  entityType!: ClientEntityType;

  @IsString()
  @Matches(/^[A-Za-z][A-Za-z0-9_]{0,63}$/)
  key!: string;

  @IsString()
  @MaxLength(120)
  label!: string;

  @IsIn(CLIENT_CUSTOM_VALUE_TYPES)
  valueType!: ClientCustomValueType;

  @IsOptional()
  @IsBoolean()
  required?: boolean;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  @MaxLength(160, { each: true })
  options?: string[];
}

export class UpdateClientCustomFieldDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  label?: string;

  @IsOptional()
  @IsIn(CLIENT_CUSTOM_VALUE_TYPES)
  valueType?: ClientCustomValueType;

  @IsOptional()
  @IsBoolean()
  required?: boolean;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  @MaxLength(160, { each: true })
  options?: string[];
}

export class ClientCustomFieldInputDto {
  @IsUUID()
  definitionId!: string;

  @IsDefined()
  value!: unknown;
}

export class StrictCreateLeadDto {
  @IsString()
  @MaxLength(80)
  firstName!: string;

  @IsString()
  @MaxLength(120)
  lastName!: string;

  @IsString()
  @MaxLength(40)
  phone!: string;

  @IsUUID()
  sourceId!: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  status?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => ClientCustomFieldInputDto)
  customFields?: ClientCustomFieldInputDto[];
}

export class StrictCreateStudentDto {
  @IsString()
  @MaxLength(100)
  firstName!: string;

  @IsString()
  @MaxLength(120)
  lastName!: string;

  @IsString()
  @MaxLength(50)
  phone!: string;

  @IsUUID()
  branchId!: string;

  @IsString()
  @MaxLength(50)
  status!: string;

  @IsOptional()
  @IsUUID()
  sourceId?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => ClientCustomFieldInputDto)
  customFields?: ClientCustomFieldInputDto[];
}
