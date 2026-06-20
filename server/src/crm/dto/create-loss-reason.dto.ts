import { IsIn, IsInt, IsOptional, IsString, MaxLength, Min } from "class-validator";

export class CreateLossReasonDto {
  @IsString()
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsIn(["lost", "paused"])
  kind?: "lost" | "paused";

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;
}
