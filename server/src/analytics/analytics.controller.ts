import { Controller, Get, Query, Res, StreamableFile, UseGuards } from "@nestjs/common";
import { Response } from "express";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { AnalyticsService } from "./analytics.service";

@Controller("analytics")
@UseGuards(JwtAuthGuard)
export class AnalyticsController {
  constructor(private readonly analytics: AnalyticsService) {}

  @Get("overview")
  overview(@CurrentActor() actor: ActorContext) {
    return this.analytics.overview(actor);
  }

  @Get("dashboard")
  dashboard(@CurrentActor() actor: ActorContext, @Query() query: Record<string, string>) {
    return this.analytics.dashboard(actor, query as never);
  }

  @Get("funnel")
  funnel(
    @CurrentActor() actor: ActorContext,
    @Query() query: { from?: string; to?: string; branchId?: string },
  ) {
    return this.analytics.funnel(actor, query);
  }

  @Get("branches")
  branchComparison(@CurrentActor() actor: ActorContext, @Query() query: { from?: string; to?: string }) {
    return this.analytics.branchComparison(actor, query);
  }

  @Get("loss-reasons")
  lossReasons(
    @CurrentActor() actor: ActorContext,
    @Query() query: { from?: string; to?: string; branchId?: string },
  ) {
    return this.analytics.lossReasons(actor, query);
  }

  @Get("debts")
  debts(@CurrentActor() actor: ActorContext, @Query() query: { branchId?: string }) {
    return this.analytics.debts(actor, query);
  }

  @Get("forecast")
  revenueForecast(@CurrentActor() actor: ActorContext, @Query() query: { branchId?: string }) {
    return this.analytics.revenueForecast(actor, query);
  }

  @Get("finance/monthly")
  financeMonthly(@CurrentActor() actor: ActorContext, @Query() query: { from?: string; to?: string }) {
    return this.analytics.financeMonthly(actor, query);
  }

  @Get("finance/monthly.csv")
  async financeMonthlyCsv(
    @CurrentActor() actor: ActorContext,
    @Query() query: { from?: string; to?: string },
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const csv = await this.analytics.financeMonthlyCsv(actor, query);
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", 'attachment; filename="finance-monthly.csv"');
    return new StreamableFile(Buffer.from(csv, "utf-8"));
  }
}
