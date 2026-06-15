import { IsNotEmpty, IsString, MaxLength } from "class-validator";

export class CreateProfileNoteDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(4000)
  body!: string;
}
