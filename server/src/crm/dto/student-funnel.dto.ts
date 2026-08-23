import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  Min,
  ValidateNested,
} from "class-validator";

const CLIENT_PIPELINE_TYPES = ["lead", "student"] as const;
export type ClientPipelineType = (typeof CLIENT_PIPELINE_TYPES)[number];

export class ClientPipelineQuery {
  @IsIn(CLIENT_PIPELINE_TYPES)
  clientType: ClientPipelineType;

  @IsOptional()
  @IsUUID()
  branchId?: string;
}

export class ClientPipelineStageDto {
  @IsString()
  @Matches(/^[a-z][a-z0-9_-]{0,63}$/)
  key: string;

  @IsString()
  @MaxLength(80)
  label: string;

  @IsString()
  @Matches(/^(cyan|green|amber|slate|gray|red|#[0-9a-fA-F]{6})$/)
  style: string;

  @IsBoolean()
  active: boolean;

  @IsOptional()
  @IsBoolean()
  terminal?: boolean;

  @IsOptional()
  @IsBoolean()
  requiresReason?: boolean;

  @IsArray()
  @ArrayMaxSize(30)
  @IsString({ each: true })
  allowedTransitions: string[];
}

// Kept as a source-compatible name for student write validation.
export class StudentFunnelStageDto extends ClientPipelineStageDto {}

export class PreviewClientPipelineDto {
  @IsIn(CLIENT_PIPELINE_TYPES)
  clientType: ClientPipelineType;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsInt()
  @Min(0)
  expectedVersion: number;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(30)
  @ValidateNested({ each: true })
  @Type(() => ClientPipelineStageDto)
  stages: ClientPipelineStageDto[];
}

export class PublishClientPipelineDto extends PreviewClientPipelineDto {
  @IsString()
  @MaxLength(500)
  reason: string;
}

export class RollbackClientPipelineDto {
  @IsIn(CLIENT_PIPELINE_TYPES)
  clientType: ClientPipelineType;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsInt()
  @Min(0)
  expectedVersion: number;

  @IsInt()
  @Min(1)
  targetVersion: number;

  @IsString()
  @MaxLength(500)
  reason: string;
}

export class PublishStudentFunnelDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsInt()
  @Min(0)
  expectedVersion: number;

  @IsString()
  @MaxLength(500)
  reason: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(30)
  @ValidateNested({ each: true })
  @Type(() => StudentFunnelStageDto)
  stages: StudentFunnelStageDto[];
}

export class RollbackStudentFunnelDto {
  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsInt()
  @Min(0)
  expectedVersion: number;

  @IsInt()
  @Min(1)
  targetVersion: number;

  @IsString()
  @MaxLength(500)
  reason: string;
}
