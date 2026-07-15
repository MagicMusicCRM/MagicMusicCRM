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
import { DuplicatesService } from "./duplicates.service";
import { MergeService } from "./merge.service";
import { PhoneReviewService } from "./phone-review.service";
import { LeadsService } from "./leads.service";
import { CrmListQuery } from "./dto/crm-list.query";
import { DuplicateCandidatesQuery } from "./dto/duplicate-candidates.query";
import { DuplicateDecisionDto } from "./dto/duplicate-decision.dto";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { UpsertLeadDto } from "./dto/upsert-lead.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmLeadsController {
  constructor(
    private readonly duplicates: DuplicatesService,
    private readonly leads: LeadsService,
    private readonly merge: MergeService,
    private readonly phoneReview: PhoneReviewService,
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
    @Query("limit") limit?: string,
  ) {
    return this.phoneReview.listPhoneReviewQueue(actor, limit ? Number(limit) : undefined);
  }

  @Get("merge-candidates")
  listMergeCandidates(
    @CurrentActor() actor: ActorContext,
    @Query("limit") limit?: string,
  ) {
    return this.merge.listMergeCandidates(actor, limit ? Number(limit) : undefined);
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
