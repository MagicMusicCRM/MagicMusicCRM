import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { LEAD_INTAKE_PORT } from '../common/lead-intake.port';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ChatWorkTimelineModule } from '../messenger/chat-work-timeline.module';
import { PlatformModule } from '../platform/platform.module';
import { AdminStaffController } from './admin-staff.controller';
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
import { BlacklistService } from './blacklist.service';
import { HomeworkService } from './homework.service';
import { ReferenceDataService } from './reference-data.service';
import { SubscriptionsService } from './subscriptions.service';
import { FinanceService } from './finance.service';
import { TasksService } from './tasks.service';
import { StaffService } from './staff.service';
import { TeachersService } from './teachers.service';
import { ScheduleService } from './schedule.service';
import { SectionViewsService } from './section-views.service';
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
import { CommentSharingService } from './clients/comment-sharing.service';
import { ClientReferenceService } from './clients/client-reference.service';
import { CrmClientsController } from './crm-clients.controller';
import { CrmClientConfigController } from './crm-client-config.controller';
import { ClientConfigRepository } from './clients/client-config.repository';
import { ClientConfigService } from './clients/client-config.service';
import { ClientWriteValidator } from './clients/client-write.validator';
import { InboundLeadService } from './clients/inbound-lead.service';
import { ClientConversionService } from './clients/client-conversion.service';
import { ClientArchiveService } from './clients/client-archive.service';
import { LessonLifecycleRepository } from './schedule/lesson-lifecycle.repository';
import { AvailabilityController } from './schedule/availability.controller';
import { AvailabilityRepository } from './schedule/availability.repository';
import { AvailabilityService } from './schedule/availability.service';
import { ConstraintEngineRepository } from './schedule/constraint-engine.repository';
import { ScheduleConstraintEngine } from './schedule/constraint-engine.service';
import { LessonRequiredFieldValidator } from './schedule/lesson-required-field.validator';
import { LessonCommandService } from './schedule/lesson-command.service';
import { LessonSeriesCommandService } from './schedule/lesson-series-command.service';
import { LessonTransitionFinancialService } from './schedule/lesson-transition-financial.service';
import { LessonTransitionService } from './schedule/lesson-transition.service';
import { LESSON_SETTLEMENT_PORT } from './commerce/lesson-settlement.port';
import { LessonSettlementRepository } from './commerce/lesson-settlement.repository';
import { LessonSettlementService } from './commerce/lesson-settlement.service';
import { LessonCompletionWorkerRepository } from './schedule/completion-worker.repository';
import { LessonCompletionService } from './schedule/lesson-completion.service';
import { LessonCompletionWorker } from './schedule/lesson-completion.worker';
import { PackageCatalogRepository } from './commerce/package-catalog.repository';
import { PackageCatalogService } from './commerce/package-catalog.service';

@Module({
  imports: [
    AuditModule,
    DatabaseModule,
    JwtModule.register({}),
    NotificationsModule,
    ChatWorkTimelineModule,
    PlatformModule,
  ],
  controllers: [
    AdminStaffController,
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
    CrmClientsController,
    CrmClientConfigController,
    AvailabilityController,
    LeadWebhookController,
  ],
  providers: [
    CrmService,
    BlacklistService,
    HomeworkService,
    ReferenceDataService,
    SubscriptionsService,
    FinanceService,
    TasksService,
    StaffService,
    TeachersService,
    ScheduleService,
    TimelineService,
    SectionViewsService,
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
    CommentSharingService,
    ClientReferenceService,
    ClientConfigRepository,
    ClientConfigService,
    ClientWriteValidator,
    InboundLeadService,
    ClientConversionService,
    ClientArchiveService,
    LessonLifecycleRepository,
    AvailabilityRepository,
    AvailabilityService,
    ConstraintEngineRepository,
    ScheduleConstraintEngine,
    LessonRequiredFieldValidator,
    LessonCommandService,
    LessonSeriesCommandService,
    LessonTransitionFinancialService,
    LessonTransitionService,
    LessonSettlementRepository,
    LessonSettlementService,
    LessonCompletionWorkerRepository,
    LessonCompletionService,
    LessonCompletionWorker,
    PackageCatalogRepository,
    PackageCatalogService,
    {
      provide: LESSON_SETTLEMENT_PORT,
      useExisting: LessonSettlementService,
    },
    JwtAuthGuard,
    // Lead intake (chat/app/site → lead) lives in LeadIntakeService, the port
    // implementer. The messenger depends only on LEAD_INTAKE_PORT, so this
    // binding is the single point that moves — messenger stays untouched.
    { provide: LEAD_INTAKE_PORT, useExisting: LeadIntakeService },
  ],
  // CrmService is not exported: it is only injected by this module's own
  // controllers. Other modules consume the stable contract surface —
  // DashboardService (analytics), CrmPolicy, and LEAD_INTAKE_PORT (messenger).
  exports: [
    CrmPolicy,
    DashboardService,
    ClientReferenceService,
    ClientWriteValidator,
    LEAD_INTAKE_PORT,
    LESSON_SETTLEMENT_PORT,
    LessonCompletionWorker,
  ]
})
export class CrmModule {}
