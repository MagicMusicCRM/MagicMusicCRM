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
import { CrmAnalyticsSupportModule } from "./crm-analytics-support.module";
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { CrmService } from "./crm.service";
import { BlacklistService } from "./blacklist.service";
import { HomeworkService } from "./homework.service";
import { ReferenceDataService } from "./reference-data.service";
import { ReferenceCatalogLifecycleService } from "./reference-catalog-lifecycle.service";
import { SubscriptionsService } from "./subscriptions.service";
import { ExpenseService } from "./finance/expense.service";
import { FinancePaymentService } from "./finance/finance-payment.service";
import { StudentAccountTransferService } from "./finance/student-account-transfer.service";
import { StudentFinanceQueryService } from "./finance/student-finance-query.service";
import { FinanceService } from "./finance.service";
import { StaffService } from "./staff.service";
import { TeachersService } from "./teachers.service";
import { PersonAccountService } from "./person-account.service";
import { PersonLifecycleService } from "./person-lifecycle.service";
import { ScheduleReadService } from "./schedule/schedule-read.service";
import { ScheduleConflictService } from "./schedule/schedule-conflict.service";
import { ScheduleSeriesMaterializerService } from "./schedule/schedule-series-materializer.service";
import { ScheduleSeriesService } from "./schedule/schedule-series.service";
import { LessonScheduleMutationService } from "./schedule/lesson-schedule-mutation.service";
import { LessonTeacherRateService } from "./schedule/lesson-teacher-rate.service";
import { SectionViewsService } from "./section-views.service";
import { TimelineService } from "./timeline.service";
import { ClientLinkingService } from "./client-linking.service";
import { FamilyService } from "./family.service";
import { DuplicatesService } from "./duplicates.service";
import { MergeService } from "./merge.service";
import { PhoneReviewService } from "./phone-review.service";
import { LeadsService } from "./leads.service";
import { LeadBoardService } from "./lead-board.service";
import { LeadCardService } from "./lead-card.service";
import { LeadCommandService } from "./lead-command.service";
import { LeadDirectoryService } from "./lead-directory.service";
import { LeadWriteRepository } from "./lead-write.repository";
import { LeadIntakeService } from "./lead-intake.service";
import { RoomsService } from "./rooms.service";
import { RoomLifecycleService } from "./room-lifecycle.service";
import { BranchesService } from "./branches.service";
import { BranchLifecycleService } from "./branch-lifecycle.service";
import { GroupsService } from "./groups.service";
import { GroupLifecycleService } from "./group-lifecycle.service";
import { PayrollAccrualCalculator } from "./payroll/payroll-accrual-calculator";
import { PayrollReadRepository } from "./payroll/payroll-read.repository";
import { TeacherPayrollQueryService } from "./payroll/teacher-payroll-query.service";
import { TeacherPayrollCommandService } from "./payroll/teacher-payroll-command.service";
import { TeacherStatsReportService } from "./payroll/teacher-stats-report.service";
import { TeacherStatsXlsxService } from "./payroll/teacher-stats-xlsx.service";
import { OoxmlWorkbookModule } from "../common/ooxml-workbook.module";
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
import { LessonCommandRepository } from "./schedule/lesson-command.repository";
import { LessonConstraintPreviewService } from "./schedule/lesson-constraint-preview.service";
import { LessonPlannedSettlementCommandService } from "./schedule/lesson-planned-settlement-command.service";
import { LessonWriteCommandService } from "./schedule/lesson-write-command.service";
import { LessonCommandService } from "./schedule/lesson-command.service";
import { LessonSeriesCommandService } from "./schedule/lesson-series-command.service";
import { LessonTransitionService } from "./schedule/lesson-transition.service";
import { LessonTransitionPreparationService } from "./schedule/lesson-transition-preparation.service";
import { LessonTransitionFinancialService } from "./schedule/lesson-transition-financial.service";
import { LessonTransitionCommitService } from "./schedule/lesson-transition-commit.service";
import { LessonTransitionPreviewService } from "./schedule/lesson-transition-preview.service";
import { LessonTransitionCommandService } from "./schedule/lesson-transition-command.service";
import { LessonBulkTransitionService } from "./schedule/lesson-bulk-transition.service";
import { LESSON_SETTLEMENT_PORT } from "./commerce/lesson-settlement.port";
import { LessonSettlementService } from "./commerce/lesson-settlement.service";
import { LessonCompletionWorkerRepository } from "./schedule/completion-worker.repository";
import { LessonCompletionService } from "./schedule/lesson-completion.service";
import { LessonCompletionWorker } from "./schedule/lesson-completion.worker";
import { PackageCatalogRepository } from "./commerce/package-catalog.repository";
import { PackageCatalogService } from "./commerce/package-catalog.service";
import { SubscriptionCommerceController } from "./subscription-commerce.controller";
import { SubscriptionCommercialTermsService } from "./commerce/subscription-commercial-terms.service";
import { SubscriptionPurchaseTermsService } from "./commerce/subscription-purchase-terms.service";
import { SubscriptionPurchasePreviewService } from "./commerce/subscription-purchase-preview.service";
import { SubscriptionPurchasePaymentService } from "./commerce/subscription-purchase-payment.service";
import { SubscriptionPurchasePersistenceService } from "./commerce/subscription-purchase-persistence.service";
import { SubscriptionPurchaseCommandService } from "./commerce/subscription-purchase-command.service";
import { SubscriptionGrantCommandService } from "./commerce/subscription-grant-command.service";
import { SubscriptionIssueResultService } from "./commerce/subscription-issue-result.service";
import { SubscriptionIssueRepository } from "./commerce/subscription-issue.repository";
import { SubscriptionIssueService } from "./commerce/subscription-issue.service";
import { ActualPaymentService } from "./commerce/actual-payment.service";
import { SubscriptionLifecycleRepository } from "./commerce/subscription-lifecycle.repository";
import { SubscriptionLifecycleCommandPolicy } from "./commerce/subscription-lifecycle-command.policy";
import { SubscriptionCancellationService } from "./commerce/subscription-cancellation.service";
import { SubscriptionCancellationPolicy } from "./commerce/subscription-cancellation.policy";
import { SubscriptionReplacementPolicy } from "./commerce/subscription-replacement.policy";
import { SubscriptionReplacementService } from "./commerce/subscription-replacement.service";
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
import { StudentFunnelQueryService } from "./student-funnel/student-funnel-query.service";
import { StudentFunnelRepository } from "./student-funnel/student-funnel.repository";
import { StudentFunnelResolverService } from "./student-funnel/student-funnel-resolver.service";
import { StudentFunnelRevisionService } from "./student-funnel/student-funnel-revision.service";
import { StudentFunnelTransitionPolicy } from "./student-funnel/student-funnel-transition.policy";
import { StudentFunnelService } from "./student-funnel.service";
import { StudentDirectoryService } from "./students/student-directory.service";
import { StudentSelfSummaryService } from "./students/student-self-summary.service";
import { StudentCardTimelineService } from "./students/student-card-timeline.service";
import { StudentMutationExecutor } from "./students/student-mutation.executor";
import { StudentCommandService } from "./students/student-command.service";
import { CrmConfigurationController } from "./crm-configuration.controller";
import { CrmConfigurationService } from "./crm-configuration.service";
import { InstallmentDueWorker } from "./commerce/installment-due.worker";
import { PaymentLifecycleRepository } from "./commerce/payment-lifecycle.repository";
import { PaymentLifecycleService } from "./commerce/payment-lifecycle.service";
import { PaymentReversalRepository } from "./commerce/payment-reversal.repository";
import { PaymentReversalService } from "./commerce/payment-reversal.service";
import { PaymentCorrectionService } from "./commerce/payment-correction.service";
import { SchedulePlanRepository } from "./schedule/schedule-plan.repository";
import { SchedulePlanDefinitionService } from "./schedule/schedule-plan-definition.service";
import { SchedulePlanQueryService } from "./schedule/schedule-plan-query.service";
import { SchedulePlanConstraintPreviewService } from "./schedule/schedule-plan-constraint-preview.service";
import { SchedulePlanMutationService } from "./schedule/schedule-plan-mutation.service";
import { SchedulePlanEndService } from "./schedule/schedule-plan-end.service";
import { SchedulePlanService } from "./schedule/schedule-plan.service";
import { LessonSettlementCorrectionService } from "./schedule/lesson-settlement-correction.service";
import { StudentLessonTimelineRepository } from "./schedule/student-lesson-timeline.repository";
import { StudentLessonTimelineService } from "./schedule/student-lesson-timeline.service";

@Module({
  imports: [
    OoxmlWorkbookModule,
    AuditModule,
    AuthModule,
    AccessControlModule,
    CrmAnalyticsSupportModule,
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
    StudentDirectoryService,
    StudentSelfSummaryService,
    StudentCardTimelineService,
    StudentMutationExecutor,
    StudentCommandService,
    BlacklistService,
    HomeworkService,
    ReferenceDataService,
    ReferenceCatalogLifecycleService,
    SubscriptionsService,
    ExpenseService,
    FinancePaymentService,
    StudentAccountTransferService,
    StudentFinanceQueryService,
    FinanceService,
    StaffService,
    TeachersService,
    PersonAccountService,
    PersonLifecycleService,
    ScheduleReadService,
    ScheduleConflictService,
    ScheduleSeriesMaterializerService,
    ScheduleSeriesService,
    LessonScheduleMutationService,
    LessonTeacherRateService,
    TimelineService,
    SectionViewsService,
    ClientLinkingService,
    FamilyService,
    DuplicatesService,
    MergeService,
    PhoneReviewService,
    LeadsService,
    LeadBoardService,
    LeadCardService,
    LeadCommandService,
    LeadDirectoryService,
    LeadWriteRepository,
    LeadIntakeService,
    RoomsService,
    RoomLifecycleService,
    BranchesService,
    BranchLifecycleService,
    GroupsService,
    GroupLifecycleService,
    PayrollAccrualCalculator,
    PayrollReadRepository,
    TeacherPayrollQueryService,
    TeacherPayrollCommandService,
    TeacherStatsReportService,
    TeacherStatsXlsxService,
    PayrollService,
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
    LessonCommandRepository,
    LessonConstraintPreviewService,
    LessonWriteCommandService,
    LessonPlannedSettlementCommandService,
    LessonCommandService,
    LessonSeriesCommandService,
    SchedulePlanRepository,
    SchedulePlanDefinitionService,
    SchedulePlanQueryService,
    SchedulePlanConstraintPreviewService,
    SchedulePlanMutationService,
    SchedulePlanEndService,
    SchedulePlanService,
    LessonTransitionPreparationService,
    LessonTransitionFinancialService,
    LessonTransitionCommitService,
    LessonTransitionPreviewService,
    LessonTransitionCommandService,
    LessonBulkTransitionService,
    LessonTransitionService,
    LessonSettlementService,
    LessonCompletionWorkerRepository,
    LessonCompletionService,
    LessonCompletionWorker,
    LessonSettlementCorrectionService,
    StudentLessonTimelineRepository,
    StudentLessonTimelineService,
    PackageCatalogRepository,
    PackageCatalogService,
    SubscriptionPurchaseTermsService,
    SubscriptionCommercialTermsService,
    SubscriptionPurchasePreviewService,
    SubscriptionPurchasePaymentService,
    SubscriptionPurchasePersistenceService,
    SubscriptionPurchaseCommandService,
    SubscriptionGrantCommandService,
    SubscriptionIssueResultService,
    SubscriptionIssueRepository,
    SubscriptionIssueService,
    ActualPaymentService,
    SubscriptionLifecycleRepository,
    SubscriptionLifecycleCommandPolicy,
    SubscriptionReplacementPolicy,
    SubscriptionReplacementService,
    SubscriptionCancellationPolicy,
    SubscriptionCancellationService,
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
    StudentFunnelRepository,
    StudentFunnelResolverService,
    StudentFunnelQueryService,
    StudentFunnelRevisionService,
    StudentFunnelTransitionPolicy,
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
  // CrmAnalyticsSupportModule (policy/dashboard), LEAD_INTAKE_PORT (messenger),
  // and the other narrow contracts below are the only cross-module surface.
  exports: [
    CrmAnalyticsSupportModule,
    ClientReferenceService,
    ClientWriteValidator,
    LEAD_INTAKE_PORT,
    LESSON_SETTLEMENT_PORT,
    LessonCompletionWorker,
  ],
})
export class CrmModule {}
