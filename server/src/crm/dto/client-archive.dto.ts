import { Type } from "class-transformer";
import {
  Equals,
  IsInt,
  IsString,
  Matches,
  MaxLength,
  Min,
} from "class-validator";
import { ClientRefDto } from "./client-ref.dto";

export class ArchiveClientPreviewDto extends ClientRefDto {}

export class ArchiveClientCommandDto extends ClientRefDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @Equals(true)
  confirm!: true;

  @IsString()
  @MaxLength(120)
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reason!: string;
}

export class ArchiveConvertedLeadDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @Equals(true)
  confirm!: true;

  @IsString()
  @MaxLength(120)
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reason!: string;
}
