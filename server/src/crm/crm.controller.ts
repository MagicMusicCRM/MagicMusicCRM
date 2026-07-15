import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { CrmService } from "./crm.service";
import { HomeworkService } from "./homework.service";
import { ReferenceDataService } from "./reference-data.service";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { TasksService } from "./tasks.service";
import { AttendanceService } from "./attendance.service";
import { StaffService } from "./staff.service";
import { TeachersService } from "./teachers.service";
import { ScheduleService } from "./schedule.service";
import { RoomsService } from "./rooms.service";
import { BranchesService } from "./branches.service";
import { GroupsService } from "./groups.service";
import { PayrollService } from "./payroll.service";
import { ActivityLogQuery } from "./dto/activity-log.query";
import { CommentQuery } from "./dto/comment.query";
import { CreateAdjustmentDto } from "./dto/create-adjustment.dto";
import { CreateCommentDto } from "./dto/create-comment.dto";
import { SetCommentVisibilityDto } from "./dto/set-comment-visibility.dto";
import { CreatePaymentDto } from "./dto/create-payment.dto";
import {
  CreateScheduleSeriesDto,
  UpdateScheduleSeriesDto,
} from "./dto/schedule-series.dto";
import { ExpenseQuery } from "./dto/expense.query";
import { UpsertExpenseDto } from "./dto/upsert-expense.dto";
import { UpdateExpenseDto } from "./dto/update-expense.dto";
import { UpsertSubscriptionPackageDto } from "./dto/upsert-subscription-package.dto";
import { UpdateSubscriptionPackageDto } from "./dto/update-subscription-package.dto";
import { IssueSubscriptionDto } from "./dto/issue-subscription.dto";
import { CreateHomeworkDto } from "./dto/create-homework.dto";
import { UpdateHomeworkDto } from "./dto/update-homework.dto";
import { HomeworkQuery } from "./dto/homework.query";
import { AddHomeworkAttachmentDto } from "./dto/add-homework-attachment.dto";
import { CreateStaffDto } from "./dto/create-staff.dto";
import { CreateStudentDto } from "./dto/create-student.dto";
import { CreateTeacherDto } from "./dto/create-teacher.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { DuplicateCandidatesQuery } from "./dto/duplicate-candidates.query";
import { DuplicateDecisionDto } from "./dto/duplicate-decision.dto";
import { GroupStudentDto } from "./dto/group-student.dto";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { LessonQuery } from "./dto/lesson.query";
import { ManagerDashboardQuery } from "./dto/manager-dashboard.query";
import { PaymentQuery } from "./dto/payment.query";
import { ReportQuery } from "./dto/report.query";
import { RoomAvailabilityQuery } from "./dto/room-availability.query";
import { SaveContactFromChatDto } from "./dto/save-contact-from-chat.dto";
import { CreateBranchDto } from "./dto/create-branch.dto";
import { UpdateBranchDto } from "./dto/update-branch.dto";
import { ScheduleMatrixQuery } from "./dto/schedule-matrix.query";
import { StaffListQuery } from "./dto/staff-list.query";
import { StudentBalanceQuery } from "./dto/student-balance.query";
import { StudentSearchQuery } from "./dto/student-search.query";
import { TaskBoardQuery } from "./dto/task-board.query";
import { TeacherListQuery } from "./dto/teacher-list.query";
import { TimelineQuery } from "./dto/timeline.query";
import { UpdateStaffDto } from "./dto/update-staff.dto";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { UpdateTeacherDto } from "./dto/update-teacher.dto";
import { UpsertAttendanceDto } from "./dto/upsert-attendance.dto";
import { UpsertLeadDto } from "./dto/upsert-lead.dto";
import { UpsertLeadStatusDto } from "./dto/upsert-lead-status.dto";
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";
import { CreateDisciplineDto } from "./dto/create-discipline.dto";
import { CreateLossReasonDto } from "./dto/create-loss-reason.dto";
import { UpsertBranchDisciplineDto } from "./dto/upsert-branch-discipline.dto";
import { ReorderBranchDisciplinesDto } from "./dto/reorder-branch-disciplines.dto";
import { UpsertGroupDto } from "./dto/upsert-group.dto";
import { UpdateGroupDto } from "./dto/update-group.dto";
import { CreateTeacherPayoutDto } from "./dto/create-teacher-payout.dto";
import { SetTeacherRateDto } from "./dto/set-teacher-rate.dto";
import { TeacherStatsQuery } from "./dto/teacher-stats.query";
import { UpsertRoomDto } from "./dto/upsert-room.dto";
import { UpsertTaskDto } from "./dto/upsert-task.dto";
import { CreateFamilyDto } from "./dto/create-family.dto";
import { AddFamilyMemberDto } from "./dto/add-family-member.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmController {
  constructor(
    private readonly crm: CrmService,
    private readonly homework: HomeworkService,
    private readonly referenceData: ReferenceDataService,
    private readonly subscriptions: SubscriptionsService,
    private readonly finance: FinanceService,
    private readonly tasks: TasksService,
    private readonly attendance: AttendanceService,
    private readonly staff: StaffService,
    private readonly teachers: TeachersService,
    private readonly schedule: ScheduleService,
    private readonly rooms: RoomsService,
    private readonly branches: BranchesService,
    private readonly groups: GroupsService,
    private readonly payroll: PayrollService,
  ) {}

  @Get("me")
  getMe(@CurrentActor() actor: ActorContext) {
    return this.crm.getMySummary(actor);
  }

  @Get("overview")
  getOverview(@CurrentActor() actor: ActorContext) {
    return this.crm.getOverview(actor);
  }

  @Get("dashboard/manager")
  getManagerDashboard(
    @CurrentActor() actor: ActorContext,
    @Query() query: ManagerDashboardQuery,
  ) {
    return this.crm.getManagerDashboard(actor, query);
  }

  @Get("reports/finance")
  getFinanceReport(
    @CurrentActor() actor: ActorContext,
    @Query() query: ReportQuery,
  ) {
    return this.crm.getFinanceReport(actor, query);
  }

  @Get("students")
  listStudents(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listStudents(actor, query);
  }

  @Get("students/search")
  searchStudents(
    @CurrentActor() actor: ActorContext,
    @Query() query: StudentSearchQuery,
  ) {
    return this.crm.searchStudents(actor, query);
  }

  @Post("students")
  createStudent(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateStudentDto,
  ) {
    return this.crm.createStudent(actor, dto);
  }

  @Get("student-balances")
  listStudentBalances(
    @CurrentActor() actor: ActorContext,
    @Query() query: StudentBalanceQuery,
  ) {
    return this.finance.listStudentBalances(actor, query);
  }

  @Get("students/:id/groups")
  listStudentGroups(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listStudentGroups(actor, id, query);
  }

  @Get("students/:id/card")
  getStudentCard(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.getStudentCard(actor, id);
  }

  @Get("students/:id/ledger")
  listStudentLedger(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query("direction") direction?: string,
    @Query("limit") limit?: string,
  ) {
    return this.finance.listStudentLedger(actor, id, {
      direction,
      limit: limit ? Number(limit) : undefined,
    });
  }

  @Post("students/:id/adjustments")
  createAccountAdjustment(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CreateAdjustmentDto,
  ) {
    return this.finance.createAccountAdjustment(actor, id, dto);
  }

  @Get("schedule-series")
  listScheduleSeries(
    @CurrentActor() actor: ActorContext,
    @Query("studentId") studentId?: string,
    @Query("groupId") groupId?: string,
    @Query("includeExpired") includeExpired?: string,
  ) {
    return this.schedule.listScheduleSeries(actor, {
      studentId,
      groupId,
      includeExpired: includeExpired === "true",
    });
  }

  @Post("schedule-series")
  createScheduleSeries(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateScheduleSeriesDto,
  ) {
    return this.schedule.createScheduleSeries(actor, dto);
  }

  @Patch("schedule-series/:id")
  updateScheduleSeries(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateScheduleSeriesDto,
  ) {
    return this.schedule.updateScheduleSeries(actor, id, dto);
  }

  @Delete("schedule-series/:id")
  deleteScheduleSeries(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query("from") from?: string,
  ) {
    return this.schedule.deleteScheduleSeries(actor, id, from);
  }

  @Get("students/:id")
  getStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.getStudent(actor, id);
  }

  @Patch("students/:id")
  updateStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateStudentDto,
  ) {
    return this.crm.updateStudent(actor, id, dto);
  }

  @Delete("students/:id")
  deleteStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.deleteStudent(actor, id);
  }

  @Post("students/:id/return-to-lead")
  returnStudentToLead(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.returnStudentToLead(actor, id);
  }

  @Post("students/:id/invite")
  inviteStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.inviteStudent(actor, id);
  }

  @Get("duplicates")
  listDuplicateCandidates(
    @CurrentActor() actor: ActorContext,
    @Query() query: DuplicateCandidatesQuery,
  ) {
    return this.crm.listDuplicateCandidates(actor, query);
  }

  @Patch("duplicates/:id")
  decideDuplicateCandidate(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: DuplicateDecisionDto,
  ) {
    return this.crm.decideDuplicateCandidate(actor, id, dto);
  }

  @Get("activity")
  listActivityLog(
    @CurrentActor() actor: ActorContext,
    @Query() query: ActivityLogQuery,
  ) {
    return this.crm.listActivityLog(actor, query);
  }

  @Get("teachers")
  listTeachers(
    @CurrentActor() actor: ActorContext,
    @Query() query: TeacherListQuery,
  ) {
    return this.teachers.listTeachers(actor, query);
  }

  @Post("teachers")
  createTeacher(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateTeacherDto,
  ) {
    return this.teachers.createTeacher(actor, dto);
  }

  @Patch("teachers/:id")
  updateTeacher(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateTeacherDto,
  ) {
    return this.teachers.updateTeacher(actor, id, dto);
  }

  // ── KVA-238: зарплатный модуль педагогов ──────────────────────────────────

  @Get("teachers/:id/payroll")
  getTeacherPayroll(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.payroll.getTeacherPayroll(actor, id);
  }

  @Post("teachers/:id/payouts")
  createTeacherPayout(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CreateTeacherPayoutDto,
  ) {
    return this.payroll.createTeacherPayout(actor, id, dto);
  }

  @Post("teachers/:id/rates")
  setTeacherRate(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SetTeacherRateDto,
  ) {
    return this.payroll.setTeacherRate(actor, id, dto);
  }

  @Get("reports/teacher-stats")
  getTeacherStats(
    @CurrentActor() actor: ActorContext,
    @Query() query: TeacherStatsQuery,
  ) {
    return this.payroll.getTeacherStatsReport(actor, query);
  }

  @Get("staff")
  listStaff(
    @CurrentActor() actor: ActorContext,
    @Query() query: StaffListQuery,
  ) {
    return this.staff.listStaff(actor, query);
  }

  @Post("staff")
  createStaff(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateStaffDto,
  ) {
    return this.staff.createStaff(actor, dto);
  }

  @Patch("staff/:id")
  updateStaff(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateStaffDto,
  ) {
    return this.staff.updateStaff(actor, id, dto);
  }

  @Get("branches")
  listBranches(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.branches.listBranches(actor, query);
  }

  @Post("branches")
  createBranch(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateBranchDto,
  ) {
    return this.branches.createBranch(actor, dto);
  }

  @Patch("branches/:id")
  updateBranch(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateBranchDto,
  ) {
    return this.branches.updateBranch(actor, id, dto);
  }

  @Get("rooms")
  listRooms(@CurrentActor() actor: ActorContext, @Query() query: CrmListQuery) {
    return this.rooms.listRooms(actor, query);
  }

  @Get("rooms/availability")
  listRoomAvailability(
    @CurrentActor() actor: ActorContext,
    @Query() query: RoomAvailabilityQuery,
  ) {
    return this.rooms.listRoomAvailability(actor, query);
  }

  @Post("rooms")
  createRoom(@CurrentActor() actor: ActorContext, @Body() dto: UpsertRoomDto) {
    return this.rooms.createRoom(actor, dto);
  }

  @Patch("rooms/:id")
  updateRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertRoomDto,
  ) {
    return this.rooms.updateRoom(actor, id, dto);
  }

  @Delete("rooms/:id")
  deleteRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.rooms.deleteRoom(actor, id);
  }

  @Get("groups")
  listGroups(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.groups.listGroups(actor, query);
  }

  @Post("groups")
  createGroup(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertGroupDto,
  ) {
    return this.groups.createGroup(actor, dto);
  }

  // KVA-238: PATCH группы (в т.ч. ставка педагога из drill-down отчёта).
  @Patch("groups/:id")
  updateGroup(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateGroupDto,
  ) {
    return this.groups.updateGroup(actor, id, dto);
  }

  @Get("groups/:id/students")
  listGroupStudents(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listGroupStudents(actor, id, query);
  }

  @Post("groups/:id/students")
  addGroupStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: GroupStudentDto,
  ) {
    return this.groups.addGroupStudent(actor, id, dto.studentId);
  }

  @Delete("groups/:id/students/:studentId")
  removeGroupStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("studentId", ParseUUIDPipe) studentId: string,
  ) {
    return this.groups.removeGroupStudent(actor, id, studentId);
  }

  @Get("lead-statuses")
  listLeadStatuses(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.referenceData.listLeadStatuses(actor, query);
  }

  @Get("loss-reasons")
  listLossReasons(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listLossReasons(actor);
  }

  @Get("lead-sources")
  listLeadSources(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listLeadSources(actor);
  }

  @Get("disciplines")
  listDisciplines(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listDisciplines(actor);
  }

  @Get("branches/:branchId/disciplines")
  listBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
  ) {
    return this.referenceData.listBranchDisciplines(actor, branchId);
  }

  @Post("disciplines")
  createDiscipline(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateDisciplineDto,
  ) {
    return this.referenceData.createDiscipline(actor, dto);
  }

  @Post("loss-reasons")
  createLossReason(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateLossReasonDto,
  ) {
    return this.referenceData.createLossReason(actor, dto);
  }

  @Post("branches/:branchId/disciplines")
  assignBranchDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Body() dto: UpsertBranchDisciplineDto,
  ) {
    return this.referenceData.assignBranchDiscipline(actor, branchId, dto);
  }

  @Patch("branches/:branchId/disciplines/order")
  reorderBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Body() dto: ReorderBranchDisciplinesDto,
  ) {
    return this.referenceData.reorderBranchDisciplines(actor, branchId, dto);
  }

  @Get("hollihop/disciplines")
  listHolliHopDisciplines(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopDisciplines(actor);
  }

  @Get("hollihop/levels")
  listHolliHopLevels(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopLevels(actor);
  }

  @Get("hollihop/categories")
  listHolliHopCategories(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopCategories(actor);
  }

  @Get("hollihop/lead-statuses")
  listHolliHopLeadStatuses(@CurrentActor() actor: ActorContext) {
    return this.referenceData.listHolliHopLeadStatuses(actor);
  }

  @Post("lead-statuses")
  createLeadStatus(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertLeadStatusDto,
  ) {
    return this.referenceData.createLeadStatus(actor, dto);
  }

  @Patch("lead-statuses/order")
  reorderLeadStatuses(
    @CurrentActor() actor: ActorContext,
    @Body() dto: { statusIds: string[] },
  ) {
    return this.referenceData.reorderLeadStatuses(actor, dto);
  }

  @Delete("lead-statuses/:id")
  deleteLeadStatus(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.referenceData.deleteLeadStatus(actor, id);
  }

  @Get("lessons")
  listLessons(
    @CurrentActor() actor: ActorContext,
    @Query() query: LessonQuery,
  ) {
    return this.schedule.listLessons(actor, query);
  }

  @Get("schedule/matrix")
  getScheduleMatrix(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleMatrixQuery,
  ) {
    return this.schedule.getScheduleMatrix(actor, query);
  }

  @Get("schedule/month-summary")
  getScheduleMonthSummary(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleMatrixQuery,
  ) {
    return this.schedule.getScheduleMonthSummary(actor, query);
  }

  @Post("lessons")
  createLesson(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertLessonDto,
  ) {
    return this.schedule.createLesson(actor, dto);
  }

  @Patch("lessons/:id")
  updateLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertLessonDto,
  ) {
    return this.schedule.updateLesson(actor, id, dto);
  }

  @Delete("lessons/:id")
  deleteLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.schedule.deleteLesson(actor, id);
  }

  @Get("lessons/:id/attendance")
  getLessonAttendance(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.attendance.getLessonAttendance(actor, id);
  }

  @Patch("lessons/:id/attendance")
  upsertLessonAttendance(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertAttendanceDto,
  ) {
    return this.attendance.upsertLessonAttendance(actor, id, dto);
  }

  @Get("tasks")
  listTasks(
    @CurrentActor() actor: ActorContext,
    @Query() query: TaskBoardQuery,
  ) {
    return this.tasks.listTasks(actor, query);
  }

  @Get("timeline")
  listTimeline(
    @CurrentActor() actor: ActorContext,
    @Query() query: TimelineQuery,
  ) {
    return this.crm.listTimeline(actor, query);
  }

  @Get("comments")
  listComments(
    @CurrentActor() actor: ActorContext,
    @Query() query: CommentQuery,
  ) {
    return this.crm.listComments(actor, query);
  }

  @Post("comments")
  createComment(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateCommentDto,
  ) {
    return this.crm.createComment(actor, dto);
  }

  @Patch("comments/:id/visibility")
  setCommentVisibility(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SetCommentVisibilityDto,
  ) {
    return this.crm.setCommentVisibility(actor, id, dto.visibleToTeacher);
  }

  @Post("tasks")
  createTask(@CurrentActor() actor: ActorContext, @Body() dto: UpsertTaskDto) {
    return this.tasks.createTask(actor, dto);
  }

  @Patch("tasks/:id")
  updateTask(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertTaskDto,
  ) {
    return this.tasks.updateTask(actor, id, dto);
  }

  @Get("payments")
  listPayments(
    @CurrentActor() actor: ActorContext,
    @Query() query: PaymentQuery,
  ) {
    return this.finance.listPayments(actor, query);
  }

  @Get("expected-payments")
  listExpectedPayments(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.finance.listExpectedPayments(actor, query);
  }

  @Get("subscriptions")
  listSubscriptions(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.subscriptions.listSubscriptions(actor, query);
  }

  @Post("payments")
  createPayment(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreatePaymentDto,
  ) {
    return this.finance.createPayment(actor, dto);
  }

  @Get("expenses")
  listExpenses(
    @CurrentActor() actor: ActorContext,
    @Query() query: ExpenseQuery,
  ) {
    return this.finance.listExpenses(actor, query);
  }

  @Post("expenses")
  createExpense(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertExpenseDto,
  ) {
    return this.finance.createExpense(actor, dto);
  }

  @Patch("expenses/:id")
  updateExpense(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateExpenseDto,
  ) {
    return this.finance.updateExpense(actor, id, dto);
  }

  @Delete("expenses/:id")
  deleteExpense(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.finance.deleteExpense(actor, id);
  }

  @Get("subscription-packages")
  listSubscriptionPackages(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.subscriptions.listSubscriptionPackages(actor, query);
  }

  @Post("subscription-packages")
  createSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertSubscriptionPackageDto,
  ) {
    return this.subscriptions.createSubscriptionPackage(actor, dto);
  }

  @Patch("subscription-packages/:id")
  updateSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateSubscriptionPackageDto,
  ) {
    return this.subscriptions.updateSubscriptionPackage(actor, id, dto);
  }

  @Delete("subscription-packages/:id")
  deleteSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.subscriptions.deleteSubscriptionPackage(actor, id);
  }

  @Post("students/:id/subscriptions/issue")
  issueSubscription(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: IssueSubscriptionDto,
  ) {
    return this.subscriptions.issueSubscription(actor, id, dto);
  }

  @Get("homeworks")
  listHomeworks(
    @CurrentActor() actor: ActorContext,
    @Query() query: HomeworkQuery,
  ) {
    return this.homework.listHomeworks(actor, query);
  }

  @Post("homeworks")
  createHomework(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateHomeworkDto,
  ) {
    return this.homework.createHomework(actor, dto);
  }

  @Patch("homeworks/:id")
  updateHomework(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateHomeworkDto,
  ) {
    return this.homework.updateHomework(actor, id, dto);
  }

  @Post("homeworks/:id/submit")
  submitHomework(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.homework.submitHomework(actor, id);
  }

  @Post("homeworks/:id/attachments")
  addHomeworkAttachment(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: AddHomeworkAttachmentDto,
  ) {
    return this.homework.addHomeworkAttachment(actor, id, dto);
  }

  @Get("leads")
  listLeads(@CurrentActor() actor: ActorContext, @Query() query: CrmListQuery) {
    return this.crm.listLeads(actor, query);
  }

  @Get("leads/board")
  listLeadBoard(
    @CurrentActor() actor: ActorContext,
    @Query() query: LeadBoardQuery,
  ) {
    return this.crm.listLeadBoard(actor, query);
  }

  @Get("leads/app-count")
  countAppLeads(@CurrentActor() actor: ActorContext) {
    return this.crm.countAppLeads(actor);
  }

  @Get("leads/:id/card")
  getLeadCard(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.getLeadCard(actor, id);
  }

  // KVA-234: заявки лида (app.lead_applications) — секция «Заявки» в карточке.
  @Get("leads/:id/applications")
  listLeadApplications(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.listLeadApplications(actor, id);
  }

  @Get("leads/:leadId/status-history")
  listLeadStatusHistory(
    @CurrentActor() actor: ActorContext,
    @Param("leadId", ParseUUIDPipe) leadId: string,
  ) {
    return this.crm.listLeadStatusHistory(actor, leadId);
  }

  @Get("leads/:id/chat-user")
  resolveLeadChatUser(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.resolveLeadChatUser(actor, id);
  }

  @Get("contacts/by-user/:userId")
  resolveContactForUser(
    @CurrentActor() actor: ActorContext,
    @Param("userId", ParseUUIDPipe) userId: string,
  ) {
    return this.crm.resolveContactForUser(actor, userId);
  }

  @Post("contacts/save-from-chat")
  saveContactFromChat(
    @CurrentActor() actor: ActorContext,
    @Body() dto: SaveContactFromChatDto,
  ) {
    return this.crm.saveContactFromChat(actor, dto);
  }

  @Post("leads")
  createLead(@CurrentActor() actor: ActorContext, @Body() dto: UpsertLeadDto) {
    return this.crm.createLead(actor, dto);
  }

  @Patch("leads/:id")
  updateLead(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertLeadDto,
  ) {
    return this.crm.updateLead(actor, id, dto);
  }

  @Delete("leads/:id")
  deleteLead(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.deleteLead(actor, id);
  }

  @Get("phone-review-queue/count")
  countPhoneReviewQueue(@CurrentActor() actor: ActorContext) {
    return this.crm.countPhoneReviewQueue(actor);
  }

  @Get("phone-review-queue")
  listPhoneReviewQueue(
    @CurrentActor() actor: ActorContext,
    @Query("limit") limit?: string,
  ) {
    return this.crm.listPhoneReviewQueue(actor, limit ? Number(limit) : undefined);
  }

  @Post("families")
  createFamily(@CurrentActor() actor: ActorContext, @Body() dto: CreateFamilyDto) {
    return this.crm.createFamily(actor, dto);
  }

  @Post("families/:familyId/members")
  addFamilyMember(
    @CurrentActor() actor: ActorContext,
    @Param("familyId", ParseUUIDPipe) familyId: string,
    @Body() dto: AddFamilyMemberDto,
  ) {
    return this.crm.addFamilyMember(actor, familyId, dto);
  }

  @Get("families/by-entity/:entityType/:entityId")
  getFamilyForEntity(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
  ) {
    return this.crm.getFamilyForEntity(actor, entityType, entityId);
  }

  @Delete("family-members/:memberId")
  removeFamilyMember(
    @CurrentActor() actor: ActorContext,
    @Param("memberId", ParseUUIDPipe) memberId: string,
  ) {
    return this.crm.removeFamilyMember(actor, memberId);
  }

  @Post("families/:familyId/primary-payer/:memberId")
  setPrimaryPayer(
    @CurrentActor() actor: ActorContext,
    @Param("familyId", ParseUUIDPipe) familyId: string,
    @Param("memberId", ParseUUIDPipe) memberId: string,
  ) {
    return this.crm.setPrimaryPayer(actor, familyId, memberId);
  }

  @Get("merge-candidates")
  listMergeCandidates(
    @CurrentActor() actor: ActorContext,
    @Query("limit") limit?: string,
  ) {
    return this.crm.listMergeCandidates(actor, limit ? Number(limit) : undefined);
  }

  @Post("leads/:winnerId/merge/:loserId")
  mergeLeads(
    @CurrentActor() actor: ActorContext,
    @Param("winnerId", ParseUUIDPipe) winnerId: string,
    @Param("loserId", ParseUUIDPipe) loserId: string,
  ) {
    return this.crm.mergeLeads(actor, loserId, winnerId);
  }

  @Post("merges/:mergeLogId/undo")
  undoMerge(
    @CurrentActor() actor: ActorContext,
    @Param("mergeLogId", ParseUUIDPipe) mergeLogId: string,
  ) {
    return this.crm.undoMerge(actor, mergeLogId);
  }

  @Get("clients/:entityType/:entityId/linked-users")
  getClientLinkedUsers(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
  ) {
    return this.crm.getClientLinkedUsers(actor, entityType, entityId);
  }

  @Get("clients/:entityType/:entityId/user-candidates")
  listClientUserCandidates(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
  ) {
    return this.crm.listClientUserCandidates(actor, entityType, entityId);
  }

  @Post("clients/:entityType/:entityId/link-user")
  linkUserToClient(
    @CurrentActor() actor: ActorContext,
    @Param("entityType") entityType: string,
    @Param("entityId", ParseUUIDPipe) entityId: string,
    @Body() dto: { userId: string },
  ) {
    return this.crm.linkUserToClient(actor, entityType, entityId, dto.userId);
  }
}
