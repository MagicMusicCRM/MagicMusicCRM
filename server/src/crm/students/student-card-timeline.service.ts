import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { ChatWorkTimelineService } from "../../messenger/chat-work-timeline.service";
import { toTimelineDto } from "../crm-mappers";
import { ScheduleReadService } from "../schedule/schedule-read.service";
import { SharedTaskService } from "../tasks/shared-task.service";
import { TimelineService } from "../timeline.service";
import { StudentDirectoryService } from "./student-directory.service";

@Injectable()
export class StudentCardTimelineService {
  constructor(
    private readonly database: DatabaseService,
    private readonly directory: StudentDirectoryService,
    private readonly scheduleRead: ScheduleReadService,
    private readonly tasks: SharedTaskService,
    private readonly timeline: TimelineService,
    private readonly chatWork: ChatWorkTimelineService,
  ) {}

  async getStudentCard(actor: ActorContext, studentId: string) {
    const student = await this.directory.getStudent(actor, studentId);
    const emptyList = { items: [] as never[] };
    const [groups, lessons, tasks, comments, links, chatWork, fieldAudit] =
      await Promise.all([
        this.directory.listStudentGroups(actor, studentId, { limit: 100 }),
        this.scheduleRead.listLessons(actor, { studentId, limit: 100 }),
        this.tasks.list(actor, {
          linkedEntityType: "student",
          linkedEntityId: studentId,
          limit: 100,
        }),
        this.timeline
          .listComments(actor, {
            entityType: "student",
            entityId: studentId,
            limit: 100,
          })
          .catch(() => emptyList),
        this.listUserCrmLinks("student", studentId),
        this.listChatWorkTimeline("student", studentId),
        this.timeline
          .listFieldAudit(actor, "student", studentId, 50)
          .catch(() => emptyList),
      ]);

    const combinedTimeline = [
      ...comments.items.map((comment) => ({
        id: comment.id,
        type: "comment",
        title: "Комментарий",
        body: comment.body,
        status: null,
        occurredAt: comment.createdAt,
      })),
      ...tasks.items.map((task) => ({
        id: task.id,
        type: "task",
        title: task.title,
        body: task.body,
        status: task.state,
        occurredAt: task.createdAt,
      })),
      ...lessons.items.map((lesson) => ({
        id: lesson.id,
        type: lesson.isTrial ? "trial" : "lesson",
        title: lesson.isTrial ? "Пробное занятие" : "Занятие",
        body: lesson.teacherName || lesson.roomName || null,
        status: lesson.status,
        occurredAt: lesson.scheduledAt,
      })),
      ...chatWork,
      ...fieldAudit.items.map((entry) => ({
        id: String(entry.id),
        type: "audit",
        title: String(entry.title),
        body: entry.body === null ? null : String(entry.body),
        status: null,
        occurredAt: entry.occurredAt,
      })),
    ].sort(
      (a, b) =>
        new Date(String(b.occurredAt)).getTime() -
        new Date(String(a.occurredAt)).getTime(),
    );

    return {
      student,
      groups: groups.items,
      lessons: lessons.items,
      tasks: tasks.items,
      comments: comments.items,
      links,
      timeline: combinedTimeline,
    };
  }

  private async listUserCrmLinks(entityType: string, entityId: string) {
    const result = await this.database.query<{
      id: string;
      user_id: string;
      email: string | null;
      phone: string | null;
      link_source: string;
      confirmed_at: Date | string | null;
      created_at: Date | string;
    }>(
      `
        select link.id, link.user_id, u.email, u.phone, link.link_source,
          link.confirmed_at, link.created_at
        from app.user_crm_links link
        join app.users u on u.id = link.user_id and u.deleted_at is null
        where link.deleted_at is null
          and link.entity_type = $1::app.crm_entity_type
          and link.entity_id = $2
        order by link.created_at desc, link.id desc
      `,
      [entityType, entityId],
    );
    return result.rows.map((row) => ({
      id: row.id,
      userId: row.user_id,
      email: row.email,
      phone: row.phone,
      linkSource: row.link_source,
      confirmedAt: row.confirmed_at,
      createdAt: row.created_at,
    }));
  }

  private async listChatWorkTimeline(
    entityType: "student" | "lead",
    entityId: string,
  ) {
    const rows = await this.chatWork.listForEntity(entityType, entityId);
    return rows.map((row) => toTimelineDto(row));
  }
}
