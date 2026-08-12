import { Transform, Type } from "class-transformer";
import {
  Equals,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Matches,
  Min,
  MinLength,
} from "class-validator";
import { CrmListQuery } from "./crm-list.query";

export class GroupListQuery extends CrmListQuery {
  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  includeArchived?: boolean;
}

export class GroupLifecycleCommandDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  expectedVersion!: number;

  @Equals(true)
  confirm!: true;

  @IsString()
  @MinLength(3)
  @MaxLength(500)
  reasonText!: string;

  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  effectiveDate!: string;
}
