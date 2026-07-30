import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AuditModule } from "../audit/audit.module";
import { DatabaseModule } from "../db/database.module";
import { CrmModule } from "../crm/crm.module";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { AnalyticsController } from "./analytics.controller";
import { AnalyticsService } from "./analytics.service";
import { AnalyticsRefreshWorker } from "./analytics-refresh.worker";
import { ClientStatusReadService } from "./client-status-read.service";

@Module({
  imports: [DatabaseModule, AuditModule, CrmModule, JwtModule.register({})],
  controllers: [AnalyticsController],
  providers: [
    AnalyticsService,
    AnalyticsRefreshWorker,
    ClientStatusReadService,
    JwtAuthGuard,
  ],
})
export class AnalyticsModule {}
