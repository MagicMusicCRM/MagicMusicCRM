import { Controller, Get, Query, Res, StreamableFile, UseGuards } from "@nestjs/common";
import { Response } from "express";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { AnalyticsRangeQuery } from "./dto/analytics-range.query";
import { ClientStatusFilterQuery } from "./dto/client-status-filter.query";
import { AnalyticsService } from "./analytics.service";
import { ClientStatusReadService } from "./client-status-read.service";

@Controller("analytics")
@UseGuards(JwtAuthGuard)
export class AnalyticsController {
  constructor(
    private readonly analytics: AnalyticsService,
    private readonly clientStatus: ClientStatusReadService,
  ) {}

  @Get("v4/client-status/summary")
  clientStatusSummary(
    @CurrentActor() actor: ActorContext,
    @Query() query: ClientStatusFilterQuery,
  ) {
    return this.clientStatus.summary(actor, query);
  }

  @Get("v4/client-status/clients")
  clientStatusClients(
    @CurrentActor() actor: ActorContext,
    @Query() query: ClientStatusFilterQuery,
  ) {
    return this.clientStatus.list(actor, query);
  }

  @Get("overview")
  overview(@CurrentActor() actor: ActorContext) {
    return this.analytics.overview(actor);
  }

  @Get("dashboard")
  dashboard(@CurrentActor() actor: ActorContext, @Query() query: AnalyticsRangeQuery) {
    return this.analytics.dashboard(actor, query as never);
  }

  @Get("funnel")
  funnel(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
  ) {
    return this.analytics.funnel(actor, query);
  }

  @Get("branches")
  branchComparison(@CurrentActor() actor: ActorContext, @Query() query: AnalyticsRangeQuery) {
    return this.analytics.branchComparison(actor, query);
  }

  @Get("loss-reasons")
  lossReasons(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
  ) {
    return this.analytics.lossReasons(actor, query);
  }

  @Get("debts")
  debts(@CurrentActor() actor: ActorContext, @Query() query: AnalyticsRangeQuery) {
    return this.analytics.debts(actor, query);
  }

  @Get("forecast")
  revenueForecast(@CurrentActor() actor: ActorContext, @Query() query: AnalyticsRangeQuery) {
    return this.analytics.revenueForecast(actor, query);
  }

  @Get("churn-risk")
  churnRisk(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
  ) {
    return this.analytics.churnRisk(actor, query);
  }

  @Get("weekly-report")
  weeklyReport(@CurrentActor() actor: ActorContext, @Query() query: AnalyticsRangeQuery) {
    return this.analytics.weeklyReport(actor, query);
  }

  @Get("chats/sla")
  chatsSla(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
  ) {
    return this.analytics.chatsSla(actor, { from: query.from, to: query.to });
  }

  @Get("finance/monthly")
  financeMonthly(@CurrentActor() actor: ActorContext, @Query() query: AnalyticsRangeQuery) {
    return this.analytics.financeMonthly(actor, query);
  }

  @Get("finance/monthly.csv")
  async financeMonthlyCsv(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const csv = await this.analytics.financeMonthlyCsv(actor, query);
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", 'attachment; filename="finance-monthly.csv"');
    return new StreamableFile(Buffer.from(csv, "utf-8"));
  }

  @Get("finance/monthly.xlsx")
  async financeMonthlyXlsx(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const xlsx = await this.analytics.financeMonthlyXlsx(actor, query);
    res.setHeader("Content-Type", "application/vnd.ms-excel");
    res.setHeader("Content-Disposition", 'attachment; filename="finance-monthly.xls"');
    return new StreamableFile(Buffer.from(xlsx, "utf-8"));
  }

  @Get("sources")
  sourceAnalytics(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
  ) {
    return this.analytics.sourceAnalytics(actor, query);
  }

  @Get("data-quality")
  dataQuality(@CurrentActor() actor: ActorContext, @Query() query: AnalyticsRangeQuery) {
    return this.analytics.dataQuality(actor, query);
  }

  @Get("responsible")
  responsibleDistribution(
    @CurrentActor() actor: ActorContext,
    @Query() query: AnalyticsRangeQuery,
  ) {
    return this.analytics.responsibleDistribution(actor, query);
  }
}
