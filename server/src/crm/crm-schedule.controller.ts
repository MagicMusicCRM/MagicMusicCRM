import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
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
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";
import {
  LessonCancelCommandDto,
  LessonCancelPreviewDto,
  LessonRescheduleCommandDto,
  LessonReschedulePreviewDto,
} from "./dto/lesson-transition.dto";
import { LessonCommandService } from "./schedule/lesson-command.service";
import { LessonSeriesCommandService } from "./schedule/lesson-series-command.service";
import { LessonTransitionService } from "./schedule/lesson-transition.service";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmScheduleController {
  constructor(
    private readonly schedule: ScheduleService,
    private readonly lessonCommands: LessonCommandService,
    private readonly lessonSeriesCommands: LessonSeriesCommandService,
    private readonly lessonTransitions: LessonTransitionService,
  ) {}

  @Get("schedule-series")
  listScheduleSeries(
    @CurrentActor() actor: ActorContext,
    @Query() query: ScheduleSeriesQuery,
  ) {
    return this.schedule.listScheduleSeries(actor, {
      clientType: query.clientType,
      clientId: query.clientId,
      studentId: query.studentId,
      groupId: query.groupId,
      includeExpired: query.includeExpired ?? false,
    });
  }

  @Post("schedule-series")
  createScheduleSeries(
    @CurrentActor() actor: ActorContext,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: CreateScheduleSeriesDto,
  ) {
    return this.lessonSeriesCommands.create(actor, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
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
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpsertLessonDto,
  ) {
    return this.lessonCommands.create(actor, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
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
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpsertLessonDto,
  ) {
    return this.lessonCommands.update(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("lessons/:id/reschedule/preview")
  previewLessonReschedule(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: LessonReschedulePreviewDto,
  ) {
    return this.lessonTransitions.previewReschedule(actor, id, dto);
  }

  @Post("lessons/:id/reschedule")
  rescheduleLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: LessonRescheduleCommandDto,
  ) {
    return this.lessonTransitions.reschedule(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("lessons/:id/cancel/preview")
  previewLessonCancel(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: LessonCancelPreviewDto,
  ) {
    return this.lessonTransitions.previewCancel(actor, id, dto);
  }

  @Post("lessons/:id/cancel")
  cancelLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: LessonCancelCommandDto,
  ) {
    return this.lessonTransitions.cancel(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Delete("lessons/:id")
  deleteLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.schedule.deleteLesson(actor, id);
  }
}
