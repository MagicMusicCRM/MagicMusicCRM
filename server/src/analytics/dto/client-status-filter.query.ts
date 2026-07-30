import { Type } from "class-transformer";
import {
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export const CLIENT_STATUS_FILTER_VERSION = 1 as const;
export type ClientStatusType = "lead" | "student";

export class ClientStatusFilterQuery {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @IsIn([CLIENT_STATUS_FILTER_VERSION])
  filterVersion: number = CLIENT_STATUS_FILTER_VERSION;

  @IsOptional()
  @IsIn(["lead", "student"])
  clientType?: ClientStatusType;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  status?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  q?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit: number = 50;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset: number = 0;
}

