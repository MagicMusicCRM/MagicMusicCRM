import { ArrayNotEmpty, IsArray, IsUUID } from "class-validator";

export class ReorderBranchDisciplinesDto {
  @IsArray()
  @ArrayNotEmpty()
  @IsUUID("all", { each: true })
  disciplineIds!: string[];
}
