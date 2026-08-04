import { Type } from "class-transformer";
import {
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
} from "class-validator";

export class CrmConfigurationQuery {
  @IsOptional()
  @IsUUID()
  branchId?: string;
}

export class SaveCrmConfigurationDraftDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  baseVersion!: number;

  @IsObject()
  snapshot!: Record<string, unknown>;
}

export class PublishCrmConfigurationDto extends SaveCrmConfigurationDraftDto {
  @IsString()
  @MaxLength(500)
  reason!: string;
}

export class RollbackCrmConfigurationDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  expectedVersion!: number;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  targetVersion!: number;

  @IsString()
  @MaxLength(500)
  reason!: string;
}
