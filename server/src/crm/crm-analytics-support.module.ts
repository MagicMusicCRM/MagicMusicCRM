import { Module } from "@nestjs/common";
import { AuditModule } from "../audit/audit.module";
import { DatabaseModule } from "../db/database.module";
import { CrmPolicy } from "./crm.policy";
import { DashboardService } from "./dashboard.service";

@Module({
  imports: [DatabaseModule, AuditModule],
  providers: [CrmPolicy, DashboardService],
  exports: [CrmPolicy, DashboardService],
})
export class CrmAnalyticsSupportModule {}
