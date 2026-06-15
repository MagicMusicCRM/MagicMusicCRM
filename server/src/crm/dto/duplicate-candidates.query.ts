import { Type } from "class-transformer";
import { IsIn, IsInt, IsOptional, IsUUID, Max, Min } from "class-validator";

export class DuplicateCandidatesQuery {
  @IsOptional()
  @IsIn(["pending", "not_duplicate", "attached", "merged", "ignored"])
  status?: string;

  @IsOptional()
  @IsUUID()
  leadId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
