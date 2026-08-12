import {
  Body,
  Controller,
  Get,
  Headers,
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
import { CreateDisciplineDto } from "./dto/create-discipline.dto";
import { CreateLossReasonDto } from "./dto/create-loss-reason.dto";
import { UpsertBranchDisciplineDto } from "./dto/upsert-branch-discipline.dto";
import { ReorderBranchDisciplinesDto } from "./dto/reorder-branch-disciplines.dto";
import {
  ReferenceCatalogLifecycleCommandDto,
  ReferenceCatalogListQuery,
  RenameReferenceCatalogItemDto,
} from "./dto/reference-catalog-lifecycle.dto";
import { ReferenceCatalogLifecycleService } from "./reference-catalog-lifecycle.service";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmReferenceDataController {
  constructor(
    private readonly referenceData: ReferenceDataService,
    private readonly referenceLifecycle: ReferenceCatalogLifecycleService,
  ) {}

  @Get("lead-statuses")
  listLeadStatuses(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.referenceData.listLeadStatuses(actor, query);
  }

  @Get("loss-reasons")
  listLossReasons(
    @CurrentActor() actor: ActorContext,
    @Query() query: ReferenceCatalogListQuery,
  ) {
    return this.referenceData.listLossReasons(actor, query.includeArchived);
  }

  @Get("lead-sources")
  listLeadSources(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listLeadSources(actor);
  }

  @Get("disciplines")
  listDisciplines(
    @CurrentActor() actor: ActorContext,
    @Query() query: ReferenceCatalogListQuery,
  ) {
    return this.referenceData.listDisciplines(actor, query.includeArchived);
  }

  @Get("branches/:branchId/disciplines")
  listBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Query() query: ReferenceCatalogListQuery,
  ) {
    return this.referenceData.listBranchDisciplines(
      actor,
      branchId,
      query.includeArchived,
    );
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

  @Post("disciplines/:id/lifecycle-preview")
  previewDisciplineLifecycle(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceLifecycle.preview(actor, "discipline", id);
  }

  @Patch("disciplines/:id")
  renameDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: RenameReferenceCatalogItemDto,
  ) {
    return this.referenceLifecycle.rename(actor, "discipline", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("disciplines/:id/archive")
  archiveDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReferenceCatalogLifecycleCommandDto,
  ) {
    return this.referenceLifecycle.archive(actor, "discipline", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("disciplines/:id/restore")
  restoreDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReferenceCatalogLifecycleCommandDto,
  ) {
    return this.referenceLifecycle.restore(actor, "discipline", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Get("disciplines/:id/history")
  disciplineHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceLifecycle.history(actor, "discipline", id);
  }

  @Post("loss-reasons/:id/lifecycle-preview")
  previewLossReasonLifecycle(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceLifecycle.preview(actor, "loss_reason", id);
  }

  @Patch("loss-reasons/:id")
  renameLossReason(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: RenameReferenceCatalogItemDto,
  ) {
    return this.referenceLifecycle.rename(actor, "loss_reason", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("loss-reasons/:id/archive")
  archiveLossReason(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReferenceCatalogLifecycleCommandDto,
  ) {
    return this.referenceLifecycle.archive(actor, "loss_reason", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("loss-reasons/:id/restore")
  restoreLossReason(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReferenceCatalogLifecycleCommandDto,
  ) {
    return this.referenceLifecycle.restore(actor, "loss_reason", id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Get("loss-reasons/:id/history")
  lossReasonHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceLifecycle.history(actor, "loss_reason", id);
  }

  @Post("branch-disciplines/:id/lifecycle-preview")
  previewBranchDisciplineLifecycle(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceLifecycle.preview(actor, "branch_discipline", id);
  }

  @Post("branch-disciplines/:id/unassign")
  unassignBranchDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReferenceCatalogLifecycleCommandDto,
  ) {
    return this.referenceLifecycle.archive(
      actor,
      "branch_discipline",
      id,
      dto,
      {
        idempotencyKey: idempotencyKey ?? "",
        requestId: requestId ?? "",
      },
    );
  }

  @Post("branch-disciplines/:id/restore")
  restoreBranchDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReferenceCatalogLifecycleCommandDto,
  ) {
    return this.referenceLifecycle.restore(
      actor,
      "branch_discipline",
      id,
      dto,
      {
        idempotencyKey: idempotencyKey ?? "",
        requestId: requestId ?? "",
      },
    );
  }

  @Get("branch-disciplines/:id/history")
  branchDisciplineHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceLifecycle.history(actor, "branch_discipline", id);
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

}
