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
import { HomeworkService } from "./homework.service";
import { TasksService } from "./tasks.service";
import { SectionViewsService } from "./section-views.service";
import { TimelineService } from "./timeline.service";
import { CommentQuery } from "./dto/comment.query";
import { MarkSectionSeenDto } from "./dto/mark-section-seen.dto";
import { CreateCommentDto } from "./dto/create-comment.dto";
import { SetCommentVisibilityDto } from "./dto/set-comment-visibility.dto";
import { CreateHomeworkDto } from "./dto/create-homework.dto";
import { UpdateHomeworkDto } from "./dto/update-homework.dto";
import { HomeworkQuery } from "./dto/homework.query";
import { AddHomeworkAttachmentDto } from "./dto/add-homework-attachment.dto";
import { TaskBoardQuery } from "./dto/task-board.query";
import { TaskHistoryQuery } from "./dto/task-history.query";
import { TimelineQuery } from "./dto/timeline.query";
import { UpsertTaskDto } from "./dto/upsert-task.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmEngagementController {
  constructor(
    private readonly homework: HomeworkService,
    private readonly tasks: TasksService,
    private readonly timeline: TimelineService,
    private readonly sectionViews: SectionViewsService,
  ) {}

  /**
   * Счётчики непросмотренного на вкладках CRM.
   *
   * ✔ Заказчик 17.07: «счётчик непрочитанных/непросмотренных изменений» по
   * разделам. «Чата» здесь нет намеренно: у него непрочитанные считаются точно,
   * по факту прочтения каждого сообщения (messenger), — подменять их
   * приблизительным «когда я заглядывал» значило бы ухудшить работающее.
   */
  @Get("sections/unseen")
  unseenSections(@CurrentActor() actor: ActorContext) {
    return this.sectionViews.unseenCounts(actor);
  }

  /** «Я открыл раздел» — обнуляет его счётчик. */
  @Post("sections/seen")
  markSectionSeen(
    @CurrentActor() actor: ActorContext,
    @Body() dto: MarkSectionSeenDto,
  ) {
    return this.sectionViews.markSeen(actor, dto.section);
  }

  @Get("tasks")
  listTasks(
    @CurrentActor() actor: ActorContext,
    @Query() query: TaskBoardQuery,
  ) {
    return this.tasks.listTasks(actor, query);
  }

  // Literal segment, registered before "tasks/:id" so «calendar» is never
  // parsed as a task id. Per-day counts for the month/year calendar grids.
  @Get("tasks/calendar")
  taskCalendar(
    @CurrentActor() actor: ActorContext,
    @Query() query: TaskBoardQuery,
  ) {
    return this.tasks.taskCalendar(actor, query);
  }

  // Registered before "tasks/:id/history" so the literal segment wins the match
  // and "history" is never parsed as a task id.
  @Get("tasks/history")
  listTaskHistoryFeed(
    @CurrentActor() actor: ActorContext,
    @Query() query: TaskHistoryQuery,
  ) {
    return this.tasks.listTaskHistoryFeed(actor, query);
  }

  @Get("tasks/:id/history")
  listTaskHistory(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.tasks.listTaskHistory(actor, id);
  }

  @Get("timeline")
  listTimeline(
    @CurrentActor() actor: ActorContext,
    @Query() query: TimelineQuery,
  ) {
    return this.timeline.listTimeline(actor, query);
  }

  @Get("comments")
  listComments(
    @CurrentActor() actor: ActorContext,
    @Query() query: CommentQuery,
  ) {
    return this.timeline.listComments(actor, query);
  }

  @Post("comments")
  createComment(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateCommentDto,
  ) {
    return this.timeline.createComment(actor, dto);
  }

  @Patch("comments/:id/visibility")
  setCommentVisibility(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SetCommentVisibilityDto,
  ) {
    return this.timeline.setCommentVisibility(actor, id, dto.visibleToTeacher);
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

  @Delete("tasks/:id")
  deleteTask(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.tasks.deleteTask(actor, id);
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
}
