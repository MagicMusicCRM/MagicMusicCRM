import { Injectable, NotFoundException } from "@nestjs/common";
import { AccessMutationsRepository } from "../../access-control/access-mutations.repository";
import { CapabilityKey } from "../../access-control/capability-registry";
import { EffectiveAccessEvaluator } from "../../access-control/effective-access-evaluator";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { ClientRefDto } from "../dto/client-ref.dto";
import {
  ClientReferenceService,
  ResolvedClientReference,
} from "./client-reference.service";

interface ClientCardCompositionRow {
  header: Record<string, unknown> | null;
  lessons: Array<Record<string, unknown>>;
  tasks: Array<Record<string, unknown>>;
  homework: Array<Record<string, unknown>>;
  comments: Array<Record<string, unknown>>;
  groups: Array<Record<string, unknown>>;
  finance: Record<string, unknown> | null;
  lesson_counts: Record<string, number>;
  task_counts: Record<string, number>;
  homework_counts: Record<string, number>;
  next_lesson: Record<string, unknown> | null;
}

type ClientCardProjection = "full" | "teacher" | "client";

@Injectable()
export class ClientCardReadService {
  constructor(
    private readonly database: DatabaseService,
    private readonly references: ClientReferenceService,
    private readonly access: AccessMutationsRepository,
    private readonly evaluator: EffectiveAccessEvaluator,
  ) {}

  async load(actor: ActorContext, ref: ClientRefDto) {
    const [reference, capabilities] = await Promise.all([
      this.references.resolve(actor, ref),
      this.effectiveCapabilities(actor),
    ]);
    const projection = this.projectionFor(actor);
    const canReadLessons = capabilities.has("schedule.lesson.read.assigned");
    const canReadTasks =
      projection === "full" && capabilities.has("workflow.task.read");
    const canReadHomework = canReadLessons;
    const canReadComments = capabilities.has("crm.client.read.basic");
    const canReadGroups = projection === "full";
    const canReadFinance =
      ref.type === "student" &&
      projection !== "teacher" &&
      capabilities.has("commerce.client_finance.read");
    const commentKinds =
      projection === "full"
        ? ["admin_comment", "teacher_note", "progress"]
        : projection === "teacher"
          ? ["teacher_note", "progress"]
          : ["progress"];

    const result = await this.database.query<ClientCardCompositionRow>(
      `
        with target as (
          select $1::text as type, $2::uuid as id
        ),
        header_row as (
          select
            target.type,
            target.id,
            case
              when target.type = 'student' then student_profile.first_name
              else lead.first_name
            end as first_name,
            case
              when target.type = 'student' then student_profile.last_name
              else lead.last_name
            end as last_name,
            case
              when target.type = 'student' then student.status
              else lead_status.name
            end as status,
            case
              when target.type = 'student' then student.status
              else lead_status.stage_key
            end as status_key,
            coalesce(student.branch_id, lead.branch_id) as branch_id,
            branch.name as branch_name
          from target
          left join app.students student
            on target.type = 'student' and student.id = target.id
          left join app.profiles student_profile
            on student_profile.id = student.profile_id
          left join app.leads lead
            on target.type = 'lead' and lead.id = target.id
          left join app.lead_statuses lead_status
            on lead_status.id = lead.status_id
          left join app.branches branch
            on branch.id = coalesce(student.branch_id, lead.branch_id)
        ),
        lesson_rows as (
          select
            lesson.id,
            lesson.scheduled_at as occurred_at,
            lesson.lifecycle_state as state,
            jsonb_build_object(
              'id', lesson.id,
              'scheduledAt', lesson.scheduled_at,
              'durationMinutes', lesson.duration_minutes,
              'status', lesson.status,
              'lifecycleState', lesson.lifecycle_state,
              'isTrial', lesson.is_trial,
              'teacherName', nullif(btrim(
                coalesce(teacher_profile.first_name, '') || ' ' ||
                coalesce(teacher_profile.last_name, '')
              ), ''),
              'branchName', lesson_branch.name,
              'roomName', room.name,
              'reservationState', reservation.state
            ) as item
          from target
          join app.lessons lesson
            on (
              (target.type = 'student' and lesson.student_id = target.id)
              or (target.type = 'lead' and lesson.lead_id = target.id)
            )
           and lesson.deleted_at is null
          left join app.teachers teacher
            on teacher.id = lesson.teacher_id and teacher.deleted_at is null
          left join app.profiles teacher_profile
            on teacher_profile.id = teacher.profile_id
           and teacher_profile.deleted_at is null
          left join app.branches lesson_branch
            on lesson_branch.id = lesson.branch_id
           and lesson_branch.deleted_at is null
          left join app.rooms room
            on room.id = lesson.room_id and room.deleted_at is null
          left join app.lesson_reservations reservation
            on reservation.lesson_id = lesson.id
           and reservation.state = 'reserved'
          where $3::boolean
            and (
              $11::text <> 'teacher'
              or teacher_profile.user_id = $12::uuid
            )
        ),
        task_rows as (
          select
            task.id,
            coalesce(task.due_at, task.created_at) as occurred_at,
            task.status,
            jsonb_build_object(
              'id', task.id,
              'title', task.title,
              'description', task.description,
              'status', task.status,
              'dueAt', task.due_at,
              'createdAt', task.created_at
            ) as item
          from target
          join app.canonical_tasks task
            on task.entity_type::text = target.type
           and task.entity_id = target.id
           and task.deleted_at is null
          where $4::boolean
            and exists (
              select 1 from app.shared_task_visibility visibility
              where visibility.task_id = task.id
                and visibility.user_id = $12::uuid
            )
        ),
        homework_rows as (
          select
            homework.id,
            coalesce(homework.due_at, homework.created_at) as occurred_at,
            homework.status,
            jsonb_build_object(
              'id', homework.id,
              'lessonId', homework.lesson_id,
              'title', homework.title,
              'description', homework.description,
              'status', homework.status,
              'dueAt', homework.due_at,
              'createdAt', homework.created_at
            ) as item
          from target
          join app.lesson_homeworks homework
            on (
              (target.type = 'student' and homework.student_id = target.id)
              or (target.type = 'lead' and homework.lead_id = target.id)
            )
           and homework.deleted_at is null
          left join app.lessons homework_lesson
            on homework_lesson.id = homework.lesson_id
           and homework_lesson.deleted_at is null
          left join app.teachers homework_teacher
            on homework_teacher.id = homework_lesson.teacher_id
           and homework_teacher.deleted_at is null
          left join app.profiles homework_teacher_profile
            on homework_teacher_profile.id = homework_teacher.profile_id
           and homework_teacher_profile.deleted_at is null
          where $5::boolean
            and (
              $11::text <> 'teacher'
              or homework_teacher_profile.user_id = $12::uuid
            )
        ),
        comment_rows as (
          select
            comment.id,
            comment.created_at as occurred_at,
            jsonb_build_object(
              'id', comment.id,
              'body', comment.body,
              'kind', comment.kind,
              'sharedWithTeacher', comment.shared_with_teacher,
              'version', comment.version,
              'createdAt', comment.created_at
            ) as item
          from target
          join app.entity_comments comment
            on comment.entity_type::text = target.type
           and comment.entity_id = target.id
           and comment.deleted_at is null
          where $6::boolean
            and comment.kind = any($9::text[])
            and ($10::boolean = false or comment.shared_with_teacher)
        ),
        group_rows as (
          select
            membership.id,
            membership.joined_at as occurred_at,
            jsonb_build_object(
              'id', group_row.id,
              'name', group_row.name,
              'branchId', group_row.branch_id,
              'branchName', branch.name,
              'teacherName', nullif(btrim(
                coalesce(teacher_profile.first_name, '') || ' ' ||
                coalesce(teacher_profile.last_name, '')
              ), '')
            ) as item
          from target
          join app.group_students membership
            on target.type = 'student'
           and membership.student_id = target.id
           and membership.left_at is null
          join app.groups group_row
            on group_row.id = membership.group_id
           and group_row.deleted_at is null
          left join app.branches branch
            on branch.id = group_row.branch_id and branch.deleted_at is null
          left join app.teachers teacher
            on teacher.id = group_row.teacher_id and teacher.deleted_at is null
          left join app.profiles teacher_profile
            on teacher_profile.id = teacher.profile_id
           and teacher_profile.deleted_at is null
          where $7::boolean
        )
        select
          (
            select jsonb_build_object(
              'type', header.type,
              'id', header.id,
              'firstName', header.first_name,
              'lastName', header.last_name,
              'displayName', nullif(btrim(
                coalesce(header.first_name, '') || ' ' ||
                coalesce(header.last_name, '')
              ), ''),
              'status', header.status,
              'statusKey', header.status_key,
              'branchId', header.branch_id,
              'branchName', header.branch_name
            )
            from header_row header
          ) as header,
          (
            select coalesce(jsonb_agg(page.item order by page.occurred_at desc),
              '[]'::jsonb)
            from (
              select item, occurred_at from lesson_rows
              order by occurred_at desc, id desc limit 100
            ) page
          ) as lessons,
          (
            select coalesce(jsonb_agg(page.item order by page.occurred_at desc),
              '[]'::jsonb)
            from (
              select item, occurred_at from task_rows
              order by occurred_at desc, id desc limit 100
            ) page
          ) as tasks,
          (
            select coalesce(jsonb_agg(page.item order by page.occurred_at desc),
              '[]'::jsonb)
            from (
              select item, occurred_at from homework_rows
              order by occurred_at desc, id desc limit 100
            ) page
          ) as homework,
          (
            select coalesce(jsonb_agg(page.item order by page.occurred_at desc),
              '[]'::jsonb)
            from (
              select item, occurred_at from comment_rows
              order by occurred_at desc, id desc limit 100
            ) page
          ) as comments,
          (
            select coalesce(jsonb_agg(page.item order by page.occurred_at desc),
              '[]'::jsonb)
            from (
              select item, occurred_at from group_rows
              order by occurred_at desc, id desc limit 100
            ) page
          ) as groups,
          case when $8::boolean then (
            select jsonb_build_object(
              'balanceMinor', coalesce(
                round(balance.balance * 100)::bigint,
                0
              ),
              'activeSubscription', (
                select jsonb_build_object(
                  'id', subscription.id,
                  'remainingUnits', greatest(
                    0,
                    subscription.lessons_total - subscription.lessons_used
                  ),
                  'expiresAt', subscription.expires_at,
                  'currencyCode', subscription.currency_code
                )
                from app.subscriptions subscription
                where subscription.student_id = target.id
                  and subscription.status = 'active'
                order by subscription.created_at desc, subscription.id desc
                limit 1
              )
            )
            from target
            left join app.student_balances balance
              on target.type = 'student' and balance.student_id = target.id
          ) else null end as finance,
          (
            select coalesce(jsonb_object_agg(counts.state, counts.total),
              '{}'::jsonb)
            from (
              select state, count(*)::integer as total
              from lesson_rows group by state
            ) counts
          ) as lesson_counts,
          (
            select coalesce(jsonb_object_agg(counts.status, counts.total),
              '{}'::jsonb)
            from (
              select status, count(*)::integer as total
              from task_rows group by status
            ) counts
          ) as task_counts,
          (
            select coalesce(jsonb_object_agg(counts.status, counts.total),
              '{}'::jsonb)
            from (
              select status, count(*)::integer as total
              from homework_rows group by status
            ) counts
          ) as homework_counts,
          (
            select item from lesson_rows
            where occurred_at >= now() and state = 'scheduled'
            order by occurred_at, id
            limit 1
          ) as next_lesson
      `,
      [
        ref.type,
        ref.id,
        canReadLessons,
        canReadTasks,
        canReadHomework,
        canReadComments,
        canReadGroups,
        canReadFinance,
        commentKinds,
        projection === "teacher",
        actor.role,
        actor.userId,
      ],
    );
    const row = result.rows[0];
    if (!row?.header) {
      throw new NotFoundException("Клиент не найден.");
    }

    const sections: Record<string, unknown> = {
      lessons: this.section(row.lessons),
      homework: this.section(row.homework),
      comments: this.section(row.comments),
    };
    if (projection === "full") {
      sections.groups = this.section(row.groups);
      sections.tasks = this.section(row.tasks);
    }
    if (row.finance) sections.finance = row.finance;

    const timeline = [
      ...row.comments.map((item) => this.timelineItem(item, "comment")),
      ...row.tasks.map((item) => this.timelineItem(item, "task")),
      ...row.homework.map((item) => this.timelineItem(item, "homework")),
      ...row.lessons.map((item) => this.timelineItem(item, "lesson")),
    ].sort(
      (left, right) =>
        new Date(String(right.occurredAt)).getTime() -
        new Date(String(left.occurredAt)).getTime(),
    );

    const indicators: Record<string, unknown> = {
      nextLesson: row.next_lesson,
      lessonsByState: row.lesson_counts,
      homeworkByStatus: row.homework_counts,
      comments: row.comments.length,
    };
    if (projection === "full") {
      indicators.tasksByStatus = row.task_counts;
    }
    if (row.finance) {
      indicators.activeSubscriptionRemaining =
        (row.finance.activeSubscription as
          | { remainingUnits?: unknown }
          | undefined)?.remainingUnits ?? null;
    }

    return {
      ref: reference.ref,
      projection,
      header: row.header,
      lifecycle: {
        state: reference.lifecycleState,
        tombstone: reference.tombstone,
        archivedAt: reference.archivedAt,
        version: reference.version,
      },
      links: reference.links,
      indicators,
      sections,
      // Compatibility aliases keep the existing Flutter client card wired to
      // this read model while T3.3.2 moves it to the stable section contract.
      student:
        ref.type === "student"
          ? {
              id: ref.id,
              ...(row.header as Record<string, unknown>),
            }
          : null,
      ...(projection === "full"
        ? { groups: row.groups, tasks: row.tasks }
        : {}),
      lessons: row.lessons,
      comments: row.comments,
      homework: row.homework,
      timeline,
    };
  }

  private projectionFor(actor: ActorContext): ClientCardProjection {
    if (actor.role === "teacher") return "teacher";
    if (actor.role === "client") return "client";
    return "full";
  }

  private section(items: Array<Record<string, unknown>>) {
    return { items, count: items.length };
  }

  private timelineItem(item: Record<string, unknown>, type: string) {
    const occurredAt =
      item.createdAt ?? item.dueAt ?? item.scheduledAt ?? null;
    return {
      id: item.id,
      type,
      title: item.title ?? (type === "lesson" ? "Занятие" : type),
      body: item.body ?? item.description ?? null,
      status: item.status ?? item.lifecycleState ?? null,
      occurredAt,
    };
  }

  private async effectiveCapabilities(
    actor: ActorContext,
  ): Promise<Set<CapabilityKey>> {
    const rows = await this.access.getEffectiveAccessSnapshot(actor.userId);
    return new Set(
      rows
        .filter((row) =>
          this.evaluator.evaluate({
            actor: {
              userId: row.userId,
              role: row.role,
              active: row.active,
            },
            capability: {
              key: row.capabilityKey,
              active: row.capabilityActive,
              overrideMode: row.overrideMode,
            },
            roleEffect: row.roleEffect,
            overrideEffect: row.overrideEffect,
            resourceAllowed: true,
          }).allowed,
        )
        .map((row) => row.capabilityKey),
    );
  }
}
