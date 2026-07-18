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
import { AttendanceService } from "./attendance.service";
import { ScheduleService } from "./schedule.service";
import { BulkLessonRateDto } from "./dto/bulk-lesson-rate.dto";
import {
  CreateScheduleSeriesDto,
  UpdateScheduleSeriesDto,
} from "./dto/schedule-series.dto";
import { LessonQuery } from "./dto/lesson.query";
import { ScheduleConflictsQuery } from "./dto/schedule-conflicts.query";
import { ScheduleMatrixQuery } from "./dto/schedule-matrix.query";
import {
  ScheduleSeriesDeleteQuery,
  ScheduleSeriesQuery,
} from "./dto/schedule-series.query";
import { UpsertAttendanceDto } from "./dto/upsert-attendance.dto";
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmScheduleController {
  constructor(
    private readonly attendance: AttendanceService,
    private readonly schedule: ScheduleService,
  ) {}

  @Get("schedule-series")
  listScheduleSeries(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleSeriesQuery,
  ) {
    return this.schedule.listScheduleSeries(actor, {
      studentId: query.studentId,
      groupId: query.groupId,
      includeExpired: query.includeExpired ?? false,
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
    @Query() query: ScheduleSeriesDeleteQuery,
  ) {
    return this.schedule.deleteScheduleSeries(actor, id, query.from);
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

  // Contract 1 (правки №2): busy-slot pre-flight for the lesson dialog.
  @Get("schedule/conflicts")
  getScheduleConflicts(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleConflictsQuery,
  ) {
    return this.schedule.getScheduleConflicts(actor, query);
  }

  @Post("lessons")
  createLesson(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertLessonDto,
  ) {
    return this.schedule.createLesson(actor, dto);
  }

  // Registered before "lessons/:id" so the literal segment wins the match and
  // "teacher-rate" is never parsed as a lesson id.
  @Patch("lessons/teacher-rate")
  setLessonsTeacherRate(
    @CurrentActor() actor: ActorContext,
    @Body() dto: BulkLessonRateDto,
  ) {
    return this.schedule.setLessonsTeacherRate(actor, dto);
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
}
