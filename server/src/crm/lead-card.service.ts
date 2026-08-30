import { Injectable, NotFoundException } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { ChatWorkTimelineService } from "../messenger/chat-work-timeline.service";
import { branchIdExpr } from "./branch-scope";
import { readTypedClientValueMap } from "./clients/client-config.repository";
import { CrmPolicy } from "./crm.policy";
import { LessonRow, toLessonDto, toTimelineDto } from "./crm-mappers";
import {
  CommentRow,
  LeadBoardRow,
  LeadRow,
  toCommentDto,
  toLeadBoardItemDto,
  toLeadDto,
  toStudentDto,
} from "./lead-model";
import { SharedTaskService } from "./tasks/shared-task.service";
import { StudentFunnelService } from "./student-funnel.service";
import { StudentRow } from "./student-read";
import { studentContactEmailSql } from "./students/student-contact-email";
import { TimelineService } from "./timeline.service";

@Injectable()
export class LeadCardService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly chatWork: ChatWorkTimelineService,
    private readonly timeline: TimelineService,
    private readonly pipelines: StudentFunnelService,
    private readonly tasks: SharedTaskService,
  ) {}

  async get(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const leadResult = await this.database.query<LeadBoardRow>(
      `
        select l.id, l.version, l.status_id, ls.stage_key as status_key,
          ls.name as status_name, ls.color as status_color,
          ls.sort_order as status_sort_order, l.first_name, l.last_name, l.phone,
          l.email, l.source, l.source_id, l.notes, l.assigned_to, l.blacklisted, l.blacklist_reason, l.custom_data,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          ${branchIdExpr("l")} as branch_id,
          b.name as branch_name,
          linked_student.id as linked_student_id,
          (
            select link.user_id
            from app.user_crm_links link
            join app.users chat_user on chat_user.id = link.user_id
              and chat_user.deleted_at is null
              and chat_user.is_app_account = true
            where link.entity_type = 'lead'
              and link.entity_id = l.id
              and link.deleted_at is null
            order by link.confirmed_at desc nulls last, link.created_at desc, link.id desc
            limit 1
          ) as linked_user_id,
          (
            select count(*)
            from app.canonical_tasks task
            where task.deleted_at is null
              and task.entity_type = 'lead'
              and task.entity_id = l.id
              and task.status in ('open', 'in_progress')
              and exists (
                select 1 from app.shared_task_visibility visibility
                where visibility.task_id = task.id
                  and visibility.user_id = $2::uuid
              )
          ) as open_tasks_count,
          (
            select count(*)
            from app.entity_comments comment
            where comment.deleted_at is null
              and comment.entity_type = 'lead'
              and comment.entity_id = l.id
          ) as comments_count,
          (
            select count(*)
            from app.lessons lesson
            where lesson.deleted_at is null
              and lesson.lead_id = l.id
              and lesson.is_trial = true
          ) as trial_lessons_count,
          l.created_by, l.created_at, l.updated_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        left join app.users assigned_user on assigned_user.id = l.assigned_to and assigned_user.deleted_at is null
        left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
        left join app.branches b
          on b.id::text = ${branchIdExpr("l")}
         and b.deleted_at is null
        left join app.students linked_student
          on linked_student.lead_id = l.id
         and linked_student.deleted_at is null
        where l.id = $1 and l.deleted_at is null
        limit 1
      `,
      [leadId, actor.userId],
    );
    const lead = leadResult.rows[0];
    if (!lead) throw new NotFoundException("Лид не найден.");
    await this.applyEffectiveStage(actor, lead);
    const related = await this.loadRelated(actor, lead);
    return {
      lead: toLeadBoardItemDto(lead),
      linkedStudents: related.students,
      otherLeads: related.otherLeads,
      comments: related.comments,
      tasks: related.tasks,
      trials: related.trials,
      timeline: this.buildTimeline(related),
      customFieldValues: related.customFieldValues,
    };
  }

  private async applyEffectiveStage(actor: ActorContext, lead: LeadBoardRow) {
    const effective = await this.pipelines.getEffective(
      actor,
      lead.branch_id ?? undefined,
      "lead",
    );
    const stage = effective.stages.find((item) => item.key === lead.status_key);
    if (!stage) return;
    lead.status_name = stage.label;
    lead.status_color = stage.style;
  }

  private async loadRelated(actor: ActorContext, lead: LeadBoardRow) {
    const [
      students,
      otherLeads,
      comments,
      tasks,
      trials,
      chatWork,
      fieldAudit,
      customFieldValues,
    ] = await Promise.all([
      this.listStudents(lead.id),
      this.listRelatedLeads(lead),
      this.listComments(lead.id),
      this.tasks
        .list(actor, {
          linkedEntityType: "lead",
          linkedEntityId: lead.id,
          limit: 100,
        })
        .then((result) => result.items),
      this.listTrials(lead.id),
      this.listChatWork(lead.id),
      this.timeline
        .listFieldAudit(actor, "lead", lead.id, 50)
        .catch(() => ({ items: [] as Record<string, unknown>[] })),
      readTypedClientValueMap(this.database, "lead", lead.id),
    ]);
    return {
      students,
      otherLeads,
      comments,
      tasks,
      trials,
      chatWork,
      fieldAudit,
      customFieldValues,
    };
  }

  private buildTimeline(
    related: Awaited<ReturnType<LeadCardService["loadRelated"]>>,
  ) {
    return [
      ...related.comments.map((comment) => ({
        id: comment.id,
        type: "comment",
        title: "Комментарий",
        body: comment.body,
        status: null,
        occurredAt: comment.createdAt,
      })),
      ...related.tasks.map((task) => ({
        id: task.id,
        type: "task",
        title: task.title,
        body: task.body,
        status: task.state,
        occurredAt: task.createdAt,
      })),
      ...related.trials.map((lesson) => ({
        id: lesson.id,
        type: "trial",
        title: "Пробное занятие",
        body: lesson.teacherName || lesson.roomName || null,
        status: lesson.status,
        occurredAt: lesson.scheduledAt,
      })),
      ...related.chatWork,
      ...related.fieldAudit.items.map((entry) => ({
        id: String(entry.id),
        type: "audit",
        title: String(entry.title),
        body: entry.body === null ? null : String(entry.body),
        status: null,
        occurredAt: entry.occurredAt,
      })),
    ].sort(
      (left, right) =>
        new Date(String(right.occurredAt)).getTime() -
        new Date(String(left.occurredAt)).getTime(),
    );
  }

  private async listStudents(leadId: string) {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.version, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason,
          p.first_name, p.last_name, ${studentContactEmailSql()} as email, p.phone,
          s.created_at, '{}'::uuid[] as teacher_user_ids
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where s.deleted_at is null and s.lead_id = $1
        order by s.created_at desc, s.id desc
        limit 20
      `,
      [leadId],
    );
    return result.rows.map(toStudentDto);
  }

  private async listRelatedLeads(lead: LeadRow) {
    if (!lead.phone && !lead.email) return [];
    const result = await this.database.query<LeadRow>(
      `
        select l.id, l.version, l.status_id, ls.name as status_name, l.first_name,
          l.last_name, l.phone, l.email, l.source, l.notes, l.assigned_to,
          l.custom_data, l.created_by, l.created_at, l.updated_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where l.deleted_at is null
          and l.id <> $1
          and (
            ($2::text is not null and l.phone = $2)
            or ($3::text is not null and lower(l.email) = lower($3))
          )
        order by l.created_at desc, l.id desc
        limit 10
      `,
      [lead.id, lead.phone, lead.email],
    );
    return result.rows.map(toLeadDto);
  }

  private async listComments(leadId: string) {
    const result = await this.database.query<CommentRow>(
      `
        select c.id, c.entity_type, c.entity_id, c.author_id,
          p.first_name as author_first_name, p.last_name as author_last_name,
          c.body, c.kind, c.created_at
        from app.entity_comments c
        left join app.users u on u.id = c.author_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where c.deleted_at is null
          and c.entity_type = 'lead'
          and c.entity_id = $1
        order by c.created_at desc, c.id desc
        limit 50
      `,
      [leadId],
    );
    return result.rows.map(toCommentDto);
  }

  private async listTrials(leadId: string) {
    const result = await this.database.query<LessonRow>(
      `
        select l.id, l.student_id, l.group_id, l.lead_id, l.teacher_id, l.branch_id, l.room_id, l.scheduled_at,
          l.duration_minutes, l.status, l.is_trial, l.notes,
          null::uuid as student_user_id, tp.user_id as teacher_user_id,
          null::text as student_name,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.name as group_name,
          g.price_per_lesson as group_price_per_lesson
        from app.lessons l
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = l.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        where l.deleted_at is null
          and l.lead_id = $1
          and l.is_trial = true
        order by l.scheduled_at desc, l.id desc
        limit 20
      `,
      [leadId],
    );
    return result.rows.map(toLessonDto);
  }

  private async listChatWork(leadId: string) {
    const rows = await this.chatWork.listForEntity("lead", leadId);
    return rows.map(toTimelineDto);
  }
}
