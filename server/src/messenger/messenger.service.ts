import { Injectable, OnModuleInit } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CreateDirectChatDto } from "./dto/create-direct-chat.dto";
import { CreateGroupChatDto } from "./dto/create-group-chat.dto";
import { MessengerListQuery } from "./dto/messenger-list.query";
import { SendMessageDto } from "./dto/send-message.dto";
import { SetChatMuteDto } from "./dto/set-chat-mute.dto";
import { UpdateGroupMembersDto } from "./dto/update-group-members.dto";
import { MessengerChatCommandService } from "./messenger-chat-command.service";
import { MessengerChatQueryService } from "./messenger-chat-query.service";
import { ANNOUNCEMENTS_CHAT_SLUG } from "./messenger.constants";
import { MessengerMessageDeliveryService } from "./messenger-message-delivery.service";
import { MessengerSystemChatService } from "./messenger-system-chat.service";

@Injectable()
export class MessengerService implements OnModuleInit {
  static readonly announcementsSlug = ANNOUNCEMENTS_CHAT_SLUG;

  constructor(
    private readonly systemChats: MessengerSystemChatService,
    private readonly queries: MessengerChatQueryService,
    private readonly delivery: MessengerMessageDeliveryService,
    private readonly commands: MessengerChatCommandService,
  ) {}

  onModuleInit(): Promise<void> {
    return this.systemChats.bootstrapAnnouncements();
  }

  ensureAnnouncementsChat(): Promise<void> {
    return this.systemChats.ensureAnnouncementsChat();
  }

  listChats(actor: ActorContext, query: MessengerListQuery) {
    return this.queries.listChats(actor, query);
  }

  getMessages(actor: ActorContext, chatId: string, query: MessengerListQuery) {
    return this.queries.getMessages(actor, chatId, query);
  }

  listChatMembers(actor: ActorContext, chatId: string) {
    return this.queries.listChatMembers(actor, chatId);
  }

  sendMessage(actor: ActorContext, chatId: string, dto: SendMessageDto) {
    return this.delivery.sendMessage(actor, chatId, dto);
  }

  createDirectChat(actor: ActorContext, dto: CreateDirectChatDto) {
    return this.commands.createDirectChat(actor, dto);
  }

  createGroup(actor: ActorContext, dto: CreateGroupChatDto) {
    return this.commands.createGroup(actor, dto);
  }

  updateGroupMembers(
    actor: ActorContext,
    chatId: string,
    dto: UpdateGroupMembersDto,
  ) {
    return this.commands.updateGroupMembers(actor, chatId, dto);
  }

  leaveGroup(actor: ActorContext, chatId: string) {
    return this.commands.leaveGroup(actor, chatId);
  }

  getChat(actor: ActorContext, chatId: string) {
    return this.queries.getChat(actor, chatId);
  }

  setChatMute(actor: ActorContext, chatId: string, dto: SetChatMuteDto) {
    return this.commands.setChatMute(actor, chatId, dto);
  }
}
