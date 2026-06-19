import { IsInt, IsOptional, IsUUID, Min } from "class-validator";

export class UpsertBranchDisciplineDto {
  @IsUUID()
  disciplineId!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;
}
