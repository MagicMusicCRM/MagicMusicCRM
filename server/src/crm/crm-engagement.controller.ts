import {
  BadRequestException,
  Body,
  Controller,
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
import { HomeworkService } from "./homework.service";
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
import { TimelineQuery } from "./dto/timeline.query";
import { CommentSharingService } from "./clients/comment-sharing.service";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmEngagementController {
  constructor(
    private readonly homework: HomeworkService,
    private readonly timeline: TimelineService,
    private readonly sectionViews: SectionViewsService,
    private readonly commentSharing: CommentSharingService,
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
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: SetCommentVisibilityDto,
  ) {
    const sharedWithTeacher =
      dto.sharedWithTeacher ?? dto.visibleToTeacher;
    if (sharedWithTeacher === undefined) {
      throw new BadRequestException(
        "sharedWithTeacher or visibleToTeacher is required.",
      );
    }
    const effectiveRequestId = requestId ?? "";
    return this.commentSharing.setTeacherSharing(actor, {
      commentId: id,
      sharedWithTeacher,
      expectedVersion: dto.expectedVersion,
      reasonCode: dto.reasonCode ?? "crm.comment.teacher-sharing",
      requestId: effectiveRequestId,
      idempotencyKey: idempotencyKey ?? `request:${effectiveRequestId}`,
    });
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
