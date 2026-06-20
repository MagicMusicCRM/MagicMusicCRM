import { IsOptional, IsString, IsUUID, MaxLength } from "class-validator";

export class CreateFamilyDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  name?: string;

  @IsOptional()
  @IsUUID()
  branchId?: string;
}
