import {
  Body,
  Controller,
  Get,
  Post,
  Put,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import {
  CrmConfigurationQuery,
  PublishCrmConfigurationDto,
  RollbackCrmConfigurationDto,
  SaveCrmConfigurationDraftDto,
} from "./dto/crm-configuration.dto";
import { CrmConfigurationService } from "./crm-configuration.service";

@UseGuards(JwtAuthGuard)
@Controller("crm/configuration")
export class CrmConfigurationController {
  constructor(private readonly configuration: CrmConfigurationService) {}

  @Get("effective")
  getEffective(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmConfigurationQuery,
  ) {
    return this.configuration.getEffective(actor, query.branchId);
  }

  @Get("lesson-decisions")
  getLessonDecisionCatalog(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmConfigurationQuery,
  ) {
    return this.configuration.getLessonDecisionCatalog(actor, query.branchId);
  }

  @Get("draft")
  getDraft(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmConfigurationQuery,
  ) {
    return this.configuration.getDraft(actor, query.branchId);
  }

  @Put("draft")
  saveDraft(
    @CurrentActor() actor: ActorContext,
    @Body() dto: SaveCrmConfigurationDraftDto,
  ) {
    return this.configuration.saveDraft(actor, dto);
  }

  @Post("preview")
  preview(
    @CurrentActor() actor: ActorContext,
    @Body() dto: SaveCrmConfigurationDraftDto,
  ) {
    return this.configuration.preview(actor, dto);
  }

  @Post("publish")
  publish(
    @CurrentActor() actor: ActorContext,
    @Body() dto: PublishCrmConfigurationDto,
  ) {
    return this.configuration.publish(actor, dto);
  }

  @Get("revisions")
  revisions(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmConfigurationQuery,
  ) {
    return this.configuration.listRevisions(actor, query.branchId);
  }

  @Post("rollback")
  rollback(
    @CurrentActor() actor: ActorContext,
    @Body() dto: RollbackCrmConfigurationDto,
  ) {
    return this.configuration.rollback(actor, dto);
  }
}
