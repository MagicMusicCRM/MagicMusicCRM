import { Injectable, NotFoundException } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { MessengerPolicy } from "./messenger.policy";

export type MessengerChatAccess = NonNullable<
  Awaited<ReturnType<MessengerPolicy["getChatAccess"]>>
>;

@Injectable()
export class MessengerChatAccessService {
  constructor(private readonly policy: MessengerPolicy) {}

  async requireChat(actor: ActorContext, chatId: string) {
    const chat = await this.policy.getChatAccess(actor, chatId);
    if (!chat) throw new NotFoundException("Чат не найден.");
    return chat;
  }


}
