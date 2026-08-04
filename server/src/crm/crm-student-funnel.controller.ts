import { Body, Controller, Get, Post, Query, UseGuards } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import {
  PublishStudentFunnelDto,
  RollbackStudentFunnelDto,
  StudentFunnelQuery,
} from "./dto/student-funnel.dto";
import { StudentFunnelService } from "./student-funnel.service";

@UseGuards(JwtAuthGuard)
@Controller("crm/student-funnel")
export class CrmStudentFunnelController {
  constructor(private readonly funnel: StudentFunnelService) {}

  @Get()
  getEffective(
    @CurrentActor() actor: ActorContext,
    @Query() query: StudentFunnelQuery,
  ) {
    return this.funnel.getEffective(actor, query.branchId);
  }

  @Get("revisions")
  listRevisions(
    @CurrentActor() actor: ActorContext,
    @Query() query: StudentFunnelQuery,
  ) {
    return this.funnel.listRevisions(actor, query.branchId);
  }

  @Post("publish")
  publish(
    @CurrentActor() actor: ActorContext,
    @Body() dto: PublishStudentFunnelDto,
  ) {
    return this.funnel.publish(actor, dto);
  }

  @Post("rollback")
  rollback(
    @CurrentActor() actor: ActorContext,
    @Body() dto: RollbackStudentFunnelDto,
  ) {
    return this.funnel.rollback(actor, dto);
  }
}
