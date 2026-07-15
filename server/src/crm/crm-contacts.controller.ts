import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { ClientLinkingService } from "./client-linking.service";
import { FamilyService } from "./family.service";
import { LeadIntakeService } from "./lead-intake.service";
import { SaveContactFromChatDto } from "./dto/save-contact-from-chat.dto";
import { CreateFamilyDto } from "./dto/create-family.dto";
import { AddFamilyMemberDto } from "./dto/add-family-member.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmContactsController {
  constructor(
    private readonly clientLinking: ClientLinkingService,
    private readonly family: FamilyService,
    private readonly leadIntake: LeadIntakeService,
  ) {}

  @Get("leads/app-count")
  countAppLeads(@CurrentActor() actor: ActorContext) {
    return this.leadIntake.countAppLeads(actor);
  }

  @Get("leads/:id/chat-user")
  resolveLeadChatUser(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.leadIntake.resolveLeadChatUser(actor, id);
  }

  @Get("contacts/by-user/:userId")
  resolveContactForUser(
    @CurrentActor() actor: ActorContext,
    @Param("userId", ParseUUIDPipe) userId: string,
  ) {
    return this.leadIntake.resolveContactForUser(actor, userId);
  }

  @Post("contacts/save-from-chat")
  saveContactFromChat(
    @CurrentActor() actor: ActorContext,
    @Body() dto: SaveContactFromChatDto,
  ) {
    return this.leadIntake.saveContactFromChat(actor, dto);
  }

  @Post("families")
  createFamily(@CurrentActor() actor: ActorContext, @Body() dto: CreateFamilyDto) {
    return this.family.createFamily(actor, dto);
  }

  @Post("families/:familyId/members")
  addFamilyMember(
    @CurrentActor() actor: ActorContext,
    @Param("familyId", ParseUUIDPipe) familyId: string,
    @Body() dto: AddFamilyMemberDto,
  ) {
    return this.family.addFamilyMember(actor, familyId, dto);
  }

  @Get("families/by-entity/:entityType/:entityId")
  getFamilyForEntity(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
  ) {
    return this.family.getFamilyForEntity(actor, entityType, entityId);
  }

  @Delete("family-members/:memberId")
  removeFamilyMember(
    @CurrentActor() actor: ActorContext,
    @Param("memberId", ParseUUIDPipe) memberId: string,
  ) {
    return this.family.removeFamilyMember(actor, memberId);
  }

  @Post("families/:familyId/primary-payer/:memberId")
  setPrimaryPayer(
    @CurrentActor() actor: ActorContext,
    @Param("familyId", ParseUUIDPipe) familyId: string,
    @Param("memberId", ParseUUIDPipe) memberId: string,
  ) {
    return this.family.setPrimaryPayer(actor, familyId, memberId);
  }

  @Get("clients/:entityType/:entityId/linked-users")
  getClientLinkedUsers(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
  ) {
    return this.clientLinking.getClientLinkedUsers(actor, entityType, entityId);
  }

  @Get("clients/:entityType/:entityId/user-candidates")
  listClientUserCandidates(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
  ) {
    return this.clientLinking.listClientUserCandidates(actor, entityType, entityId);
  }

  @Post("clients/:entityType/:entityId/link-user")
  linkUserToClient(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
    @Body() dto: { userId: string },
  ) {
    return this.clientLinking.linkUserToClient(actor, entityType, entityId, dto.userId);
  }
}
