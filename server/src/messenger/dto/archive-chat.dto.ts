import { IsBoolean } from "class-validator";

/** Contract 3 (правки №2): PATCH /api/chats/:chatId/archive {archived}. */
export class ArchiveChatDto {
  @IsBoolean()
  archived!: boolean;
}
