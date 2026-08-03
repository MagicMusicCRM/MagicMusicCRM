import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Put,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { CurrentActor } from "../../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../../common/security/jwt-auth.guard";
import {
  ReplaceBranchHoursDto,
  ReplaceTeacherAvailabilityDto,
  ReplaceTeacherBranchesDto,
  ScheduleReferenceQuery,
} from "./availability.dto";
import { AvailabilityService } from "./availability.service";
import { V4DomainFlagsService } from "../../platform/v4-domain-flags";

@UseGuards(JwtAuthGuard)
@Controller("crm/schedule-reference")
export class AvailabilityController {
  constructor(
    private readonly availability: AvailabilityService,
    private readonly v4DomainFlags: V4DomainFlagsService,
  ) {}

  @Get()
  resolve(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleReferenceQuery,
  ) {
    return this.availability.resolve(actor, query);
  }

  @Put("branches/:branchId/hours")
  replaceBranchHours(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Body() dto: ReplaceBranchHoursDto,
  ) {
    this.v4DomainFlags.assertEnabled("schedule");
    return this.availability.replaceBranchHours(actor, branchId, dto);
  }

  @Put("teachers/:teacherId/branches")
  replaceTeacherBranches(
    @CurrentActor() actor: ActorContext,
    @Param("teacherId", ParseUUIDPipe) teacherId: string,
    @Body() dto: ReplaceTeacherBranchesDto,
  ) {
    this.v4DomainFlags.assertEnabled("schedule");
    return this.availability.replaceTeacherBranches(actor, teacherId, dto);
  }

  @Put("teachers/:teacherId/availability")
  replaceTeacherAvailability(
    @CurrentActor() actor: ActorContext,
    @Param("teacherId", ParseUUIDPipe) teacherId: string,
    @Body() dto: ReplaceTeacherAvailabilityDto,
  ) {
    this.v4DomainFlags.assertEnabled("schedule");
    return this.availability.replaceTeacherAvailability(actor, teacherId, dto);
  }
}
