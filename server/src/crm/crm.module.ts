import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { LEAD_INTAKE_PORT } from '../common/lead-intake.port';
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
import { FinanceService } from './finance.service';
import { TasksService } from './tasks.service';
import { AttendanceService } from './attendance.service';
import { StaffService } from './staff.service';
import { TeachersService } from './teachers.service';
import { ScheduleService } from './schedule.service';
import { TimelineService } from './timeline.service';
import { DashboardService } from './dashboard.service';
import { ClientLinkingService } from './client-linking.service';
import { RoomsService } from './rooms.service';
import { BranchesService } from './branches.service';
import { GroupsService } from './groups.service';
import { PayrollService } from './payroll.service';
import { LeadWebhookController } from './lead-webhook.controller';
import { ScheduleSeriesWorker } from './schedule-series.worker';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({}), NotificationsModule],
  controllers: [CrmController, LeadWebhookController],
  providers: [
    CrmService,
    HomeworkService,
    ReferenceDataService,
    SubscriptionsService,
    FinanceService,
    TasksService,
    AttendanceService,
    StaffService,
    TeachersService,
    ScheduleService,
    TimelineService,
    DashboardService,
    ClientLinkingService,
    RoomsService,
    BranchesService,
    GroupsService,
    PayrollService,
    CrmPolicy,
    HolliHopMetadataService,
    ScheduleSeriesWorker,
    JwtAuthGuard,
    // B2: bind the messenger's narrow lead-intake port to CrmService (its
    // current implementer). When lead logic moves to LeadsService (B5), only
    // this binding changes — messenger stays untouched.
    { provide: LEAD_INTAKE_PORT, useExisting: CrmService },
  ],
  exports: [CrmService, CrmPolicy, DashboardService, LEAD_INTAKE_PORT]
})
export class CrmModule {}
