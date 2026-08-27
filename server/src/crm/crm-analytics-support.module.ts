import { Module } from "@nestjs/common";
import { DatabaseModule } from "../db/database.module";
import { CrmPolicy } from "./crm.policy";
import { DashboardService } from "./dashboard.service";

@Module({
  imports: [DatabaseModule],
  providers: [CrmPolicy, DashboardService],
  exports: [CrmPolicy, DashboardService],
})
export class CrmAnalyticsSupportModule {}
