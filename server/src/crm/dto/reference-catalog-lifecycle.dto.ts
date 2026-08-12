import { Transform, Type } from "class-transformer";
import {
  Equals,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
} from "class-validator";

export class ReferenceCatalogListQuery {
  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  includeArchived?: boolean;
}

export class ReferenceCatalogLifecycleCommandDto {
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
}

export class RenameReferenceCatalogItemDto extends ReferenceCatalogLifecycleCommandDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name!: string;
}
