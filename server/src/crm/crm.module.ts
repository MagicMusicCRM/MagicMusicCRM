import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AuditModule } from "../audit/audit.module";
import { AuthModule } from "../auth/auth.module";
import { AccessControlModule } from "../access-control/access-control.module";
import { LEAD_INTAKE_PORT } from "../common/lead-intake.port";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { RolesGuard } from "../common/security/roles.guard";
import { DatabaseModule } from "../db/database.module";
import { NotificationDeliveryModule } from "../notifications/notification-delivery.module";
import { ChatWorkTimelineModule } from "../messenger/chat-work-timeline.module";
import { PlatformModule } from "../platform/platform.module";
import { AdminStaffController } from "./admin-staff.controller";
import { CrmStudentsController } from "./crm-students.controller";
import { CrmDashboardController } from "./crm-dashboard.controller";
import { CrmScheduleController } from "./crm-schedule.controller";
import { CrmPeopleController } from "./crm-people.controller";
import { CrmFacilitiesController } from "./crm-facilities.controller";
import { CrmReferenceDataController } from "./crm-reference-data.controller";
import { CrmEngagementController } from "./crm-engagement.controller";
import { CrmFinanceController } from "./crm-finance.controller";
import { CrmLeadsController } from "./crm-leads.controller";
import { CrmContactsController } from "./crm-contacts.controller";
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { CrmPolicy } from "./crm.policy";
import { CrmService } from "./crm.service";
import { BlacklistService } from "./blacklist.service";
import { HomeworkService } from "./homework.service";
import { ReferenceDataService } from "./reference-data.service";
import { ReferenceCatalogLifecycleService } from "./reference-catalog-lifecycle.service";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { StaffService } from "./staff.service";
import { TeachersService } from "./teachers.service";
import { PersonAccountService } from "./person-account.service";
import { PersonLifecycleService } from "./person-lifecycle.service";
import { ScheduleService } from "./schedule.service";
import { ScheduleReadService } from "./schedule/schedule-read.service";
import { ScheduleConflictService } from "./schedule/schedule-conflict.service";
import { ScheduleSeriesMaterializerService } from "./schedule/schedule-series-materializer.service";
import { ScheduleSeriesService } from "./schedule/schedule-series.service";
import { SectionViewsService } from "./section-views.service";
import { TimelineService } from "./timeline.service";
import { DashboardService } from "./dashboard.service";
import { ClientLinkingService } from "./client-linking.service";
import { FamilyService } from "./family.service";
import { DuplicatesService } from "./duplicates.service";
import { MergeService } from "./merge.service";
import { PhoneReviewService } from "./phone-review.service";
import { LeadsService } from "./leads.service";
import { LeadIntakeService } from "./lead-intake.service";
import { RoomsService } from "./rooms.service";
import { RoomLifecycleService } from "./room-lifecycle.service";
import { BranchesService } from "./branches.service";
import { BranchLifecycleService } from "./branch-lifecycle.service";
import { GroupsService } from "./groups.service";
import { GroupLifecycleService } from "./group-lifecycle.service";
import { PayrollService } from "./payroll.service";
import { LeadWebhookController } from "./lead-webhook.controller";
import { ScheduleSeriesWorker } from "./schedule-series.worker";
import { CommentSharingService } from "./clients/comment-sharing.service";
import { ClientReferenceService } from "./clients/client-reference.service";
import { CrmClientsController } from "./crm-clients.controller";
import { CrmClientConfigController } from "./crm-client-config.controller";
import { ClientConfigRepository } from "./clients/client-config.repository";
import { ClientConfigService } from "./clients/client-config.service";
import { ClientWriteValidator } from "./clients/client-write.validator";
import { InboundLeadService } from "./clients/inbound-lead.service";
import { ClientConversionService } from "./clients/client-conversion.service";
import { ClientArchiveService } from "./clients/client-archive.service";
import { ClientCardReadService } from "./clients/client-card-read.service";
import { ClientInternalContextService } from "./clients/client-internal-context.service";
import { LessonLifecycleRepository } from "./schedule/lesson-lifecycle.repository";
import { AvailabilityController } from "./schedule/availability.controller";
import { AvailabilityRepository } from "./schedule/availability.repository";
import { AvailabilityService } from "./schedule/availability.service";
import { ConstraintEngineRepository } from "./schedule/constraint-engine.repository";
import { ScheduleConstraintEngine } from "./schedule/constraint-engine.service";
import { LessonRequiredFieldValidator } from "./schedule/lesson-required-field.validator";
import { LessonCommandService } from "./schedule/lesson-command.service";
import { LessonSeriesCommandService } from "./schedule/lesson-series-command.service";
import { LessonTransitionService } from "./schedule/lesson-transition.service";
import { LESSON_SETTLEMENT_PORT } from "./commerce/lesson-settlement.port";
import { LessonSettlementRepository } from "./commerce/lesson-settlement.repository";
import { LessonSettlementService } from "./commerce/lesson-settlement.service";
import { LessonCompletionWorkerRepository } from "./schedule/completion-worker.repository";
import { LessonCompletionService } from "./schedule/lesson-completion.service";
import { LessonCompletionWorker } from "./schedule/lesson-completion.worker";
import { PackageCatalogRepository } from "./commerce/package-catalog.repository";
import { PackageCatalogService } from "./commerce/package-catalog.service";
import { SubscriptionCommerceController } from "./subscription-commerce.controller";
import { SubscriptionIssueRepository } from "./commerce/subscription-issue.repository";
import { SubscriptionIssueService } from "./commerce/subscription-issue.service";
import { ActualPaymentService } from "./commerce/actual-payment.service";
import { SubscriptionLifecycleRepository } from "./commerce/subscription-lifecycle.repository";
import { SubscriptionLifecycleService } from "./commerce/subscription-lifecycle.service";
import { SubscriptionPreviewTokenService } from "./commerce/subscription-preview-token.service";
import { CommerceProjectionController } from "./commerce/commerce-projection.controller";
import { CommerceProjectionFactory } from "./commerce/commerce-projection.factory";
import { CommerceProjectionRepository } from "./commerce/commerce-projection.repository";
import { CommerceProjectionService } from "./commerce/commerce-projection.service";
import { SubscriptionReservationService } from "./commerce/subscription-reservation.service";
import { SharedTaskController } from "./shared-task.controller";
import { SharedTaskRepository } from "./tasks/shared-task.repository";
import { SharedTaskService } from "./tasks/shared-task.service";
import { SharedTaskReminderWorker } from "./tasks/shared-task-reminder.worker";
import { CrmClientPipelineController } from "./crm-student-funnel.controller";
import { StudentFunnelService } from "./student-funnel.service";
import { CrmConfigurationController } from "./crm-configuration.controller";
import { CrmConfigurationService } from "./crm-configuration.service";
import { InstallmentDueWorker } from "./commerce/installment-due.worker";
import { PaymentLifecycleRepository } from "./commerce/payment-lifecycle.repository";
import { PaymentLifecycleService } from "./commerce/payment-lifecycle.service";
import { PaymentReversalRepository } from "./commerce/payment-reversal.repository";
import { PaymentReversalService } from "./commerce/payment-reversal.service";
import { PaymentCorrectionService } from "./commerce/payment-correction.service";
import { SchedulePlanRepository } from "./schedule/schedule-plan.repository";
import { SchedulePlanService } from "./schedule/schedule-plan.service";
import { LessonSettlementCorrectionService } from "./schedule/lesson-settlement-correction.service";

@Module({
  imports: [
    AuditModule,
    AuthModule,
    AccessControlModule,
    DatabaseModule,
    JwtModule.register({}),
    NotificationDeliveryModule,
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
    SubscriptionCommerceController,
    CommerceProjectionController,
    SharedTaskController,
    CrmClientPipelineController,
    CrmConfigurationController,
  ],
  providers: [
    CrmService,
    BlacklistService,
    HomeworkService,
    ReferenceDataService,
    ReferenceCatalogLifecycleService,
    SubscriptionsService,
    FinanceService,
    StaffService,
    TeachersService,
    PersonAccountService,
    PersonLifecycleService,
    ScheduleReadService,
    ScheduleConflictService,
    ScheduleSeriesMaterializerService,
    ScheduleSeriesService,
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
    RoomLifecycleService,
    BranchesService,
    BranchLifecycleService,
    GroupsService,
    GroupLifecycleService,
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
    ClientCardReadService,
    ClientInternalContextService,
    LessonLifecycleRepository,
    AvailabilityRepository,
    AvailabilityService,
    ConstraintEngineRepository,
    ScheduleConstraintEngine,
    LessonRequiredFieldValidator,
    LessonCommandService,
    LessonSeriesCommandService,
    SchedulePlanRepository,
    SchedulePlanService,
    LessonTransitionService,
    LessonSettlementRepository,
    LessonSettlementService,
    LessonCompletionWorkerRepository,
    LessonCompletionService,
    LessonCompletionWorker,
    LessonSettlementCorrectionService,
    PackageCatalogRepository,
    PackageCatalogService,
    SubscriptionIssueRepository,
    SubscriptionIssueService,
    ActualPaymentService,
    SubscriptionLifecycleRepository,
    SubscriptionLifecycleService,
    SubscriptionPreviewTokenService,
    CommerceProjectionFactory,
    CommerceProjectionRepository,
    CommerceProjectionService,
    SubscriptionReservationService,
    PaymentLifecycleRepository,
    PaymentLifecycleService,
    PaymentReversalRepository,
    PaymentReversalService,
    PaymentCorrectionService,
    InstallmentDueWorker,
    SharedTaskRepository,
    SharedTaskService,
    SharedTaskReminderWorker,
    StudentFunnelService,
    CrmConfigurationService,
    {
      provide: LESSON_SETTLEMENT_PORT,
      useExisting: LessonSettlementService,
    },
    JwtAuthGuard,
    RolesGuard,
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
  ],
})
export class CrmModule {}
