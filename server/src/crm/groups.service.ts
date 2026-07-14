import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmListQuery } from "./dto/crm-list.query";
import { UpdateGroupDto } from "./dto/update-group.dto";
import { UpsertGroupDto } from "./dto/upsert-group.dto";
import { CrmPolicy } from "./crm.policy";

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
  created_at: Date | string;
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
  // uses them for listStudentGroups. requiredTrim/affectedUserIdsForStudent are
  // shared helpers copied here. All fold into shared mappers/AudienceResolver in B4/B5.
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
      createdAt: row.created_at,
    };
  }

  private requiredTrim(value: string | undefined, message: string): string {
    const trimmed = value?.trim();
    if (!trimmed) throw new BadRequestException(message);
    return trimmed;
  }

  async listGroups(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<GroupRow>(
      `
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson, g.teacher_rate,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.created_at
        from app.groups g
        left join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = g.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = g.room_id and r.deleted_at is null
        where g.deleted_at is null
          and ($1::uuid is null or g.branch_id = $1)
          and (
            $2::text is null
            or lower(coalesce(g.name, '') || ' ' || coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) like lower('%' || $2 || '%')
          )
        order by g.name asc, g.id asc
        limit $3
      `,
      [query.branchId ?? null, q || null, limit],
    );

    return { items: result.rows.map((row) => this.toGroupDto(row)) };
  }

  async createGroup(actor: ActorContext, dto: UpsertGroupDto) {
    this.policy.assertCanWriteCrm(actor);
    const name = this.requiredTrim(dto.name, "Название группы обязательно.");
    const result = await this.database.query<GroupRow>(
      `
        with inserted_group as (
          insert into app.groups (
            teacher_id,
            branch_id,
            room_id,
            name,
            price_per_lesson,
            teacher_rate
          )
          values ($1, $2, $3, $4, $5, $6)
          returning id, teacher_id, branch_id, room_id, name, price_per_lesson,
            teacher_rate, created_at
        )
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson, g.teacher_rate,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.created_at
        from inserted_group g
        left join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = g.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = g.room_id and r.deleted_at is null
        limit 1
      `,
      [
        dto.teacherId ?? null,
        dto.branchId ?? null,
        dto.roomId ?? null,
        name,
        dto.pricePerLesson ?? null,
        dto.teacherRate ?? null,
      ],
    );
    const group = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.group_created",
      entityType: "group",
      entityId: group.id,
    });
    const affectedUserIds = await this.affectedUserIdsForGroup(group.id);
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
    this.policy.assertCanWriteCrm(actor);
    const name =
      dto.name === undefined
        ? null
        : this.requiredTrim(dto.name, "Название группы обязательно.");
    const teacherRateProvided = dto.teacherRate !== undefined;
    const result = await this.database.query<GroupRow>(
      `
        with updated_group as (
          update app.groups g
          set name = coalesce($2, g.name),
            teacher_id = coalesce($3::uuid, g.teacher_id),
            branch_id = coalesce($4::uuid, g.branch_id),
            room_id = coalesce($5::uuid, g.room_id),
            price_per_lesson = coalesce($6::numeric, g.price_per_lesson),
            teacher_rate = case when $7::boolean then $8::numeric else g.teacher_rate end,
            updated_at = now()
          where g.id = $1 and g.deleted_at is null
          returning g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
            g.price_per_lesson, g.teacher_rate, g.created_at
        )
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson, g.teacher_rate,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.created_at
        from updated_group g
        left join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = g.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = g.room_id and r.deleted_at is null
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
      ],
    );
    const group = result.rows[0];
    if (!group) throw new NotFoundException("Группа не найдена.");
    await this.audit.record({
      actor,
      action: "crm.group_updated",
      entityType: "group",
      entityId: group.id,
      metadata: teacherRateProvided
        ? { teacherRate: dto.teacherRate ?? null }
        : undefined,
    });
    const affectedUserIds = await this.affectedUserIdsForGroup(group.id);
    this.realtime.emitCrmChanged({
      entity: "group",
      action: "updated",
      id: group.id,
      branchId: group.branch_id ?? null,
      affectedUserIds,
    });
    return this.toGroupDto(group);
  }

  async addGroupStudent(
    actor: ActorContext,
    groupId: string,
    studentId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      student_id: string;
    }>(
      `
        with target_group as (
          select id from app.groups where id = $1 and deleted_at is null
        ),
        target_student as (
          select id from app.students where id = $2 and deleted_at is null
        )
        insert into app.group_students (group_id, student_id, left_at)
        select target_group.id, target_student.id, null
        from target_group, target_student
        on conflict (group_id, student_id)
        do update set left_at = null
        returning id, student_id
      `,
      [groupId, studentId],
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
      this.affectedUserIdsForGroup(groupId),
      this.affectedUserIdsForStudent(row.student_id),
    ]);
    this.realtime.emitCrmChanged({
      entity: "group",
      action: "updated",
      id: groupId,
      affectedUserIds: Array.from(new Set([...groupUserIds, ...studentUserIds])),
    });
    return { success: true };
  }

  async removeGroupStudent(
    actor: ActorContext,
    groupId: string,
    studentId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.group_students
        set left_at = now()
        where group_id = $1
          and student_id = $2
          and left_at is null
        returning id
      `,
      [groupId, studentId],
    );
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
      this.affectedUserIdsForGroup(groupId),
      this.affectedUserIdsForStudent(studentId),
    ]);
    this.realtime.emitCrmChanged({
      entity: "group",
      action: "updated",
      id: groupId,
      affectedUserIds: Array.from(new Set([...groupUserIds, ...studentUserIds])),
    });
    return { success: true };
  }

  private async affectedUserIdsForGroup(groupId: string): Promise<string[]> {
    const result = await this.database.query<{ user_id: string }>(
      `
        select distinct user_id
        from (
          select tp.user_id
          from app.groups g
          join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
          join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          where g.id = $1 and g.deleted_at is null and tp.user_id is not null
          union
          select sp.user_id
          from app.group_students gs
          join app.students s on s.id = gs.student_id and s.deleted_at is null
          join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
          where gs.group_id = $1 and gs.left_at is null and sp.user_id is not null
          union
          select link.user_id
          from app.group_students gs
          join app.user_crm_links link
            on link.entity_type = 'student'
           and link.entity_id = gs.student_id
           and link.deleted_at is null
          where gs.group_id = $1 and gs.left_at is null
        ) affected
        where user_id is not null
      `,
      [groupId],
    );
    return (result?.rows ?? []).map((row) => row.user_id);
  }

  // ponytail: copied from CrmService (also used by its retained student methods).
  // Lift into the shared AudienceResolver in B4.
  private async affectedUserIdsForStudent(
    studentId: string | null | undefined,
  ): Promise<string[]> {
    if (!studentId) return [];
    const result = await this.database.query<{ user_id: string }>(
      `
        select distinct user_id
        from (
          select p.user_id
          from app.students s
          join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          where s.id = $1 and s.deleted_at is null and p.user_id is not null
          union
          select link.user_id
          from app.user_crm_links link
          where link.entity_type = 'student'
            and link.entity_id = $1
            and link.deleted_at is null
        ) affected
        where user_id is not null
      `,
      [studentId],
    );
    return (result?.rows ?? []).map((row) => row.user_id);
  }
}
