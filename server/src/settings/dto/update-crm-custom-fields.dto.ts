import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  ValidateNested,
} from "class-validator";

export const CRM_CUSTOM_FIELD_ENTITIES = [
  "students",
  "leads",
  "teachers",
] as const;

export const CRM_CUSTOM_FIELD_TYPES = [
  "text",
  "number",
  "date",
  "phone",
  "email",
  "url",
  "select",
  "boolean",
] as const;

export class CrmCustomFieldDefinitionDto {
  @IsIn(CRM_CUSTOM_FIELD_ENTITIES)
  entity: (typeof CRM_CUSTOM_FIELD_ENTITIES)[number];

  @IsString()
  @MaxLength(64)
  @Matches(/^[A-Za-z][A-Za-z0-9_]*$/)
  key: string;

  @IsString()
  @MaxLength(80)
  label: string;

  @IsIn(CRM_CUSTOM_FIELD_TYPES)
  type: (typeof CRM_CUSTOM_FIELD_TYPES)[number];

  @IsOptional()
  @IsBoolean()
  required?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  hint?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(40)
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  options?: string[];
}

export class UpdateCrmCustomFieldsDto {
  @IsArray()
  @ArrayMaxSize(80)
  @ValidateNested({ each: true })
  @Type(() => CrmCustomFieldDefinitionDto)
  fields: CrmCustomFieldDefinitionDto[];
}
