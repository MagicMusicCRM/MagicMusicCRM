import { IsIn, IsOptional, IsString, MaxLength } from "class-validator";

export class DuplicateDecisionDto {
  @IsIn(["not_duplicate", "attached", "merged", "ignored"])
  status!: "not_duplicate" | "attached" | "merged" | "ignored";

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string;
}
