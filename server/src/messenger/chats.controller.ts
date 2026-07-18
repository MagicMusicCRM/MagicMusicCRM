import {
  Body,
  Controller,
  Param,
  ParseUUIDPipe,
  Patch,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { ArchiveChatDto } from "./dto/archive-chat.dto";
import { ChatInboxService } from "./chat-inbox.service";

/**
 * Contract 3 (правки №2): PATCH /api/chats/:chatId/archive {archived:boolean}.
 * Thin alias over ChatInboxService — the legacy
 * POST /api/messenger/chats/:chatId/archive|unarchive pair stays as a
 * compatibility surface for older clients.
 */
@UseGuards(JwtAuthGuard)
@Controller("chats")
export class ChatsController {
  constructor(private readonly inbox: ChatInboxService) {}

  @Patch(":chatId/archive")
  async setArchived(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
    @Body() dto: ArchiveChatDto,
  ) {
    if (dto.archived) {
      await this.inbox.archiveChat(actor, chatId);
    } else {
      await this.inbox.unarchiveChat(actor, chatId);
    }
    return { ok: true };
  }
}
