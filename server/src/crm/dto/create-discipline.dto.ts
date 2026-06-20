import { IsString, MaxLength } from "class-validator";

export class CreateDisciplineDto {
  @IsString()
  @MaxLength(120)
  name!: string;
}
