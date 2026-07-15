import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { AssignChatDto } from "./dto/assign-chat.dto";
import { UpsertChannelDto } from "./dto/channel.dto";
import { CreateChannelPostDto } from "./dto/create-channel-post.dto";
import { CreateDirectChatDto } from "./dto/create-direct-chat.dto";
import { CreateGroupChatDto } from "./dto/create-group-chat.dto";
import { DeleteMessageDto } from "./dto/delete-message.dto";
import { MarkReadDto } from "./dto/mark-read.dto";
import { MessengerListQuery } from "./dto/messenger-list.query";
import { SetChatMuteDto } from "./dto/set-chat-mute.dto";
import { SendMessageDto } from "./dto/send-message.dto";
import { UpdateGroupMembersDto } from "./dto/update-group-members.dto";
import { UpdateMessageDto } from "./dto/update-message.dto";
import { ChannelsService } from "./channels.service";
import { ChatInboxService } from "./chat-inbox.service";
import { MessageService } from "./message.service";
import { MessengerService } from "./messenger.service";

@UseGuards(JwtAuthGuard)
@Controller("messenger")
export class MessengerController {
  constructor(
    private readonly messenger: MessengerService,
    private readonly channels: ChannelsService,
    private readonly inbox: ChatInboxService,
    private readonly messages: MessageService,
  ) {}

  @Get("chats")
  listChats(
    @CurrentActor() actor: ActorContext,
    @Query() query: MessengerListQuery,
  ) {
    return this.messenger.listChats(actor, query);
  }

  @Get("chats/:chatId")
  getChat(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
  ) {
    return this.messenger.getChat(actor, chatId);
  }

  @Get("chats/:chatId/messages")
  getMessages(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
    @Query() query: MessengerListQuery,
  ) {
    return this.messenger.getMessages(actor, chatId, query);
  }

  @Get("chats/:chatId/members")
  listChatMembers(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
  ) {
    return this.messenger.listChatMembers(actor, chatId);
  }

  @Post("chats/:chatId/messages")
  sendMessage(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
    @Body() dto: SendMessageDto,
  ) {
    return this.messenger.sendMessage(actor, chatId, dto);
  }

  @Post("chats/direct")
  createDirectChat(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateDirectChatDto,
  ) {
    return this.messenger.createDirectChat(actor, dto);
  }

  @Post("groups")
  createGroup(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateGroupChatDto,
  ) {
    return this.messenger.createGroup(actor, dto);
  }

  @Patch("groups/:id/members")
  updateGroupMembers(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateGroupMembersDto,
  ) {
    return this.messenger.updateGroupMembers(actor, id, dto);
  }

  @Post("groups/:id/leave")
  leaveGroup(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.messenger.leaveGroup(actor, id);
  }

  @Post("chats/:chatId/read")
  markRead(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
    @Body() dto: MarkReadDto,
  ) {
    return this.messenger.markRead(actor, chatId, dto);
  }

  @Post("chats/:chatId/assign")
  assignChat(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
    @Body() dto: AssignChatDto,
  ) {
    return this.inbox.assignChat(actor, chatId, dto.userId);
  }

  @Post("chats/:chatId/unassign")
  unassignChat(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
  ) {
    return this.inbox.unassignChat(actor, chatId);
  }

  @Post("chats/:chatId/archive")
  archiveChat(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
  ) {
    return this.inbox.archiveChat(actor, chatId);
  }

  @Post("chats/:chatId/unarchive")
  unarchiveChat(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
  ) {
    return this.inbox.unarchiveChat(actor, chatId);
  }

  @Put("chats/:chatId/mute")
  setChatMute(
    @CurrentActor() actor: ActorContext,
    @Param("chatId", ParseUUIDPipe) chatId: string,
    @Body() dto: SetChatMuteDto,
  ) {
    return this.messenger.setChatMute(actor, chatId, dto);
  }

  @Put("messages/:id/reactions/:emoji")
  setReaction(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("emoji") emoji: string,
  ) {
    return this.messages.setReaction(actor, id, emoji);
  }

  @Delete("messages/:id/reactions/:emoji")
  removeReaction(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("emoji") emoji: string,
  ) {
    return this.messages.removeReaction(actor, id, emoji);
  }

  @Post("messages/:id/pin")
  pinMessage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.messages.pinMessage(actor, id);
  }

  @Delete("messages/:id/pin")
  unpinMessage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.messages.unpinMessage(actor, id);
  }

  @Delete("messages/:id")
  deleteMessage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: DeleteMessageDto,
  ) {
    return this.messages.deleteMessage(actor, id, dto);
  }

  @Patch("messages/:id")
  updateMessage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateMessageDto,
  ) {
    return this.messages.updateMessage(actor, id, dto);
  }

  @Get("channels")
  listChannels(@CurrentActor() actor: ActorContext) {
    return this.channels.listChannels(actor);
  }

  @Post("channels")
  createChannel(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertChannelDto,
  ) {
    return this.channels.createChannel(actor, dto);
  }

  @Patch("channels/:id")
  updateChannel(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertChannelDto,
  ) {
    return this.channels.updateChannel(actor, id, dto);
  }

  @Get("channels/:id/access")
  getChannelAccess(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.channels.getChannelAccess(actor, id);
  }

  @Get("channels/:id/permissions")
  listChannelPermissions(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.channels.listChannelPermissions(actor, id);
  }

  @Get("channels/:id/posts")
  listChannelPosts(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: MessengerListQuery,
  ) {
    return this.channels.listChannelPosts(actor, id, query);
  }

  @Post("channels/:id/posts")
  createChannelPost(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CreateChannelPostDto,
  ) {
    return this.channels.createChannelPost(actor, id, dto);
  }
}
