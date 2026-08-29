import { Transform, Type } from "class-transformer";
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from "class-validator";

export const CLIENT_REF_TYPES = ["lead", "student"] as const;
export type ClientRefType = (typeof CLIENT_REF_TYPES)[number];

/**
 * Stable cross-domain reference to a CRM client. The discriminator is
 * mandatory: Lead and Student UUID spaces must never be guessed or merged.
 */
export class ClientRefDto {
  @IsIn(CLIENT_REF_TYPES)
  type!: ClientRefType;

  @IsUUID()
  id!: string;
}

export class ClientRefSearchQuery {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  q?: string;

  @IsOptional()
  @IsIn(CLIENT_REF_TYPES)
  type?: ClientRefType;

  @IsOptional()
  @IsUUID()
  branchId?: string;

  @IsOptional()
  @Transform(({ value }) => value === true || value === "true")
  @IsBoolean()
  includeArchived?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;
}
