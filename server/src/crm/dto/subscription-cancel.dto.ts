import { Type } from "class-transformer";
import {
  Equals,
  IsBoolean,
  IsInt,
  IsString,
  Matches,
  MaxLength,
  Min,
} from "class-validator";

export class SubscriptionCancelPreviewDto {}

export class SubscriptionCancelCommandDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion: number;

  @IsString()
  @MaxLength(16_384)
  previewToken: string;

  @IsBoolean()
  @Equals(true)
  confirm: true;

  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reason: string;
}
