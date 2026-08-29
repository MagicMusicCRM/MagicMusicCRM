import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AuditModule } from "../audit/audit.module";
import { DatabaseModule } from "../db/database.module";
import { CrmAnalyticsSupportModule } from "../crm/crm-analytics-support.module";
import { OoxmlWorkbookModule } from "../common/ooxml-workbook.module";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { AnalyticsController } from "./analytics.controller";
import { AnalyticsService } from "./analytics.service";
import { AnalyticsRefreshWorker } from "./analytics-refresh.worker";
import { ClientStatusReadService } from "./client-status-read.service";
import { ReportingReadService } from "./reporting-read.service";
import { ReportExportService } from "./report-export.service";

@Module({
  imports: [
    DatabaseModule,
    AuditModule,
    CrmAnalyticsSupportModule,
    OoxmlWorkbookModule,
    JwtModule.register({}),
  ],
  controllers: [AnalyticsController],
  providers: [
    AnalyticsService,
    AnalyticsRefreshWorker,
    ClientStatusReadService,
    ReportingReadService,
    ReportExportService,
    JwtAuthGuard,
  ],
})
export class AnalyticsModule {}
