import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { GroupListQuery } from "./dto/group-lifecycle.dto";
import { UpdateGroupDto } from "./dto/update-group.dto";
import { UpsertGroupDto } from "./dto/upsert-group.dto";
import { CrmPolicy } from "./crm.policy";
import { audienceForGroup, audienceForStudent } from "./audience";
import { branchIdExpr, managerBranchScopeSql } from "./branch-scope";
import { requiredTrim } from "./crm-util";
import { assertSettingsBranchScope } from "./settings-branch-scope";
import { assertGroupBranchScope } from "./group-branch-scope";

interface GroupRow {
  id: string;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  name: string;
  price_per_lesson: string | null;
  // KVA-238: переопределение ставки педагога (null = брать ставку педагога).
  teacher_rate?: string | number | null;
  teacher_name: string | null;
  branch_name: string | null;
  room_name: string | null;
  students_count?: string | number | null;
  lifecycle_state: "active" | "archived";
  version: string | number;
  archived_at: Date | string | null;
  archive_reason: string | null;
  archive_effective_date: string | null;
  created_at: Date | string;
}

interface GroupAssignmentImpactRow {
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  future_lessons: string | number;
  active_series: string | number;
  active_plans: string | number;
}

/**
 * Groups domain, extracted from CrmService (SRP): group CRUD and membership
 * mutations (add/remove student). Touches `app.groups` / `app.group_students`
 * and the shared database/audit/policy/realtime collaborators. The two
 * student-shaped group reads (listStudentGroups, listGroupStudents) stay in
 * CrmService for now — they depend on the core student helpers (findStudent,
 * toStudentDto) and fold into the students/groups reconciliation in B5.
 */
@Injectable()
export class GroupsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  // ponytail: toGroupDto/GroupRow are duplicated from CrmService, which still
  // uses them for listStudentGroups. Fold into a shared mapper in B5.
  private toGroupDto(row: GroupRow) {
    return {
      id: row.id,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      name: row.name,
      pricePerLesson:
        row.price_per_lesson === null ? null : Number(row.price_per_lesson),
      // KVA-238: null = брать ставку педагога, 0 = «входит в оклад».
      teacherRate:
        row.teacher_rate === null || row.teacher_rate === undefined
          ? null
          : Number(row.teacher_rate),
      teacherName: row.teacher_name || null,
      branchName: row.branch_name,
      roomName: row.room_name,
      studentsCount: Number(row.students_count ?? 0),
      lifecycleState: row.lifecycle_state,
      version: Number(row.version),
      archivedAt: row.archived_at,
      archiveReason: row.archive_reason,
      archiveEffectiveDate: row.archive_effective_date,
      createdAt: row.created_at,
    };
  }

  async listGroups(actor: ActorContext, query: GroupListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const includeArchived = query.includeArchived === true;
    if (includeArchived) this.policy.assertCanManageSystemSettings(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<GroupRow>(
      `
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson, g.teacher_rate,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          (select count(*) from app.group_students membership
            where membership.group_id = g.id and membership.left_at is null
          ) as students_count,
          g.lifecycle_state, g.version, g.archived_at, g.archive_reason,
          g.archive_effective_date, g.created_at
        from app.groups g
        left join app.teachers t on t.id = g.teacher_id
        left join app.profiles tp on tp.id = t.profile_id
        left join app.branches b on b.id = g.branch_id
        left join app.rooms r on r.id = g.room_id
        where ($6::boolean or g.deleted_at is null)
          and (
            $4::text <> 'manager'
            or exists (
              select 1
              from app.user_crm_links link
              join app.staff_members staff on staff.id = link.entity_id
                and link.entity_type = 'staff' and link.deleted_at is null
                and staff.deleted_at is null
              join app.staff_branch_assignments assignment
                on assignment.staff_member_id = staff.id
                and assignment.deleted_at is null
              where link.user_id = $5 and assignment.branch_id = g.branch_id
            )
          )
          and ($1::uuid is null or g.branch_id = $1)
          and (
            $2::text is null
            or lower(coalesce(g.name, '') || ' ' || coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) like lower('%' || $2 || '%')
          )
        order by (g.lifecycle_state = 'archived') asc, g.name asc, g.id asc
        limit $3
      `,
      [
        query.branchId ?? null,
        q || null,
        limit,
        actor.role,
        actor.userId,
        includeArchived,
      ],
    );

    return { items: result.rows.map((row) => this.toGroupDto(row)) };
  }

  // Single group by id. Needed to open a group card from a context that only
  // carries an id (e.g. a task pointing at a group): the list endpoint is
  // capped at 100 rows, so filtering it client-side silently misses groups.
  async getGroup(actor: ActorContext, groupId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<GroupRow>(
      `
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson, g.teacher_rate,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.lifecycle_state, g.version, g.archived_at, g.archive_reason,
          g.archive_effective_date, g.created_at
        from app.groups g
        left join app.teachers t on t.id = g.teacher_id
        left join app.profiles tp on tp.id = t.profile_id
        left join app.branches b on b.id = g.branch_id
        left join app.rooms r on r.id = g.room_id
        where g.id = $1
      `,
      [groupId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Группа не найдена.");
    await assertGroupBranchScope(this.database, actor, groupId, row.branch_id);
    return this.toGroupDto(row);
  }

  async createGroup(actor: ActorContext, dto: UpsertGroupDto) {
    this.policy.assertCanManageSystemSettings(actor);
    await assertSettingsBranchScope(this.database, actor, dto.branchId);
    const name = requiredTrim(dto.name, "Название группы обязательно.");
    const result = await this.database.query<GroupRow>(
      `
        with valid_references as (
          select b.id as branch_id, t.id as teacher_id, r.id as room_id
          from app.branches b
          join app.teacher_branches tb
            on tb.branch_id = b.id and tb.teacher_id = $1
            and tb.active_from <= current_date
            and (tb.active_until is null or tb.active_until >= current_date)
          join app.teachers t
            on t.id = tb.teacher_id and t.deleted_at is null
            and lower(t.status) in ('active', 'working', 'активен', 'работает')
          join app.rooms r
            on r.id = $3 and r.branch_id = b.id and r.deleted_at is null
            and r.lifecycle_state = 'active'
          where b.id = $2 and b.deleted_at is null
            and b.lifecycle_state = 'active'
          for share of b, tb, t, r
        ),
        inserted_group as (
          insert into app.groups (
            teacher_id,
            branch_id,
            room_id,
            name,
            price_per_lesson,
            teacher_rate
          )
          select teacher_id, branch_id, room_id, $4, $5, $6
          from valid_references
          returning id, teacher_id, branch_id, room_id, name, price_per_lesson,
            teacher_rate, lifecycle_state, version, archived_at, archive_reason,
            archive_effective_date, created_at
        )
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson, g.teacher_rate,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.lifecycle_state, g.version, g.archived_at, g.archive_reason,
          g.archive_effective_date, g.created_at
        from inserted_group g
        left join app.teachers t on t.id = g.teacher_id
        left join app.profiles tp on tp.id = t.profile_id
        left join app.branches b on b.id = g.branch_id
        left join app.rooms r on r.id = g.room_id
        limit 1
      `,
      [
        dto.teacherId,
        dto.branchId,
        dto.roomId,
        name,
        dto.pricePerLesson ?? null,
        dto.teacherRate ?? null,
      ],
    );
    const group = result.rows[0];
    if (!group) {
      throw new BadRequestException(
        "Выберите действующий филиал, назначенного в него преподавателя и аудиторию этого филиала.",
      );
    }
    await this.audit.record({
      actor,
      action: "crm.group_created",
      entityType: "group",
      entityId: group.id,
    });
    const affectedUserIds = await audienceForGroup(this.database, group.id);
    this.realtime.emitCrmChanged({
      entity: "group",
      action: "created",
      id: group.id,
      branchId: group.branch_id ?? null,
      affectedUserIds,
    });
    return this.toGroupDto(group);
  }

  /**
   * KVA-238: частичное обновление группы (PATCH), в т.ч. ставка педагога по
   * группе из drill-down отчёта «Статистика преподавателей». teacherRate:
   * null сбрасывает переопределение (брать ставку педагога), 0 — «входит в
   * оклад»; поле применяется только если передано (dto.teacherRate !== undefined).
   */
  async updateGroup(actor: ActorContext, groupId: string, dto: UpdateGroupDto) {
    this.policy.assertCanManageSystemSettings(actor);
    const name =
      dto.name === undefined
        ? null
        : requiredTrim(dto.name, "Название группы обязательно.");
    const teacherRateProvided = dto.teacherRate !== undefined;
    const referencesProvided =
      dto.teacherId !== undefined ||
      dto.branchId !== undefined ||
      dto.roomId !== undefined;
    await this.assertAssignmentChangeAllowed(actor, groupId, dto);
    const result = await this.database.query<GroupRow>(
      `
        with target as (
          select g.*,
            coalesce($3::uuid, g.teacher_id) as next_teacher_id,
            coalesce($4::uuid, g.branch_id) as next_branch_id,
            coalesce($5::uuid, g.room_id) as next_room_id
          from app.groups g
          where g.id = $1 and g.deleted_at is null
        ),
        valid_references as (
          select target.id from target where not $9::boolean
          union all
          select target.id
          from target
          join app.branches b
            on b.id = target.next_branch_id and b.deleted_at is null
          join app.teacher_branches tb
            on tb.branch_id = b.id and tb.teacher_id = target.next_teacher_id
            and tb.active_from <= current_date
            and (tb.active_until is null or tb.active_until >= current_date)
          join app.teachers t
            on t.id = tb.teacher_id and t.deleted_at is null
            and lower(t.status) in ('active', 'working', 'активен', 'работает')
          join app.rooms r
            on r.id = target.next_room_id and r.branch_id = b.id
            and r.deleted_at is null
          where $9::boolean
        ),
        updated_group as (
          update app.groups g
          set name = coalesce($2, g.name),
            teacher_id = coalesce($3::uuid, g.teacher_id),
            branch_id = coalesce($4::uuid, g.branch_id),
            room_id = coalesce($5::uuid, g.room_id),
            price_per_lesson = coalesce($6::numeric, g.price_per_lesson),
            teacher_rate = case when $7::boolean then $8::numeric else g.teacher_rate end,
            updated_at = now()
          from valid_references
          where g.id = valid_references.id
          returning g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
            g.price_per_lesson, g.teacher_rate, g.lifecycle_state, g.version,
            g.archived_at, g.archive_reason, g.archive_effective_date, g.created_at
        )
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson, g.teacher_rate,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.lifecycle_state, g.version, g.archived_at, g.archive_reason,
          g.archive_effective_date, g.created_at
        from updated_group g
        left join app.teachers t on t.id = g.teacher_id
        left join app.profiles tp on tp.id = t.profile_id
        left join app.branches b on b.id = g.branch_id
        left join app.rooms r on r.id = g.room_id
        limit 1
      `,
      [
        groupId,
        name,
        dto.teacherId ?? null,
        dto.branchId ?? null,
        dto.roomId ?? null,
        dto.pricePerLesson ?? null,
        teacherRateProvided,
        teacherRateProvided ? dto.teacherRate : null,
        referencesProvided,
      ],
    );
    const group = result.rows[0];
    if (!group) {
      throw new BadRequestException(
        "Группа не найдена или преподаватель/аудитория не относятся к выбранному филиалу.",
      );
    }
    await this.audit.record({
      actor,
      action: "crm.group_updated",
      entityType: "group",
      entityId: group.id,
      metadata: teacherRateProvided
        ? { teacherRate: dto.teacherRate ?? null }
        : undefined,
    });
    const affectedUserIds = await audienceForGroup(this.database, group.id);
    this.realtime.emitCrmChanged({
      entity: "group",
      action: "updated",
      id: group.id,
      branchId: group.branch_id ?? null,
      affectedUserIds,
    });
    return this.toGroupDto(group);
  }

  private async assertAssignmentChangeAllowed(
    actor: ActorContext,
    groupId: string,
    dto: UpdateGroupDto,
  ) {
    const result = await this.database.query<GroupAssignmentImpactRow>(
      `select target.teacher_id, target.branch_id, target.room_id,
          (select count(*) from app.lessons item
            where item.group_id = target.id and item.deleted_at is null
              and item.scheduled_at >= now()
              and item.lifecycle_state in ('scheduled', 'settlement_pending')) as future_lessons,
          (select count(*) from app.schedule_series item
            where item.group_id = target.id and item.deleted_at is null
              and item.superseded_by is null
              and (item.valid_until is null or item.valid_until >= current_date)) as active_series,
          (select count(*) from app.schedule_plans item
            where item.group_id = target.id and item.status = 'active') as active_plans
       from app.groups target
       where target.id = $1 and target.deleted_at is null`,
      [groupId],
    );
    const current = result.rows[0];
    if (!current) throw new NotFoundException("Группа не найдена.");
    if (current.branch_id) {
      await assertSettingsBranchScope(this.database, actor, current.branch_id);
    } else if (actor.role === "manager") {
      throw new ForbiddenException("Группа не относится к доступному филиалу.");
    }
    const nextBranchId = dto.branchId ?? current.branch_id;
    if (nextBranchId && nextBranchId !== current.branch_id) {
      await assertSettingsBranchScope(this.database, actor, nextBranchId);
    }
    const changed =
      (dto.teacherId !== undefined && dto.teacherId !== current.teacher_id) ||
      (dto.branchId !== undefined && dto.branchId !== current.branch_id) ||
      (dto.roomId !== undefined && dto.roomId !== current.room_id);
    if (!changed) return;

    const blockers = [
      {
        code: "FUTURE_LESSONS",
        label: "Будущие занятия",
        count: Number(current.future_lessons),
        remediation: "Перенесите или отмените будущие занятия группы.",
      },
      {
        code: "ACTIVE_RECURRING_SERIES",
        label: "Активные серии",
        count: Number(current.active_series),
        remediation: "Завершите постоянные серии группы.",
      },
      {
        code: "ACTIVE_SCHEDULE_PLANS",
        label: "Постоянные планы",
        count: Number(current.active_plans),
        remediation: "Завершите постоянные планы группы.",
      },
    ].filter((item) => item.count > 0);
    if (blockers.length > 0) {
      throw new UnprocessableEntityException({
        code: "GROUP_ASSIGNMENT_CHANGE_BLOCKED",
        message:
          "Нельзя менять филиал, аудиторию или преподавателя, пока у группы есть активное расписание.",
        blockers,
      });
    }
  }

  async addGroupStudent(
    actor: ActorContext,
    groupId: string,
    studentId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    await assertGroupBranchScope(this.database, actor, groupId);
    const result = await this.database.query<{
      id: string;
      student_id: string;
    }>(
      `
        with target_group as (
          select id from app.groups where id = $1 and deleted_at is null
        ),
        target_student as (
          select s.id
          from app.students s
          where s.id = $2
            and s.deleted_at is null
            and ${managerBranchScopeSql({
              roleExpression: "$3",
              userIdExpression: "$4",
              branchExpression: branchIdExpr("s"),
            })}
        )
        insert into app.group_students (group_id, student_id, left_at)
        select target_group.id, target_student.id, null
        from target_group, target_student
        on conflict (group_id, student_id)
        do update set left_at = null
        returning id, student_id
      `,
      [groupId, studentId, actor.role, actor.userId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Группа или ученик не найдены.");
    await this.audit.record({
      actor,
      action: "crm.group_student_added",
      entityType: "group",
      entityId: groupId,
      metadata: { studentId: row.student_id },
    });
    const [groupUserIds, studentUserIds] = await Promise.all([
      audienceForGroup(this.database, groupId),
      audienceForStudent(this.database, row.student_id),
    ]);
    this.realtime.emitCrmChanged({
      entity: "group",
      action: "updated",
      id: groupId,
      affectedUserIds: Array.from(
        new Set([...groupUserIds, ...studentUserIds]),
      ),
    });
    return { success: true };
  }

  async removeGroupStudent(
    actor: ActorContext,
    groupId: string,
    studentId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    await assertGroupBranchScope(this.database, actor, groupId);
    const result = await this.database.transaction(async (client) => {
      // Schedule-plan writes use the same aggregate lock. A membership cannot
      // disappear between participant validation and the plan commit.
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [`group:${groupId}`],
      );
      const blockers = await client.query<{ id: string; title: string }>(
        `select distinct plan.id, plan.title
         from app.schedule_plans plan
         join app.schedule_plan_participants participant
           on participant.plan_id = plan.id
          and participant.student_id = $2
         where plan.group_id = $1
           and plan.kind = 'group'
           and plan.status = 'active'
           and (participant.effective_until is null
             or participant.effective_until >= current_date)
         order by plan.title, plan.id`,
        [groupId, studentId],
      );
      if (blockers.rows.length > 0) {
        throw new ConflictException({
          code: "GROUP_STUDENT_ACTIVE_SCHEDULE_PLAN",
          message:
            "Сначала исключите ученика из активных постоянных расписаний группы.",
          plans: blockers.rows.map((plan) => ({
            id: plan.id,
            title: plan.title,
          })),
        });
      }
      return client.query<{ id: string }>(
        `update app.group_students
         set left_at = now()
         where group_id = $1
           and student_id = $2
           and left_at is null
         returning id`,
        [groupId, studentId],
      );
    });
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Ученик не найден в группе.");
    await this.audit.record({
      actor,
      action: "crm.group_student_removed",
      entityType: "group",
      entityId: groupId,
      metadata: { studentId },
    });
    const [groupUserIds, studentUserIds] = await Promise.all([
      audienceForGroup(this.database, groupId),
      audienceForStudent(this.database, studentId),
    ]);
    this.realtime.emitCrmChanged({
      entity: "group",
      action: "updated",
      id: groupId,
      affectedUserIds: Array.from(
        new Set([...groupUserIds, ...studentUserIds]),
      ),
    });
    return { success: true };
  }
}
