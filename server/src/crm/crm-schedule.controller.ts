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
import { LessonConstraintPreviewDto } from "./dto/lesson-constraint-preview.dto";
import {
  LessonBulkTransitionCommandDto,
  LessonBulkTransitionPreviewDto,
  LessonCancelCommandDto,
  LessonCancelPreviewDto,
  LessonRescheduleCommandDto,
  LessonReschedulePreviewDto,
  LessonSettleCommandDto,
  LessonSettlePreviewDto,
} from "./dto/lesson-transition.dto";
import { LessonCommandService } from "./schedule/lesson-command.service";
import { LessonSeriesCommandService } from "./schedule/lesson-series-command.service";
import { LessonTransitionService } from "./schedule/lesson-transition.service";
import { V4DomainFlagsService } from "../platform/v4-domain-flags";
import { assertLessonPatchUsesTransition } from "./schedule/lesson-protected-patch.guard";
import {
  CreateSchedulePlanDto,
  SchedulePlanEndCommandDto,
  SchedulePlanEndPreviewDto,
  SchedulePlanQuery,
  SchedulePlanTrayQuery,
  UpdateSchedulePlanDto,
} from "./dto/schedule-plan.dto";
import { SchedulePlanService } from "./schedule/schedule-plan.service";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmScheduleController {
  constructor(
    private readonly schedule: ScheduleService,
    private readonly lessonCommands: LessonCommandService,
    private readonly lessonSeriesCommands: LessonSeriesCommandService,
    private readonly lessonTransitions: LessonTransitionService,
    private readonly v4DomainFlags: V4DomainFlagsService,
    private readonly schedulePlans: SchedulePlanService,
  ) {}

  @Get("schedule-plans")
  listSchedulePlans(
    @CurrentActor() actor: ActorContext,
    @Query() query: SchedulePlanQuery,
  ) {
    return this.schedulePlans.list(actor, query);
  }

  @Post("schedule-plans")
  createSchedulePlan(
    @CurrentActor() actor: ActorContext,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: CreateSchedulePlanDto,
  ) {
    return this.schedulePlans.create(actor, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("schedule-plans/:id/end/preview")
  previewSchedulePlanEnd(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SchedulePlanEndPreviewDto,
  ) {
    return this.schedulePlans.previewEnd(actor, id, dto);
  }

  @Post("schedule-plans/:id/end")
  endSchedulePlan(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: SchedulePlanEndCommandDto,
  ) {
    return this.schedulePlans.end(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Get("schedule-plans/:id/tray")
  schedulePlanTray(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: SchedulePlanTrayQuery,
  ) {
    return this.schedulePlans.tray(actor, id, query);
  }

  @Patch("schedule-plans/:id")
  updateSchedulePlan(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpdateSchedulePlanDto,
  ) {
    return this.schedulePlans.update(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

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
    assertLessonPatchUsesTransition(dto);
    const metadata = {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    };
    return this.v4DomainFlags.get("schedule").effectivePath === "v4"
      ? this.lessonSeriesCommands.create(actor, dto, metadata)
      : this.schedule.createScheduleSeries(actor, dto);
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
    const metadata = {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    };
    return this.v4DomainFlags.get("schedule").effectivePath === "v4"
      ? this.lessonCommands.create(actor, dto, metadata)
      : this.schedule.createLesson(actor, dto);
  }

  @Post("lessons/constraints/preview")
  previewLessonConstraints(
    @CurrentActor() actor: ActorContext,
    @Body() dto: LessonConstraintPreviewDto,
  ) {
    return this.lessonCommands.previewConstraints(actor, dto);
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
    const metadata = {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    };
    return this.v4DomainFlags.get("schedule").effectivePath === "v4"
      ? this.lessonCommands.update(actor, id, dto, metadata)
      : this.schedule.updateLesson(actor, id, dto);
  }

  @Post("lessons/transitions/bulk/preview")
  previewBulkLessonTransitions(
    @CurrentActor() actor: ActorContext,
    @Body() dto: LessonBulkTransitionPreviewDto,
  ) {
    this.v4DomainFlags.assertEnabled("schedule");
    return this.lessonTransitions.previewBulk(actor, dto);
  }

  @Post("lessons/transitions/bulk")
  bulkLessonTransitions(
    @CurrentActor() actor: ActorContext,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: LessonBulkTransitionCommandDto,
  ) {
    this.v4DomainFlags.assertEnabled("schedule");
    return this.lessonTransitions.bulk(actor, dto, {
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
    this.v4DomainFlags.assertEnabled("schedule");
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
    this.v4DomainFlags.assertEnabled("schedule");
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
    this.v4DomainFlags.assertEnabled("schedule");
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
    this.v4DomainFlags.assertEnabled("schedule");
    return this.lessonTransitions.cancel(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("lessons/:id/settle/preview")
  previewLessonSettlement(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: LessonSettlePreviewDto,
  ) {
    this.v4DomainFlags.assertEnabled("schedule");
    return this.lessonTransitions.previewSettle(actor, id, dto);
  }

  @Post("lessons/:id/settle")
  settleLesson(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: LessonSettleCommandDto,
  ) {
    this.v4DomainFlags.assertEnabled("schedule");
    return this.lessonTransitions.settle(actor, id, dto, {
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
