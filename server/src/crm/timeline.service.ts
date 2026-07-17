import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { CommentQuery } from "./dto/comment.query";
import { CreateCommentDto } from "./dto/create-comment.dto";
import { TimelineQuery } from "./dto/timeline.query";
import { findStudent } from "./student-read";
import { TimelineRow, toTimelineDto } from "./crm-mappers";
import { CHAT_WORK_TIMELINE_FRAGMENT } from "../messenger/chat-work-timeline.service";

// ponytail: CommentRow + toCommentDto remain here (retained getLeadCard readers —
// listLeadComments — still map these). The timeline mapper now lives in
// ./crm-mappers.

interface CommentRow {
  id: string;
  entity_type: string;
  entity_id: string;
  author_id: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
  body: string;
  kind: string;
  created_at: Date | string;
  /**
   * Когда идёт занятие, к которому оставлен комментарий. `null` у обычных.
   *
   * Именно так лента и отличает «комментарий к клиенту» от «комментария к
   * занятию 21.06» — без второго запроса на каждую строку.
   */
  lesson_at?: Date | string | null;
}

@Injectable()
export class TimelineService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeBus,
  ) {}

  /**
   * Field edits for one entity («кто поменял телефон и на какой»), already
   * rendered into readable lines by toTimelineDto. Feeds the client card's
   * history, which is assembled by hand from comments/tasks/… and so never saw
   * audit_events at all.
   *
   * Manager+ only, and it returns an empty list rather than throwing: the card
   * aggregate calls this for every reader, including the client portal, where
   * "who edited your record" is simply not their business.
   */
  async listFieldAudit(
    actor: ActorContext,
    entityType: string,
    entityId: string,
    limit = 50,
  ) {
    if (!isManagerOrAdminRole(actor.role)) return { items: [] };
    const result = await this.database.query<TimelineRow>(
      `
        select audit.id::text as id, 'audit'::text as type,
          audit.action as title, audit.metadata::text as body,
          audit.entity_type as status, null::numeric as amount,
          audit.actor_user_id,
          ap.first_name as actor_first_name,
          ap.last_name as actor_last_name,
          audit.created_at as occurred_at
        from app.audit_events audit
        left join app.users au on au.id = audit.actor_user_id and au.deleted_at is null
        left join app.profiles ap on ap.user_id = au.id and ap.deleted_at is null
        where audit.entity_type = $1
          and audit.entity_id = $2::text
          -- Only events that carry a diff. A CASE rather than a bare
          -- jsonb_array_length: metadata->'changes' is absent on older rows and
          -- on non-edit actions, and the function throws on a non-array.
          and case
            when jsonb_typeof(audit.metadata -> 'changes') = 'array'
              then jsonb_array_length(audit.metadata -> 'changes') > 0
            else false
          end
        order by audit.created_at desc, audit.id desc
        limit $3
      `,
      [entityType, entityId, Math.min(limit, 200)],
    );
    return { items: result.rows.map((row) => toTimelineDto(row)) };
  }

  async listTimeline(actor: ActorContext, query: TimelineQuery) {
    if (!query.entityType || !query.entityId) {
      throw new BadRequestException("Тип и объект timeline обязательны.");
    }
    await this.assertCanReadEntityComments(
      actor,
      query.entityType,
      query.entityId,
    );
    const limit = Math.min(query.limit ?? 80, 200);
    const includeAudit = query.includeAudit === true;
    const result = await this.database.query<TimelineRow>(
      `
        with timeline as (
          select c.id::text as id, 'comment'::text as type,
            'Комментарий'::text as title, c.body as body,
            null::text as status, null::numeric as amount,
            c.author_id as actor_user_id,
            cp.first_name as actor_first_name,
            cp.last_name as actor_last_name,
            c.created_at as occurred_at
          from app.entity_comments c
          left join app.users cu on cu.id = c.author_id and cu.deleted_at is null
          left join app.profiles cp on cp.user_id = cu.id and cp.deleted_at is null
          where c.deleted_at is null
            and c.entity_type::text = $1
            and c.entity_id = $2::uuid
            and c.kind = any($7::text[])

          union all

          select task.id::text as id, 'task'::text as type,
            task.title, task.description as body, task.status,
            null::numeric as amount, task.created_by as actor_user_id,
            tp.first_name as actor_first_name,
            tp.last_name as actor_last_name,
            coalesce(task.due_at, task.created_at) as occurred_at
          from app.tasks task
          left join app.users tu on tu.id = task.created_by and tu.deleted_at is null
          left join app.profiles tp on tp.user_id = tu.id and tp.deleted_at is null
          where task.deleted_at is null
            and task.entity_type::text = $1
            and task.entity_id = $2::uuid

          union all

          select lesson.id::text as id,
            case when lesson.is_trial then 'trial' else 'lesson' end as type,
            case when lesson.is_trial then 'Пробное занятие' else 'Занятие' end as title,
            nullif(trim(coalesce(tp2.first_name, '') || ' ' || coalesce(tp2.last_name, '')), '') as body,
            lesson.status, null::numeric as amount,
            null::uuid as actor_user_id,
            null::text as actor_first_name,
            null::text as actor_last_name,
            lesson.scheduled_at as occurred_at
          from app.lessons lesson
          left join app.teachers teacher on teacher.id = lesson.teacher_id and teacher.deleted_at is null
          left join app.profiles tp2 on tp2.id = teacher.profile_id and tp2.deleted_at is null
          where lesson.deleted_at is null
            and (
              ($1 = 'student' and lesson.student_id = $2::uuid)
              or ($1 = 'lead' and lesson.lead_id = $2::uuid)
              or ($1 = 'teacher' and lesson.teacher_id = $2::uuid)
              or ($1 = 'group' and lesson.group_id = $2::uuid)
              or ($1 = 'lesson' and lesson.id = $2::uuid)
            )

          union all

          select pay.id::text as id, 'payment'::text as type,
            'Платеж'::text as title, pay.notes as body,
            pay.method as status, pay.amount,
            pay.created_by as actor_user_id,
            pp.first_name as actor_first_name,
            pp.last_name as actor_last_name,
            pay.payment_date as occurred_at
          from app.payments pay
          left join app.users pu on pu.id = pay.created_by and pu.deleted_at is null
          left join app.profiles pp on pp.user_id = pu.id and pp.deleted_at is null
          where pay.deleted_at is null
            and $1 = 'student'
            and pay.student_id = $2::uuid

          union all

          ${CHAT_WORK_TIMELINE_FRAGMENT}

          union all

          select audit.id::text as id, 'audit'::text as type,
            audit.action as title, audit.metadata::text as body,
            audit.entity_type as status, null::numeric as amount,
            audit.actor_user_id,
            ap.first_name as actor_first_name,
            ap.last_name as actor_last_name,
            audit.created_at as occurred_at
          from app.audit_events audit
          left join app.users au on au.id = audit.actor_user_id and au.deleted_at is null
          left join app.profiles ap on ap.user_id = au.id and ap.deleted_at is null
          where $5::boolean = true
            and audit.entity_type = $1
            and audit.entity_id = $2::text
        )
        select *
        from timeline
        where ($3::timestamptz is null or occurred_at >= $3)
          and ($4::timestamptz is null or occurred_at < $4)
        order by occurred_at desc, id desc
        limit $6
      `,
      [
        query.entityType,
        query.entityId,
        query.from ?? null,
        query.to ?? null,
        includeAudit,
        limit,
        this.allowedCommentKinds(actor.role),
      ],
    );
    return { items: result.rows.map((row) => toTimelineDto(row)) };
  }

  async listComments(actor: ActorContext, query: CommentQuery) {
    if (!query.entityType || !query.entityId) {
      throw new BadRequestException("Тип и объект комментариев обязательны.");
    }
    await this.assertCanReadEntityComments(
      actor,
      query.entityType,
      query.entityId,
    );
    const limit = Math.min(query.limit ?? 50, 100);
    let allowedKinds = this.allowedCommentKinds(actor.role);
    // Back-compat: progressOnly restricts to the client-visible progress stream.
    if (query.progressOnly === true) {
      allowedKinds = allowedKinds.filter((k) => k === "progress");
    }
    // Caller can request a single stream (e.g. the card's admin-comments vs
    // teacher-notes section); still bounded by what the role may see.
    if (query.kind) {
      allowedKinds = allowedKinds.filter((k) => k === query.kind);
    }
    if (allowedKinds.length === 0) return { items: [] };
    // Комментарии к занятиям подмешиваются только в карточку УЧЕНИКА: у лида
    // занятий нет, и спрашивать их бессмысленно.
    const withLessons =
      query.includeLessonComments === true && query.entityType === "student";
    const result = await this.database.query<CommentRow>(
      `
        select c.id, c.entity_type, c.entity_id, c.author_id, c.kind,
          p.first_name as author_first_name, p.last_name as author_last_name,
          c.body, c.created_at,
          l.scheduled_at as lesson_at
        from app.entity_comments c
        left join app.users u on u.id = c.author_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        -- Занятие подтягивается только у комментариев к занятиям; у обычных
        -- lesson_at останется null, и лента различит их без второго запроса.
        left join app.lessons l
          on l.id = c.entity_id
         and c.entity_type = 'lesson'
         and l.deleted_at is null
        where c.deleted_at is null
          and c.kind = any($3::text[])
          and (
            (c.entity_type = $1::app.crm_entity_type and c.entity_id = $2)
            or (
              $5::boolean
              and c.entity_type = 'lesson'
              and exists (
                select 1
                from app.lessons ml
                where ml.id = c.entity_id
                  and ml.deleted_at is null
                  and (
                    -- Индивидуальное занятие: ученик прописан прямо на нём.
                    ml.student_id = $2
                    -- Групповое: ученик — через участие. Одна заметка админа
                    -- к групповому занятию попадёт в ленту КАЖДОГО участника,
                    -- и это верно: она про то занятие, на котором был каждый.
                    or exists (
                      select 1 from app.lesson_participation lp
                      where lp.lesson_id = ml.id and lp.student_id = $2
                    )
                  )
              )
            )
          )
        order by c.created_at desc, c.id desc
        limit $4
      `,
      [query.entityType, query.entityId, allowedKinds, limit, withLessons],
    );
    return { items: result.rows.map((row) => this.toCommentDto(row)) };
  }

  async createComment(actor: ActorContext, dto: CreateCommentDto) {
    const body = dto.body.trim();
    if (!body)
      throw new BadRequestException("Комментарий не может быть пустым.");
    const kind =
      dto.kind ?? (dto.progress === true ? "progress" : "admin_comment");
    await this.assertCanCreateEntityComment(actor, dto, kind);
    const result = await this.database.query<CommentRow>(
      `
        insert into app.entity_comments (
          entity_type, entity_id, author_id, body, kind
        )
        values ($1::app.crm_entity_type, $2, $3, $4, $5)
        returning id, entity_type, entity_id, author_id,
          null::text as author_first_name, null::text as author_last_name,
          body, kind, created_at
      `,
      [dto.entityType, dto.entityId, actor.userId, body, kind],
    );
    const comment = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.comment_created",
      entityType: dto.entityType,
      entityId: dto.entityId,
      metadata: { commentId: comment.id },
    });
    this.realtime.emitCrmChanged({
      entity: "comment",
      action: "created",
      id: comment.id,
    });
    return this.toCommentDto(comment);
  }

  // Toggle whether an existing comment is visible to the assigned teacher.
  // Default comments are `admin_comment` (staff-only); flipping to `teacher_note`
  // makes them visible to the teacher too, and back hides them again. Only staff
  // may change visibility; `progress` (client-facing) notes are out of scope.
  async setCommentVisibility(
    actor: ActorContext,
    commentId: string,
    visibleToTeacher: boolean,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const kind = visibleToTeacher ? "teacher_note" : "admin_comment";
    const result = await this.database.query<CommentRow>(
      `
        update app.entity_comments
        set kind = $2
        where id = $1
          and deleted_at is null
          and kind in ('admin_comment', 'teacher_note')
        returning id, entity_type, entity_id, author_id,
          null::text as author_first_name, null::text as author_last_name,
          body, kind, created_at
      `,
      [commentId, kind],
    );
    const comment = result.rows[0];
    if (!comment) throw new NotFoundException("Комментарий не найден.");
    await this.audit.record({
      actor,
      action: "crm.comment_visibility_changed",
      entityType: comment.entity_type,
      entityId: comment.entity_id,
      metadata: { commentId: comment.id, kind },
    });
    this.realtime.emitCrmChanged({
      entity: "comment",
      action: "updated",
      id: comment.id,
    });
    return this.toCommentDto(comment);
  }

  private async assertCanReadEntityComments(
    actor: ActorContext,
    entityType: string,
    entityId: string,
  ) {
    if (entityType === "student") {
      const student = await findStudent(this.database, entityId);
      if (!student) throw new NotFoundException("Ученик не найден.");
      this.policy.assertCanReadStudent(actor, {
        profileUserId: student.profile_user_id,
        teacherUserIds: student.teacher_user_ids ?? [],
      });
      return;
    }

    this.policy.assertCanWriteCrm(actor);
  }

  private async assertCanCreateEntityComment(
    actor: ActorContext,
    dto: CreateCommentDto,
    kind: string,
  ) {
    // Staff (manager/admin) may write any stream.
    if (isManagerOrAdminRole(actor.role)) {
      this.policy.assertCanWriteCrm(actor);
      await this.assertEntityExistsForComment(dto.entityType, dto.entityId);
      return;
    }

    // Teachers may write their own «Заметки преподавателя» (teacher_note) and
    // client-visible progress notes — but NEVER administrator comments.
    if (
      actor.role === "teacher" &&
      dto.entityType === "student" &&
      (kind === "teacher_note" || kind === "progress")
    ) {
      await this.assertCanReadEntityComments(
        actor,
        dto.entityType,
        dto.entityId,
      );
      return;
    }

    throw new ForbiddenException("Недостаточно прав для комментария.");
  }

  private async assertEntityExistsForComment(
    entityType: string,
    entityId: string,
  ) {
    if (entityType === "student") {
      const student = await findStudent(this.database, entityId);
      if (!student) throw new NotFoundException("Ученик не найден.");
      return;
    }

    const tableByType: Record<string, string> = {
      teacher: "teachers",
      group: "groups",
      lesson: "lessons",
      lead: "leads",
      profile: "profiles",
    };
    const table = tableByType[entityType];
    if (!table)
      throw new BadRequestException("Неподдерживаемый тип комментария.");
    const result = await this.database.query<{ exists: boolean }>(
      `select exists(select 1 from app.${table} where id = $1 and deleted_at is null) as exists`,
      [entityId],
    );
    if (!result.rows[0]?.exists) {
      throw new NotFoundException("Объект комментария не найден.");
    }
  }

  private toCommentDto(row: CommentRow) {
    const authorName =
      `${row.author_first_name ?? ""} ${row.author_last_name ?? ""}`.trim();
    return {
      id: row.id,
      entityType: row.entity_type,
      entityId: row.entity_id,
      authorId: row.author_id,
      authorName: authorName || null,
      body: row.body,
      kind: row.kind,
      // Back-compat flag for clients still keying off `progress`.
      progress: row.kind === "progress",
      createdAt: row.created_at,
      // Заполнено только у комментариев к занятиям: карточка по нему и рисует
      // пометку «к занятию такого-то числа».
      lessonAt: row.lesson_at ?? null,
    };
  }

  // Comment kinds this role may read for an entity. admin_comment is staff-only
  // (teachers/clients never see it); teacher_note is teacher + staff; progress is
  // visible to everyone including the client.
  private allowedCommentKinds(role: ActorContext["role"]): string[] {
    if (isManagerOrAdminRole(role)) {
      return ["admin_comment", "teacher_note", "progress"];
    }
    if (role === "teacher") return ["teacher_note", "progress"];
    return ["progress"];
  }
}
