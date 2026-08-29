import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import {
  ValidatedCustomFields,
  ValidatedLeadCreate,
} from "./clients/client-write.validator";
import { CrmListQuery } from "./dto/crm-list.query";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { UpdateLeadDto, UpsertLeadDto } from "./dto/upsert-lead.dto";
import { LeadBoardService } from "./lead-board.service";
import { LeadCardService } from "./lead-card.service";
import { LeadCommandService } from "./lead-command.service";
import { LeadDirectoryService } from "./lead-directory.service";

export { LeadBoardColumnDto } from "./lead-model";

/** Stable lead application port used by the controller and integration code. */
@Injectable()
export class LeadsService {
  constructor(
    private readonly board: LeadBoardService,
    private readonly card: LeadCardService,
    private readonly directory: LeadDirectoryService,
    private readonly commands: LeadCommandService,
  ) {}

  listLeadBoard(actor: ActorContext, query: LeadBoardQuery) {
    return this.board.list(actor, query);
  }

  getLeadCard(actor: ActorContext, leadId: string) {
    return this.card.get(actor, leadId);
  }

  listLeadStatusHistory(actor: ActorContext, leadId: string) {
    return this.directory.listStatusHistory(actor, leadId);
  }

  listLeadApplications(actor: ActorContext, leadId: string) {
    return this.directory.listApplications(actor, leadId);
  }

  listLeads(actor: ActorContext, query: CrmListQuery) {
    return this.directory.list(actor, query);
  }

  linkStudentToLead(
    actor: ActorContext,
    leadId: string,
    studentId: string,
  ) {
    return this.commands.linkStudent(actor, leadId, studentId);
  }

  createLead(
    actor: ActorContext,
    dto: UpsertLeadDto,
    validated?: ValidatedLeadCreate,
  ) {
    return this.commands.create(actor, dto, validated);
  }

  updateLead(
    actor: ActorContext,
    leadId: string,
    dto: UpdateLeadDto,
    customFields?: ValidatedCustomFields,
  ) {
    return this.commands.update(actor, leadId, dto, customFields);
  }

  async deleteLead(actor: ActorContext, leadId: string) {
    return this.commands.delete(actor, leadId);
  }
}
