import { IsIn, IsUUID } from "class-validator";

export class SaveContactFromChatDto {
  @IsUUID()
  userId!: string;

  @IsIn(["lead", "student"])
  as!: "lead" | "student";
}
