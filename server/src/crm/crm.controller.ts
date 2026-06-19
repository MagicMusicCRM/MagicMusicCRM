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
import { ActivityLogQuery } from "./dto/activity-log.query";
import { CommentQuery } from "./dto/comment.query";
import { CreateCommentDto } from "./dto/create-comment.dto";
import { CreatePaymentDto } from "./dto/create-payment.dto";
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
import { UpsertRoomDto } from "./dto/upsert-room.dto";
import { UpsertTaskDto } from "./dto/upsert-task.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmController {
  constructor(private readonly crm: CrmService) {}

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
    return this.crm.listStudentBalances(actor, query);
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
    return this.crm.listTeachers(actor, query);
  }

  @Post("teachers")
  createTeacher(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateTeacherDto,
  ) {
    return this.crm.createTeacher(actor, dto);
  }

  @Patch("teachers/:id")
  updateTeacher(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateTeacherDto,
  ) {
    return this.crm.updateTeacher(actor, id, dto);
  }

  @Get("staff")
  listStaff(
    @CurrentActor() actor: ActorContext,
    @Query() query: StaffListQuery,
  ) {
    return this.crm.listStaff(actor, query);
  }

  @Post("staff")
  createStaff(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateStaffDto,
  ) {
    return this.crm.createStaff(actor, dto);
  }

  @Patch("staff/:id")
  updateStaff(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateStaffDto,
  ) {
    return this.crm.updateStaff(actor, id, dto);
  }

  @Get("branches")
  listBranches(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listBranches(actor, query);
  }

  @Patch("branches/:id")
  updateBranch(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateBranchDto,
  ) {
    return this.crm.updateBranch(actor, id, dto);
  }

  @Get("rooms")
  listRooms(@CurrentActor() actor: ActorContext, @Query() query: CrmListQuery) {
    return this.crm.listRooms(actor, query);
  }

  @Get("rooms/availability")
  listRoomAvailability(
    @CurrentActor() actor: ActorContext,
    @Query() query: RoomAvailabilityQuery,
  ) {
    return this.crm.listRoomAvailability(actor, query);
  }

  @Post("rooms")
  createRoom(@CurrentActor() actor: ActorContext, @Body() dto: UpsertRoomDto) {
    return this.crm.createRoom(actor, dto);
  }

  @Patch("rooms/:id")
  updateRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertRoomDto,
  ) {
    return this.crm.updateRoom(actor, id, dto);
  }

  @Delete("rooms/:id")
  deleteRoom(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.deleteRoom(actor, id);
  }

  @Get("groups")
  listGroups(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listGroups(actor, query);
  }

  @Post("groups")
  createGroup(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertGroupDto,
  ) {
    return this.crm.createGroup(actor, dto);
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
    return this.crm.addGroupStudent(actor, id, dto.studentId);
  }

  @Delete("groups/:id/students/:studentId")
  removeGroupStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("studentId", ParseUUIDPipe) studentId: string,
  ) {
    return this.crm.removeGroupStudent(actor, id, studentId);
  }

  @Get("lead-statuses")
  listLeadStatuses(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listLeadStatuses(actor, query);
  }

  @Get("loss-reasons")
  listLossReasons(@CurrentActor() actor: ActorContext) {
    return this.crm.listLossReasons(actor);
  }

  @Get("lead-sources")
  listLeadSources(@CurrentActor() actor: ActorContext) {
    return this.crm.listLeadSources(actor);
  }

  @Get("disciplines")
  listDisciplines(@CurrentActor() actor: ActorContext) {
    return this.crm.listDisciplines(actor);
  }

  @Get("branches/:branchId/disciplines")
  listBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
  ) {
    return this.crm.listBranchDisciplines(actor, branchId);
  }

  @Post("disciplines")
  createDiscipline(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateDisciplineDto,
  ) {
    return this.crm.createDiscipline(actor, dto);
  }

  @Post("loss-reasons")
  createLossReason(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateLossReasonDto,
  ) {
    return this.crm.createLossReason(actor, dto);
  }

  @Post("branches/:branchId/disciplines")
  assignBranchDiscipline(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Body() dto: UpsertBranchDisciplineDto,
  ) {
    return this.crm.assignBranchDiscipline(actor, branchId, dto);
  }

  @Patch("branches/:branchId/disciplines/order")
  reorderBranchDisciplines(
    @CurrentActor() actor: ActorContext,
    @Param("branchId", ParseUUIDPipe) branchId: string,
    @Body() dto: ReorderBranchDisciplinesDto,
  ) {
    return this.crm.reorderBranchDisciplines(actor, branchId, dto);
  }

  @Get("hollihop/disciplines")
  listHolliHopDisciplines(@CurrentActor() actor: ActorContext) {
    return this.crm.listHolliHopDisciplines(actor);
  }

  @Get("hollihop/levels")
  listHolliHopLevels(@CurrentActor() actor: ActorContext) {
    return this.crm.listHolliHopLevels(actor);
  }

  @Get("hollihop/categories")
  listHolliHopCategories(@CurrentActor() actor: ActorContext) {
    return this.crm.listHolliHopCategories(actor);
  }

  @Get("hollihop/lead-statuses")
  listHolliHopLeadStatuses(@CurrentActor() actor: ActorContext) {
    return this.crm.listHolliHopLeadStatuses(actor);
  }

  @Post("lead-statuses")
  createLeadStatus(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertLeadStatusDto,
  ) {
    return this.crm.createLeadStatus(actor, dto);
  }

  @Delete("lead-statuses/:id")
  deleteLeadStatus(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.deleteLeadStatus(actor, id);
  }

  @Get("lessons")
  listLessons(
    @CurrentActor() actor: ActorContext,
    @Query() query: LessonQuery,
  ) {
    return this.crm.listLessons(actor, query);
  }

  @Get("schedule/matrix")
  getScheduleMatrix(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleMatrixQuery,
  ) {
    return this.crm.getScheduleMatrix(actor, query);
  }

  @Get("schedule/month-summary")
  getScheduleMonthSummary(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleMatrixQuery,
  ) {
    return this.crm.getScheduleMonthSummary(actor, query);
  }

  @Post("lessons")
  createLesson(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertLessonDto,
  ) {
    return this.crm.createLesson(actor, dto);
  }

  @Patch("lessons/:id")
  updateLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertLessonDto,
  ) {
    return this.crm.updateLesson(actor, id, dto);
  }

  @Delete("lessons/:id")
  deleteLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.deleteLesson(actor, id);
  }

  @Get("lessons/:id/attendance")
  getLessonAttendance(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.getLessonAttendance(actor, id);
  }

  @Patch("lessons/:id/attendance")
  upsertLessonAttendance(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertAttendanceDto,
  ) {
    return this.crm.upsertLessonAttendance(actor, id, dto);
  }

  @Get("tasks")
  listTasks(
    @CurrentActor() actor: ActorContext,
    @Query() query: TaskBoardQuery,
  ) {
    return this.crm.listTasks(actor, query);
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

  @Post("tasks")
  createTask(@CurrentActor() actor: ActorContext, @Body() dto: UpsertTaskDto) {
    return this.crm.createTask(actor, dto);
  }

  @Patch("tasks/:id")
  updateTask(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpsertTaskDto,
  ) {
    return this.crm.updateTask(actor, id, dto);
  }

  @Get("payments")
  listPayments(
    @CurrentActor() actor: ActorContext,
    @Query() query: PaymentQuery,
  ) {
    return this.crm.listPayments(actor, query);
  }

  @Get("expected-payments")
  listExpectedPayments(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listExpectedPayments(actor, query);
  }

  @Get("subscriptions")
  listSubscriptions(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listSubscriptions(actor, query);
  }

  @Post("payments")
  createPayment(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreatePaymentDto,
  ) {
    return this.crm.createPayment(actor, dto);
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

  @Get("leads/:id/card")
  getLeadCard(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.getLeadCard(actor, id);
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
}
