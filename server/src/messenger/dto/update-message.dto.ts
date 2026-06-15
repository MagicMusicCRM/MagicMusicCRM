import { IsString, MaxLength } from "class-validator";

export class UpdateMessageDto {
  @IsString()
  @MaxLength(5000)
  content: string;
}
