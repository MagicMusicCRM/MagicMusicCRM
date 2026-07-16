import { Module } from "@nestjs/common";
import { DatabaseModule } from "../db/database.module";
import { ChatWorkTimelineService } from "./chat-work-timeline.service";

/**
 * Thin messenger-owned module exposing the chat-work timeline read to CRM.
 * Depends only on DatabaseModule, so CrmModule imports it without creating a
 * cycle with the main MessengerModule (which imports CrmModule).
 */
@Module({
  imports: [DatabaseModule],
  providers: [ChatWorkTimelineService],
  exports: [ChatWorkTimelineService],
})
export class ChatWorkTimelineModule {}
