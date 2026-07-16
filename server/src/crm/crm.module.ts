import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { LEAD_INTAKE_PORT } from '../common/lead-intake.port';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ChatWorkTimelineModule } from '../messenger/chat-work-timeline.module';
import { CrmStudentsController } from './crm-students.controller';
import { CrmDashboardController } from './crm-dashboard.controller';
import { CrmScheduleController } from './crm-schedule.controller';
import { CrmPeopleController } from './crm-people.controller';
import { CrmFacilitiesController } from './crm-facilities.controller';
import { CrmReferenceDataController } from './crm-reference-data.controller';
import { CrmEngagementController } from './crm-engagement.controller';
import { CrmFinanceController } from './crm-finance.controller';
import { CrmLeadsController } from './crm-leads.controller';
import { CrmContactsController } from './crm-contacts.controller';
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
import { FamilyService } from './family.service';
import { DuplicatesService } from './duplicates.service';
import { MergeService } from './merge.service';
import { PhoneReviewService } from './phone-review.service';
import { LeadsService } from './leads.service';
import { LeadIntakeService } from './lead-intake.service';
import { RoomsService } from './rooms.service';
import { BranchesService } from './branches.service';
import { GroupsService } from './groups.service';
import { PayrollService } from './payroll.service';
import { LeadWebhookController } from './lead-webhook.controller';
import { ScheduleSeriesWorker } from './schedule-series.worker';

@Module({
  imports: [
    AuditModule,
    DatabaseModule,
    JwtModule.register({}),
    NotificationsModule,
    ChatWorkTimelineModule,
  ],
  controllers: [
    CrmStudentsController,
    CrmDashboardController,
    CrmScheduleController,
    CrmPeopleController,
    CrmFacilitiesController,
    CrmReferenceDataController,
    CrmEngagementController,
    CrmFinanceController,
    CrmLeadsController,
    CrmContactsController,
    LeadWebhookController,
  ],
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
    FamilyService,
    DuplicatesService,
    MergeService,
    PhoneReviewService,
    LeadsService,
    LeadIntakeService,
    RoomsService,
    BranchesService,
    GroupsService,
    PayrollService,
    CrmPolicy,
    HolliHopMetadataService,
    ScheduleSeriesWorker,
    JwtAuthGuard,
    // Lead intake (chat/app/site → lead) lives in LeadIntakeService, the port
    // implementer. The messenger depends only on LEAD_INTAKE_PORT, so this
    // binding is the single point that moves — messenger stays untouched.
    { provide: LEAD_INTAKE_PORT, useExisting: LeadIntakeService },
  ],
  // CrmService is not exported: it is only injected by this module's own
  // controllers. Other modules consume the stable contract surface —
  // DashboardService (analytics), CrmPolicy, and LEAD_INTAKE_PORT (messenger).
  exports: [CrmPolicy, DashboardService, LEAD_INTAKE_PORT]
})
export class CrmModule {}
