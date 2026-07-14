import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { CrmController } from './crm.controller';
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { CrmPolicy } from './crm.policy';
import { CrmService } from './crm.service';
import { HomeworkService } from './homework.service';
import { ReferenceDataService } from './reference-data.service';
import { SubscriptionsService } from './subscriptions.service';
import { RoomsService } from './rooms.service';
import { BranchesService } from './branches.service';
import { GroupsService } from './groups.service';
import { PayrollService } from './payroll.service';
import { LeadWebhookController } from './lead-webhook.controller';
import { ScheduleSeriesWorker } from './schedule-series.worker';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({}), NotificationsModule],
  controllers: [CrmController, LeadWebhookController],
  providers: [CrmService, HomeworkService, ReferenceDataService, SubscriptionsService, RoomsService, BranchesService, GroupsService, PayrollService, CrmPolicy, HolliHopMetadataService, ScheduleSeriesWorker, JwtAuthGuard],
  exports: [CrmService, CrmPolicy]
})
export class CrmModule {}
