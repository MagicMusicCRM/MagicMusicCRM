import { Body, Controller, Get, Post, Query, UseGuards } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import {
  ClientPipelineQuery,
  PreviewClientPipelineDto,
  PublishClientPipelineDto,
  RollbackClientPipelineDto,
} from "./dto/student-funnel.dto";
import { StudentFunnelService } from "./student-funnel.service";

@UseGuards(JwtAuthGuard)
@Controller("crm/client-pipelines")
export class CrmClientPipelineController {
  constructor(private readonly pipelines: StudentFunnelService) {}

  @Get()
  getEffective(
    @CurrentActor() actor: ActorContext,
    @Query() query: ClientPipelineQuery,
  ) {
    return this.pipelines.getEffective(actor, query.branchId, query.clientType);
  }

  @Get("revisions")
  listRevisions(
    @CurrentActor() actor: ActorContext,
    @Query() query: ClientPipelineQuery,
  ) {
    return this.pipelines.listRevisions(actor, query.branchId, query.clientType);
  }

  @Post("preview")
  preview(
    @CurrentActor() actor: ActorContext,
    @Body() dto: PreviewClientPipelineDto,
  ) {
    return this.pipelines.preview(actor, dto);
  }

  @Post("publish")
  publish(
    @CurrentActor() actor: ActorContext,
    @Body() dto: PublishClientPipelineDto,
  ) {
    return this.pipelines.publish(actor, dto);
  }

  @Post("rollback")
  rollback(
    @CurrentActor() actor: ActorContext,
    @Body() dto: RollbackClientPipelineDto,
  ) {
    return this.pipelines.rollback(actor, dto);
  }
}
