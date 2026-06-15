import { IsBoolean } from "class-validator";

export class SetChatMuteDto {
  @IsBoolean()
  isMuted!: boolean;
}
