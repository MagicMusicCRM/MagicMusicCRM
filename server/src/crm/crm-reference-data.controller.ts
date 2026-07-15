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
import { ReferenceDataService } from "./reference-data.service";
import { CrmListQuery } from "./dto/crm-list.query";
import { UpsertLeadStatusDto } from "./dto/upsert-lead-status.dto";
import { CreateDisciplineDto } from "./dto/create-discipline.dto";
import { CreateLossReasonDto } from "./dto/create-loss-reason.dto";
import { UpsertBranchDisciplineDto } from "./dto/upsert-branch-discipline.dto";
import { ReorderBranchDisciplinesDto } from "./dto/reorder-branch-disciplines.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmReferenceDataController {
  constructor(
    private readonly referenceData: ReferenceDataService,
  ) {}

  @Get("lead-statuses")
  listLeadStatuses(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.referenceData.listLeadStatuses(actor, query);
  }

  @Get("loss-reasons")
  listLossReasons(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listLossReasons(actor);
  }

  @Get("lead-sources")
  listLeadSources(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listLeadSources(actor);
  }

  @Get("disciplines")
  listDisciplines(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listDisciplines(actor);
  }

  @Get("branches/:branchId/disciplines")
  listBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
  ) {
    return this.referenceData.listBranchDisciplines(actor, branchId);
  }

  @Post("disciplines")
  createDiscipline(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateDisciplineDto,
  ) {
    return this.referenceData.createDiscipline(actor, dto);
  }

  @Post("loss-reasons")
  createLossReason(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateLossReasonDto,
  ) {
    return this.referenceData.createLossReason(actor, dto);
  }

  @Post("branches/:branchId/disciplines")
  assignBranchDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Body() dto: UpsertBranchDisciplineDto,
  ) {
    return this.referenceData.assignBranchDiscipline(actor, branchId, dto);
  }

  @Patch("branches/:branchId/disciplines/order")
  reorderBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Body() dto: ReorderBranchDisciplinesDto,
  ) {
    return this.referenceData.reorderBranchDisciplines(actor, branchId, dto);
  }

  @Get("hollihop/disciplines")
  listHolliHopDisciplines(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopDisciplines(actor);
  }

  @Get("hollihop/levels")
  listHolliHopLevels(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopLevels(actor);
  }

  @Get("hollihop/categories")
  listHolliHopCategories(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopCategories(actor);
  }

  @Get("hollihop/lead-statuses")
  listHolliHopLeadStatuses(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopLeadStatuses(actor);
  }

  @Post("lead-statuses")
  createLeadStatus(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertLeadStatusDto,
  ) {
    return this.referenceData.createLeadStatus(actor, dto);
  }

  @Patch("lead-statuses/order")
  reorderLeadStatuses(
    @CurrentActor() actor: ActorContext,
    @Body() dto: { statusIds: string[] },
  ) {
    return this.referenceData.reorderLeadStatuses(actor, dto);
  }

  @Delete("lead-statuses/:id")
  deleteLeadStatus(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceData.deleteLeadStatus(actor, id);
  }
}
