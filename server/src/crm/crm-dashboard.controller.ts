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
import { DashboardService } from "./dashboard.service";
import { ActivityLogQuery } from "./dto/activity-log.query";
import { ManagerDashboardQuery } from "./dto/manager-dashboard.query";
import { ReportQuery } from "./dto/report.query";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmDashboardController {
  constructor(
    private readonly dashboard: DashboardService,
  ) {}

  @Get("overview")
  getOverview(@CurrentActor() actor: ActorContext) {
    return this.dashboard.getOverview(actor);
  }

  @Get("dashboard/manager")
  getManagerDashboard(
    @CurrentActor() actor: ActorContext,
    @Query() query: ManagerDashboardQuery,
  ) {
    return this.dashboard.getManagerDashboard(actor, query);
  }

  @Get("reports/finance")
  getFinanceReport(
    @CurrentActor() actor: ActorContext,
    @Query() query: ReportQuery,
  ) {
    return this.dashboard.getFinanceReport(actor, query);
  }

  @Get("activity")
  listActivityLog(
    @CurrentActor() actor: ActorContext,
    @Query() query: ActivityLogQuery,
  ) {
    return this.dashboard.listActivityLog(actor, query);
  }
}
