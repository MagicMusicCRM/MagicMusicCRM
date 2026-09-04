import { Type } from "class-transformer";
import {
  Equals,
  IsDateString,
  IsInt,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  MinLength,
} from "class-validator";

export class SchedulePlanRowRemovalPreviewDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsOptional()
  @IsDateString()
  effectiveFrom?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reasonText!: string;
}

export class SchedulePlanRowRemovalCommandDto extends SchedulePlanRowRemovalPreviewDto {
  @IsString()
  @MaxLength(16_384)
  previewToken!: string;

  @Equals(true)
  confirm!: true;
}
