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
import { BlacklistService } from "./blacklist.service";
import { DuplicatesService } from "./duplicates.service";
import { MergeService } from "./merge.service";
import { PhoneReviewService } from "./phone-review.service";
import { LeadsService } from "./leads.service";
import { SubscriptionsService } from "./subscriptions.service";
import { CrmListQuery } from "./dto/crm-list.query";
import { DuplicateCandidatesQuery } from "./dto/duplicate-candidates.query";
import { DuplicateDecisionDto } from "./dto/duplicate-decision.dto";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { QueueLimitQuery } from "./dto/queue-limit.query";
import { LinkStudentDto } from "./dto/link-student.dto";
import { IssueSubscriptionDto } from "./dto/issue-subscription.dto";
import { SetBlacklistDto } from "./dto/set-blacklist.dto";
import { UpsertLeadDto } from "./dto/upsert-lead.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmLeadsController {
  constructor(
    private readonly blacklist: BlacklistService,
    private readonly duplicates: DuplicatesService,
    private readonly leads: LeadsService,
    private readonly merge: MergeService,
    private readonly phoneReview: PhoneReviewService,
    private readonly subscriptions: SubscriptionsService,
  ) {}

  @Get("duplicates")
  listDuplicateCandidates(
    @CurrentActor() actor: ActorContext,
    @Query() query: DuplicateCandidatesQuery,
  ) {
    return this.duplicates.listDuplicateCandidates(actor, query);
  }

  @Patch("duplicates/:id")
  decideDuplicateCandidate(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: DuplicateDecisionDto,
  ) {
    return this.duplicates.decideDuplicateCandidate(actor, id, dto);
  }

  @Get("leads")
  listLeads(@CurrentActor() actor: ActorContext, @Query() query: CrmListQuery) {
    return this.leads.listLeads(actor, query);
  }

  @Get("leads/board")
  listLeadBoard(
    @CurrentActor() actor: ActorContext,
    @Query() query: LeadBoardQuery,
  ) {
    return this.leads.listLeadBoard(actor, query);
  }

  @Get("leads/:id/card")
  getLeadCard(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.leads.getLeadCard(actor, id);
  }

  @Get("leads/:id/applications")
  listLeadApplications(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.leads.listLeadApplications(actor, id);
  }

  @Get("leads/:leadId/status-history")
  listLeadStatusHistory(
    @CurrentActor() actor: ActorContext,
    @Param("leadId", ParseUUIDPipe) leadId: string,
  ) {
    return this.leads.listLeadStatusHistory(actor, leadId);
  }

  @Post("leads")
  createLead(@CurrentActor() actor: ActorContext, @Body() dto: UpsertLeadDto) {
    return this.leads.createLead(actor, dto);
  }

  @Post("leads/:leadId/subscriptions/issue")
  issueLeadSubscription(
    @CurrentActor() actor: ActorContext,
    @Param("leadId", ParseUUIDPipe) leadId: string,
    @Body() dto: IssueSubscriptionDto,
  ) {
    return this.subscriptions.issueLeadSubscription(actor, leadId, dto);
  }

  // Ручное «Прикрепить к ученику»: до этого связать можно было только пару,
  // которую нашёл автоподбор дублей.
  @Post("leads/:id/link-student")
  linkStudentToLead(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: LinkStudentDto,
  ) {
    return this.leads.linkStudentToLead(actor, id, dto.studentId);
  }

  // Бан ставится и на лид-половину карточки: клиентский аккаунт цепляется к
  // любой из половин, и бан только на ученике оставил бы лиду открытый чат.
  @Patch("leads/:id/blacklist")
  setLeadBlacklist(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SetBlacklistDto,
  ) {
    return this.blacklist.setLeadBlacklist(actor, id, dto);
  }

  @Patch("leads/:id")
  updateLead(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertLeadDto,
  ) {
    return this.leads.updateLead(actor, id, dto);
  }

  @Delete("leads/:id")
  deleteLead(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.leads.deleteLead(actor, id);
  }

  @Get("phone-review-queue/count")
  countPhoneReviewQueue(@CurrentActor() actor: ActorContext) {
    return this.phoneReview.countPhoneReviewQueue(actor);
  }

  @Get("phone-review-queue")
  listPhoneReviewQueue(
    @CurrentActor() actor: ActorContext,
    @Query() query: QueueLimitQuery,
  ) {
    return this.phoneReview.listPhoneReviewQueue(actor, query.limit);
  }

  @Get("merge-candidates")
  listMergeCandidates(
    @CurrentActor() actor: ActorContext,
    @Query() query: QueueLimitQuery,
  ) {
    return this.merge.listMergeCandidates(actor, query.limit);
  }

  @Post("leads/:winnerId/merge/:loserId")
  mergeLeads(
    @CurrentActor() actor: ActorContext,
    @Param("winnerId", ParseUUIDPipe) winnerId: string,
    @Param("loserId", ParseUUIDPipe) loserId: string,
  ) {
    return this.merge.mergeLeads(actor, loserId, winnerId);
  }

  @Post("merges/:mergeLogId/undo")
  undoMerge(
    @CurrentActor() actor: ActorContext,
    @Param("mergeLogId", ParseUUIDPipe) mergeLogId: string,
  ) {
    return this.merge.undoMerge(actor, mergeLogId);
  }
}
