import { Injectable, Logger, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { ChatWorkTimelineService } from "../messenger/chat-work-timeline.service";
import { TimelineService } from "./timeline.service";
import { resolveAge } from "./age";
import { resolveAppealDate } from "./appeal-date";
import { attachStudentToLead, leadStudentMatchSql } from "./lead-student-link";
import { RealtimeBus } from "../realtime/realtime-bus";
import { branchIdExpr, extractBranchId } from "./branch-scope";
import { sanitizeJsonObject } from "./crm-util";
import { buildTextSearch } from "./search-text";
import { CrmPolicy } from "./crm.policy";
import { CrmListQuery } from "./dto/crm-list.query";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { UpsertLeadDto } from "./dto/upsert-lead.dto";
import { StudentRow } from "./student-read";
import {
  LessonRow,
  TaskRow,
  diffEntityFields,
  presentableEmail,
  toLessonDto,
  toTaskDto,
  toTimelineDto,
} from "./crm-mappers";

/**
 * Lead columns worth an audit entry. custom_data is diffed per key by
 * diffEntityFields and so is deliberately absent from this list.
 */
const LEAD_AUDITED_FIELDS = [
  "status_id",
  "first_name",
  "last_name",
  "phone",
  "email",
  "source",
  "notes",
  "assigned_to",
];

interface LeadRow {
  id: string;
  status_id: string | null;
  status_name: string | null;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  email: string | null;
  source: string | null;
  notes: string | null;
  assigned_to: string | null;
  custom_data: Record<string, unknown> | null;
  created_by: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  /** Чёрный список = бан на чаты. См. blacklist.ts. */
  blacklisted?: boolean | null;
  blacklist_reason?: string | null;
}

interface LeadBoardRow extends LeadRow {
  status_color: string | null;
  status_sort_order: number | null;
  assigned_first_name: string | null;
  assigned_last_name: string | null;
  branch_id: string | null;
  branch_name: string | null;
  linked_student_id: string | null;
  open_tasks_count: string | number;
  comments_count: string | number;
  trial_lessons_count: string | number;
}

interface LeadBoardCountRow {
  status_id: string | null;
  count: string | number;
}

interface LeadStatusRow {
  id: string;
  name: string;
  color: string | null;
  sort_order: number;
  created_at: Date | string;
  requires_reason?: boolean;
  is_terminal?: boolean;
}

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
}

// ponytail: toStudentDto/toNumericStat/listChatWorkTimeline are still copied from
// crm.service — the retained student aggregators (getMySummary/getStudentCard)
// still own them. The DTO mappers (LessonRow/TaskRow/TimelineRow + toLessonDto/
// toTaskDto/toTimelineDto) and presentableEmail now live in ./crm-mappers.

/**
 * Lead pipeline (app.leads): board/card/list, CRUD, status history,
 * applications. Inbound capture (chat/app/site → lead) lives in
 * LeadIntakeService. Extracted from CrmService (B5).
 */
@Injectable()
export class LeadsService {
  private readonly logger = new Logger(LeadsService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly notifications: NotificationsService,
    private readonly chatWork: ChatWorkTimelineService,
    private readonly realtime: RealtimeBus,
    // Field-edit audit for the lead card. TimelineService depends only on
    // db/policy/audit/realtime, so this adds no cycle — CrmService injects it
    // the same way for the student card.
    private readonly timeline: TimelineService,
  ) {}

  async listLeadBoard(actor: ActorContext, query: LeadBoardQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 25, 50);
    // Where the «Без статуса» column sits among the real ones. Stored by the
    // reorder endpoint; null (default) keeps it last, as before.
    const unassignedSortResult = await this.database.query<{ value: number }>(
      `select value::int as value from app.system_settings
        where key = 'lead_board_unassigned_sort_order'`,
    );
    const unassignedSort = unassignedSortResult.rows[0]?.value ?? null;
    const filter = this.buildLeadBoardFilter(query);
    const countFilter = this.buildLeadBoardFilter({
      ...query,
      cursor: undefined,
    });
    const statusResult = await this.database.query<LeadStatusRow>(
      `
        select id, name, color, sort_order, created_at, requires_reason, is_terminal
        from app.lead_statuses
        order by sort_order asc, name asc, id asc
      `,
    );
    const countResult = await this.database.query<LeadBoardCountRow>(
      `
        select l.status_id, count(*) as count
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where ${countFilter.where}
        group by l.status_id
      `,
      countFilter.params,
    );

    const leadResult = await this.database.query<LeadBoardRow>(
      `
        with filtered as (
          select l.id, l.status_id, ls.name as status_name, ls.color as status_color,
            ls.sort_order as status_sort_order, l.first_name, l.last_name, l.phone,
            l.email, l.source, l.notes, l.assigned_to, l.blacklisted, l.blacklist_reason, l.custom_data,
            assigned_profile.first_name as assigned_first_name,
            assigned_profile.last_name as assigned_last_name,
            ${branchIdExpr("l")} as branch_id,
            b.name as branch_name,
            linked_student.id as linked_student_id,
            (
              select count(*)
              from app.tasks task
              where task.deleted_at is null
                and task.entity_type = 'lead'
                and task.entity_id = l.id
                and task.status in ('open', 'in_progress')
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
            l.created_by, l.created_at, l.updated_at,
            row_number() over (
              partition by coalesce(l.status_id::text, 'unassigned')
              order by l.created_at desc, l.id desc
            ) as rn
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
          where ${filter.where}
        )
        select *
        from filtered
        where rn <= $${filter.params.length + 1}
        order by status_sort_order nulls last, status_name nulls last, created_at desc, id desc
      `,
      [...filter.params, limit],
    );

    const counts = new Map(
      countResult.rows.map((row) => [
        row.status_id ?? "unassigned",
        this.toNumericStat(row.count),
      ]),
    );
    const columns = statusResult.rows.map((status) => ({
      ...this.toLeadStatusDto(status),
      totalCount: counts.get(status.id) ?? 0,
      items: [] as ReturnType<typeof this.toLeadBoardItemDto>[],
    }));

    const byStatus = new Map(columns.map((column) => [column.id, column]));
    for (const row of leadResult.rows) {
      const statusKey = row.status_id ?? "unassigned";
      if (!byStatus.has(statusKey)) {
        const column = {
          id: statusKey,
          name: row.status_name ?? "Без статуса",
          color: row.status_color ?? null,
          // «Без статуса» takes its stored position if one was set, else last.
          sortOrder:
            statusKey === "unassigned"
              ? (unassignedSort ?? 9999)
              : (row.status_sort_order ?? 9999),
          createdAt: row.created_at,
          requiresReason: false,
          isTerminal: false,
          totalCount: counts.get(statusKey) ?? 0,
          items: [] as ReturnType<typeof this.toLeadBoardItemDto>[],
        };
        byStatus.set(statusKey, column);
        columns.push(column);
      }
      byStatus.get(statusKey)?.items.push(this.toLeadBoardItemDto(row));
    }

    columns.sort((a, b) => {
      const order = (a.sortOrder ?? 9999) - (b.sortOrder ?? 9999);
      if (order !== 0) return order;
      return String(a.name).localeCompare(String(b.name), "ru");
    });

    const loadedRows = leadResult.rows;
    const oldest = loadedRows[loadedRows.length - 1];
    return {
      columns,
      totalCount: Array.from(counts.values()).reduce(
        (sum, count) => sum + count,
        0,
      ),
      nextCursor: oldest ? this.encodeLeadCursor(oldest) : null,
    };
  }

  async getLeadCard(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const leadResult = await this.database.query<LeadBoardRow>(
      `
        select l.id, l.status_id, ls.name as status_name, ls.color as status_color,
          ls.sort_order as status_sort_order, l.first_name, l.last_name, l.phone,
          l.email, l.source, l.notes, l.assigned_to, l.blacklisted, l.blacklist_reason, l.custom_data,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          ${branchIdExpr("l")} as branch_id,
          b.name as branch_name,
          linked_student.id as linked_student_id,
          (
            select count(*)
            from app.tasks task
            where task.deleted_at is null
              and task.entity_type = 'lead'
              and task.entity_id = l.id
              and task.status in ('open', 'in_progress')
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
      [leadId],
    );
    const lead = leadResult.rows[0];
    if (!lead) throw new NotFoundException("Лид не найден.");

    const [students, otherLeads, comments, tasks, trials, chatWork, fieldAudit] =
      await Promise.all([
        this.listStudentsLinkedToLead(leadId),
        this.listRelatedLeads(lead),
        this.listLeadComments(leadId),
        this.listLeadTasks(leadId),
        this.listLeadTrialLessons(leadId),
        this.listChatWorkTimeline("lead", leadId),
        // Field edits («кто поменял телефон»). Empty for non-staff; caught so a
        // missing audit list can not take the whole card down.
        this.timeline
          .listFieldAudit(actor, "lead", leadId, 50)
          .catch(() => ({ items: [] as Record<string, unknown>[] })),
      ]);

    const timeline = [
      ...comments.map((comment) => ({
        id: comment.id,
        type: "comment",
        title: "Комментарий",
        body: comment.body,
        status: null,
        occurredAt: comment.createdAt,
      })),
      ...tasks.map((task) => ({
        id: task.id,
        type: "task",
        title: task.title,
        body: task.description,
        status: task.status,
        occurredAt: task.createdAt,
      })),
      ...trials.map((lesson) => ({
        id: lesson.id,
        type: "trial",
        title: "Пробное занятие",
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
      lead: this.toLeadBoardItemDto(lead),
      linkedStudents: students,
      otherLeads,
      comments,
      tasks,
      trials,
      timeline,
    };
  }

  async listLeadStatusHistory(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      old_status: string | null;
      new_status: string | null;
      old_owner_id: string | null;
      new_owner_id: string | null;
      changed_by: string | null;
      changed_by_name: string | null;
      changed_at: string;
      reason_id: string | null;
      comment: string | null;
    }>(
      // changed_by alone is a raw user id — useless to a human reading the
      // history, so resolve the author's name here.
      `select h.id,
              os.name as old_status,
              ns.name as new_status,
              h.old_owner_id, h.new_owner_id, h.changed_by, h.changed_at,
              h.reason_id, h.comment,
              nullif(trim(coalesce(cp.first_name, '') || ' ' || coalesce(cp.last_name, '')), '') as changed_by_name
         from app.lead_status_history h
         left join app.lead_statuses os on os.id = h.old_status_id
         left join app.lead_statuses ns on ns.id = h.new_status_id
         left join app.users cu on cu.id = h.changed_by and cu.deleted_at is null
         left join app.profiles cp on cp.user_id = cu.id and cp.deleted_at is null
        where h.lead_id = $1
        order by h.changed_at desc`,
      [leadId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        oldStatus: row.old_status,
        newStatus: row.new_status,
        oldOwnerId: row.old_owner_id,
        newOwnerId: row.new_owner_id,
        changedBy: row.changed_by,
        changedByName: row.changed_by_name,
        changedAt: row.changed_at,
        reasonId: row.reason_id,
        comment: row.comment,
      })),
    };
  }

  // KVA-234: заявки лида из app.lead_applications (импорт HolliHop
  // GetStudyRequests, миграция 0050) — секция «Заявки» в карточке лида.
  async listLeadApplications(actor: ActorContext, leadId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      applied_at: string;
      channel: string | null;
      office: string | null;
      discipline: string | null;
      status: string | null;
      utm: Record<string, unknown> | null;
    }>(
      `select id, applied_at, channel, office, discipline, status, utm
         from app.lead_applications
        where lead_id = $1 and deleted_at is null
        order by applied_at desc`,
      [leadId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        appliedAt: row.applied_at,
        channel: row.channel,
        office: row.office,
        discipline: row.discipline,
        status: row.status,
        utm: row.utm,
      })),
    };
  }

  async listLeads(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    // This is what the «Объект» picker calls, so it needs the same search the
    // board has: by phone in any format, and across custom_data values.
    const params: unknown[] = [];
    const add = (value: unknown) => {
      params.push(value);
      return `$${params.length}`;
    };
    const search = q
      ? buildTextSearch({
          q,
          columns: [
            "l.first_name",
            "l.last_name",
            "l.email",
            "l.phone",
            "l.source",
          ],
          phoneColumn: "l.phone",
          customDataColumn: "l.custom_data",
          exactColumn: "concat_ws(' ', l.first_name, l.last_name)",
          add,
        })
      : null;
    const limitParam = add(limit);
    const result = await this.database.query<LeadRow>(
      `
        select l.id, l.status_id, ls.name as status_name, l.first_name,
          l.last_name, l.phone, l.email, l.source, l.notes, l.assigned_to, l.blacklisted, l.blacklist_reason, l.custom_data,
          l.created_by, l.created_at, l.updated_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where l.deleted_at is null
          ${search ? `and ${search.where}` : ""}
        order by ${search ? `${search.rank} asc,` : ""} l.created_at desc, l.id desc
        limit ${limitParam}
      `,
      params,
    );
    return { items: result.rows.map((row) => this.toLeadDto(row)) };
  }

  // Resolve the messenger user behind a lead so staff can jump straight into a
  // chat with them. Prefers an explicit user_crm_link, then falls back to a
  // client user whose profile phone matches the lead's phone.



  /**
   * Ручное «Прикрепить к ученику» из карточки лида (§1 спеки, эталон
   * HolliHop — ссылка «Прикрепить к ученику»).
   *
   * До этого связать лида с учеником можно было только через автоподбор
   * дублей: если система пару не нашла, прикрепить вручную было нельзя вовсе.
   */
  async linkStudentToLead(
    actor: ActorContext,
    leadId: string,
    studentId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const lead = await this.database.query<{ id: string }>(
      "select id from app.leads where id = $1 and deleted_at is null limit 1",
      [leadId],
    );
    if (!lead.rows[0]) throw new NotFoundException("Лид не найден.");
    const student = await this.database.query<{ id: string }>(
      "select id from app.students where id = $1 and deleted_at is null limit 1",
      [studentId],
    );
    if (!student.rows[0]) throw new NotFoundException("Ученик не найден.");

    // Бросит ConflictException, если ученик уже привязан к ДРУГОМУ лиду —
    // молча перевесить чужую связь нельзя.
    await attachStudentToLead(this.database, studentId, leadId);

    await this.audit.record({
      actor,
      action: "crm.lead_student_linked",
      entityType: "lead",
      entityId: leadId,
      metadata: { studentId },
    });
    this.realtime.emitCrmChanged({ entity: "lead", action: "updated", id: leadId });
    return { leadId, studentId };
  }

  async createLead(actor: ActorContext, dto: UpsertLeadDto) {
    this.policy.assertCanWriteCrm(actor);
    const branchId = extractBranchId(dto.customDataPatch);
    const result = await this.database.query<LeadRow>(
      `
        insert into app.leads (
          status_id, first_name, last_name, phone, email,
          source, notes, assigned_to, custom_data, created_by, branch_id
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        returning id, status_id, null::text as status_name, first_name,
          last_name, phone, email, source, notes, assigned_to,
          blacklisted, blacklist_reason, custom_data, created_by, created_at,
          updated_at
      `,
      [
        dto.statusId ?? null,
        dto.firstName?.trim() || null,
        dto.lastName?.trim() || null,
        dto.phone?.trim() || null,
        dto.email?.trim().toLowerCase() || null,
        dto.source?.trim() || null,
        dto.notes?.trim() || null,
        dto.assignedTo ?? null,
        sanitizeJsonObject(dto.customDataPatch),
        actor.userId,
        branchId,
      ],
    );
    const lead = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: lead.id,
    });
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "created",
      id: lead.id,
      branchId: branchId ?? null,
    });
    this.notifyNewLeadSafe(
      lead.id,
      [lead.first_name, lead.last_name].filter(Boolean).join(" ").trim() || "Без имени",
      lead.source?.trim() || "CRM",
    );
    return this.toLeadDto(lead);
  }

  async updateLead(actor: ActorContext, leadId: string, dto: UpsertLeadDto) {
    this.policy.assertCanWriteCrm(actor);
    const branchId = extractBranchId(dto.customDataPatch);
    // The update and its status-history row must land atomically: a failure in
    // between would move the lead while silently dropping the history entry.
    const { before, lead } = await this.database.transaction(async (client) => {
      // Reads the whole editable row, not just status/owner: the audit diff
      // below is what makes «кто поменял телефон» answerable, and it can only
      // report fields it saw beforehand.
      const beforeRes = await client.query<LeadRow & { branch_id: string | null }>(
        `select id, status_id, null::text as status_name, first_name, last_name,
           phone, email, source, notes, assigned_to, custom_data, created_by,
           created_at, updated_at, branch_id
         from app.leads where id = $1 and deleted_at is null for update`,
        [leadId],
      );
      const beforeRow = beforeRes.rows[0] ?? null;
      const result = await client.query<LeadRow>(
        `
        update app.leads
        set status_id = case when $11::boolean then null
                             else coalesce($2, status_id) end,
          first_name = coalesce($3, first_name),
          last_name = coalesce($4, last_name),
          phone = coalesce($5, phone),
          email = coalesce($6, email),
          source = coalesce($7, source),
          notes = coalesce($8, notes),
          assigned_to = coalesce($9, assigned_to),
          custom_data = custom_data || $10::jsonb,
          branch_id = coalesce($12::uuid, branch_id),
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, status_id, null::text as status_name, first_name,
          last_name, phone, email, source, notes, assigned_to,
          blacklisted, blacklist_reason, custom_data, created_by, created_at,
          updated_at
      `,
        [
          leadId,
          dto.statusId ?? null,
          dto.firstName?.trim() || null,
          dto.lastName?.trim() || null,
          dto.phone?.trim() || null,
          dto.email?.trim().toLowerCase() || null,
          dto.source?.trim() || null,
          dto.notes?.trim() || null,
          dto.assignedTo ?? null,
          sanitizeJsonObject(dto.customDataPatch),
          dto.clearStatus ?? false,
          branchId,
        ],
      );
      const updatedLead = result.rows[0];
      if (
        updatedLead &&
        beforeRow &&
        (beforeRow.status_id !== updatedLead.status_id ||
          beforeRow.assigned_to !== updatedLead.assigned_to)
      ) {
        await client.query(
          `insert into app.lead_status_history
           (lead_id, old_status_id, new_status_id, old_owner_id, new_owner_id,
            changed_by, reason_id, comment, branch_id, source_snapshot)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
          [
            leadId,
            beforeRow.status_id,
            updatedLead.status_id,
            beforeRow.assigned_to,
            updatedLead.assigned_to,
            actor.userId,
            dto.reasonId ?? null,
            dto.statusComment ?? null,
            branchId ?? beforeRow.branch_id,
            updatedLead.source,
          ],
        );
      }
      return { before: beforeRow, lead: updatedLead };
    });
    if (!lead) throw new NotFoundException("Лид не найден.");
    await this.audit.record({
      actor,
      action: "crm.lead_updated",
      entityType: "lead",
      entityId: lead.id,
      // The diff is the event. Without it the card could only say «лид
      // обновлён», which answers none of «кто поменял телефон и на какой».
      metadata: {
        changes: before
          ? diffEntityFields(
              before as unknown as Record<string, unknown>,
              lead as unknown as Record<string, unknown>,
              LEAD_AUDITED_FIELDS,
            )
          : [],
      },
    });
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "updated",
      id: lead.id,
      branchId: branchId ?? before?.branch_id ?? null,
    });
    return this.toLeadDto(lead);
  }

  async deleteLead(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.leads
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [leadId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Лид не найден.");
    await this.audit.record({
      actor,
      action: "crm.lead_deleted",
      entityType: "lead",
      entityId: row.id,
    });
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "deleted",
      id: row.id,
    });
    return { success: true };
  }

  // Auto-create a lead when a non-staff user first writes to the admin chat.
  // Idempotent: skips if the user is already linked to a lead or student.
  // Uses a pg advisory lock (per-user) to serialize concurrent first messages
  // so that both the check and the create happen inside a single transaction,
  // preventing duplicate leads from a race between two rapid chat messages.



  // Fire-and-forget staff notification about a new lead. A notification
  // failure (sync or async) must NEVER break lead creation — log and move on.
  private notifyNewLeadSafe(leadId: string, name: string, source: string): void {
    try {
      void this.notifications
        .notifyNewLead({ leadId, name, source })
        .catch((error: unknown) => {
          this.logger.warn(
            `New lead notification failed for ${leadId}: ${String(error)}`,
          );
        });
    } catch (error: unknown) {
      this.logger.warn(
        `New lead notification failed for ${leadId}: ${String(error)}`,
      );
    }
  }


  private buildLeadBoardFilter(query: LeadBoardQuery) {
    const params: unknown[] = [];
    const filters = ["l.deleted_at is null"];
    const add = (value: unknown) => {
      params.push(value);
      return `$${params.length}`;
    };
    const q = query.q?.trim();
    if (q) {
      // Predicate only: the board is cursor-paginated on (created_at, id), so
      // reordering it by relevance would break the cursor.
      filters.push(
        buildTextSearch({
          q,
          columns: [
            "l.first_name",
            "l.last_name",
            "l.email",
            "l.phone",
            "l.source",
            "l.notes",
          ],
          phoneColumn: "l.phone",
          customDataColumn: "l.custom_data",
          add,
        }).where,
      );
    }
    if (query.statusId) {
      filters.push(`l.status_id = ${add(query.statusId)}::uuid`);
    }
    if (query.assignedTo) {
      filters.push(`l.assigned_to = ${add(query.assignedTo)}::uuid`);
    }
    if (query.branchId) {
      const p = add(query.branchId);
      filters.push(
        `${branchIdExpr("l")} = ${p}::text`,
      );
    }
    this.addLeadTextFilter(filters, add, "l.source", query.source);
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'discipline', l.custom_data->>'disciplineName', l.custom_data->>'discipline_name')",
      query.discipline,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'level', l.custom_data->>'levelName', l.custom_data->>'level_name')",
      query.level,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'category', l.custom_data->>'categoryName', l.custom_data->>'category_name', l.custom_data->>'maturity')",
      query.category,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'requestType', l.custom_data->>'request_type', l.custom_data->>'type')",
      query.requestType,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'goal', l.custom_data->>'learningGoal', l.custom_data->>'learning_goal')",
      query.goal,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'gender', l.custom_data->>'sex')",
      query.gender,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'preferredSchedule', l.custom_data->>'preferred_schedule')",
      query.preferredSchedule,
      true,
    );
    if (query.from) {
      filters.push(`l.created_at >= ${add(query.from)}::timestamptz`);
    }
    if (query.to) {
      filters.push(`l.created_at < ${add(query.to)}::timestamptz`);
    }
    if (query.openTasks === true) {
      filters.push(`
        exists (
          select 1
          from app.tasks open_task
          where open_task.deleted_at is null
            and open_task.entity_type = 'lead'
            and open_task.entity_id = l.id
            and open_task.status in ('open', 'in_progress')
        )
      `);
    }
    if (query.hideConverted === true) {
      // Правило «ученик и лид — один человек» живёт в одном месте на всю
      // систему: им же импорт проставляет students.lead_id. Разъедутся —
      // карточки начнут двоиться. См. leadStudentMatchSql.
      filters.push(`
        not exists (
          select 1
          from app.students linked_conv
          left join app.profiles p_conv
            on p_conv.id = linked_conv.profile_id
           and p_conv.deleted_at is null
          where linked_conv.deleted_at is null
            and linked_conv.status = 'active'
            and (
              linked_conv.lead_id = l.id
              or (${leadStudentMatchSql("l", "p_conv")})
            )
        )
      `);
    }
    const cursor = this.decodeLeadCursor(query.cursor);
    if (cursor) {
      const createdAt = add(cursor.createdAt);
      const id = add(cursor.id);
      filters.push(
        `(l.created_at, l.id) < (${createdAt}::timestamptz, ${id}::uuid)`,
      );
    }

    const quick = query.quick ?? "all";
    if (quick !== "all") {
      const groupExpr =
        "lower(coalesce(l.custom_data->>'statusGroup', l.custom_data->>'status_group', ''))";
      const statusExpr = "lower(coalesce(ls.name, ''))";
      const processed = `${groupExpr} = 'processed' or ${statusExpr} like '%обработ%' or ${statusExpr} like '%закрыт%' or ${statusExpr} like '%отказ%' or ${statusExpr} like '%processed%'`;
      const deferred = `${groupExpr} = 'deferred' or ${statusExpr} like '%отлож%' or ${statusExpr} like '%перезвон%' or ${statusExpr} like '%defer%'`;
      if (quick === "processed") {
        filters.push(`(${processed})`);
      } else if (quick === "deferred") {
        filters.push(`(${deferred})`);
      } else if (quick === "new") {
        // «Новые» = no status assigned yet, or an explicit «Новый». Mirrors the
        // overview `new_leads_count` metric so the tile and this filter agree.
        filters.push(`(l.status_id is null or ${statusExpr} in ('new', 'новый'))`);
      } else {
        filters.push(`not (${processed}) and not (${deferred})`);
      }
    }

    return { where: filters.join("\n          and "), params };
  }

  private addLeadTextFilter(
    filters: string[],
    add: (value: unknown) => string,
    expression: string,
    value: string | undefined,
    fuzzy = false,
  ) {
    const trimmed = value?.trim();
    if (!trimmed) return;
    const p = add(trimmed);
    filters.push(
      fuzzy
        ? `lower(${expression}) like lower('%' || ${p}::text || '%')`
        : `lower(${expression}) = lower(${p}::text)`,
    );
  }

  private encodeLeadCursor(row: { created_at: Date | string; id: string }) {
    const createdAt =
      row.created_at instanceof Date
        ? row.created_at.toISOString()
        : String(row.created_at);
    return `${createdAt}|${row.id}`;
  }

  private decodeLeadCursor(cursor: string | undefined) {
    if (!cursor) return null;
    const [createdAt, id] = cursor.split("|");
    if (!createdAt || !id || Number.isNaN(Date.parse(createdAt))) return null;
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        id,
      )
    ) {
      return null;
    }
    return { createdAt, id };
  }

  private async listStudentsLinkedToLead(leadId: string) {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone,
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
    return result.rows.map((row) => this.toStudentDto(row));
  }

  private async listRelatedLeads(lead: LeadRow) {
    if (!lead.phone && !lead.email) return [];
    const result = await this.database.query<LeadRow>(
      `
        select l.id, l.status_id, ls.name as status_name, l.first_name,
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
    return result.rows.map((row) => this.toLeadDto(row));
  }

  private async listLeadComments(leadId: string) {
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
    return result.rows.map((row) => this.toCommentDto(row));
  }

  private async listLeadTasks(leadId: string) {
    const result = await this.database.query<TaskRow>(
      `
        select task.id, task.entity_type, task.entity_id, task.assigned_to,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          null::text as entity_first_name,
          null::text as entity_last_name,
          null::text as entity_name,
          task.title, task.description, task.status, task.due_at,
          task.created_by, task.created_at
        from app.tasks task
        left join app.users assigned_user on assigned_user.id = task.assigned_to and assigned_user.deleted_at is null
        left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
        where task.deleted_at is null
          and task.entity_type = 'lead'
          and task.entity_id = $1
        order by task.due_at nulls last, task.created_at desc, task.id desc
        limit 50
      `,
      [leadId],
    );
    return result.rows.map((row) => toTaskDto(row));
  }

  private async listLeadTrialLessons(leadId: string) {
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
    return result.rows.map((row) => toLessonDto(row));
  }

  // Chat "taken into work" events belong to the messenger schema
  // (app.chats / app.chat_work_events); read them through the messenger-owned
  // ChatWorkTimelineService instead of inlining that SQL here.
  private async listChatWorkTimeline(
    entityType: "student" | "lead",
    entityId: string,
  ) {
    const rows = await this.chatWork.listForEntity(entityType, entityId);
    return rows.map((row) => toTimelineDto(row));
  }

  private toLeadDto(row: LeadRow) {
    // ✔ Решение владельца 16.07: лид, пришедший через приложение, получает
    // датой обращения момент, когда он тут появился; у импортированного
    // побеждает исходная дата HolliHop (custom_data.addressDate).
    const appeal = resolveAppealDate(row.custom_data, row.created_at);
    // ✔ Решение владельца 17.07: возраст либо вписан руками, либо считается из
    // даты рождения и сам меняется с годами. Резолвится на чтении: хранить
    // посчитанное число было бы обещанием пересчитывать его каждую ночь.
    const age = resolveAge(row.custom_data);
    return {
      id: row.id,
      statusId: row.status_id,
      statusName: row.status_name,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      email: presentableEmail(row.email),
      source: row.source,
      notes: row.notes,
      assignedTo: row.assigned_to,
      customData: row.custom_data ?? {},
      createdBy: row.created_by,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      appealAt: appeal.value,
      appealAtSource: appeal.source,
      age: age.years,
      ageMonths: age.months,
      ageSource: age.source,
      // Чёрный список = бан (✔ владелец 17.07). Карточка красит себя по нему,
      // мессенджер по нему же запрещает отправку — см. blacklist.ts.
      blacklisted: row.blacklisted === true,
      blacklistReason: row.blacklist_reason ?? null,
    };
  }

  private toLeadBoardItemDto(row: LeadBoardRow) {
    const assignedName =
      `${row.assigned_first_name ?? ""} ${row.assigned_last_name ?? ""}`.trim();
    return {
      ...this.toLeadDto(row),
      statusColor: row.status_color,
      statusSortOrder: row.status_sort_order,
      assignedName: assignedName || null,
      branchId: row.branch_id,
      branchName: row.branch_name,
      linkedStudentId: row.linked_student_id,
      openTasksCount: this.toNumericStat(row.open_tasks_count),
      commentsCount: this.toNumericStat(row.comments_count),
      trialLessonsCount: this.toNumericStat(row.trial_lessons_count),
    };
  }

  private toLeadStatusDto(row: LeadStatusRow) {
    return {
      id: row.id,
      name: row.name,
      color: row.color,
      sortOrder: row.sort_order,
      createdAt: row.created_at,
      requiresReason: row.requires_reason ?? false,
      isTerminal: row.is_terminal ?? false,
    };
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
    };
  }

  private toStudentDto(row: StudentRow) {
    return {
      id: row.id,
      leadId: row.lead_id,
      status: row.status,
      customData: row.custom_data ?? {},
      profileId: row.profile_id,
      profileUserId: row.profile_user_id,
      firstName: row.first_name,
      lastName: row.last_name,
      email: presentableEmail(row.email),
      phone: row.phone,
      teacherUserIds: row.teacher_user_ids ?? [],
      createdAt: row.created_at,
    };
  }

  private toNumericStat(value: string | number | null | undefined): number {
    if (value === null || value === undefined) return 0;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }
}
