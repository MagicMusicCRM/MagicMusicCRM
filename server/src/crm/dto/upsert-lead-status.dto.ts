import { IsInt, IsOptional, IsString, MaxLength, Min } from "class-validator";

export class UpsertLeadStatusDto {
  @IsString()
  @MaxLength(80)
  label!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  key?: string;

  @IsOptional()
  @IsString()
  @MaxLength(16)
  color?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;
}
