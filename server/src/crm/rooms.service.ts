import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { authorizeCurrentCapability } from "../access-control/capability-request-authorizer";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { managerAdminRolesSql } from "../common/security/role-sql";
import { DatabaseService } from "../db/database.service";
import { RoomAvailabilityQuery } from "./dto/room-availability.query";
import { RoomListQuery } from "./dto/room-lifecycle.dto";
import { UpsertRoomDto } from "./dto/upsert-room.dto";
import { CrmPolicy } from "./crm.policy";
import { currentActorRoleSql, managerBranchScopeSql } from "./branch-scope";
import { assertSettingsBranchScope } from "./settings-branch-scope";

interface RoomRow {
  id: string;
  branch_id: string | null;
  branch_name: string | null;
  name: string;
  capacity: number | null;
  lifecycle_state?: "active" | "archived";
  version?: number | string;
  archived_at?: Date | string | null;
  archive_reason?: string | null;
  archive_effective_date?: string | null;
  created_at: Date | string;
}

interface RoomAvailabilityRow {
  room_id: string;
  branch_id: string | null;
  branch_name: string | null;
  room_name: string;
  capacity: number | null;
  lessons: Array<Record<string, unknown>> | null;
  is_available: boolean | null;
  conflict_types: string[] | null;
}

/**
 * Rooms domain, extracted from CrmService (SRP): room CRUD and the room
 * availability matrix (slot/room/teacher conflict detection). Leaf domain —
 * touches `app.rooms` (joined to branches/lessons for reads) and the shared
 * database/audit/policy collaborators, with no internal callers.
 */
@Injectable()
export class RoomsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
  ) {}

  private toRoomDto(row: RoomRow) {
    return {
      id: row.id,
      branchId: row.branch_id,
      branchName: row.branch_name,
      name: row.name,
      capacity: row.capacity,
      lifecycleState: row.lifecycle_state ?? "active",
      version: Number(row.version ?? 1),
      archivedAt: row.archived_at ?? null,
      archiveReason: row.archive_reason ?? null,
      archiveEffectiveDate: row.archive_effective_date ?? null,
      createdAt: row.created_at,
    };
  }

  private toRoomAvailabilityDto(row: RoomAvailabilityRow) {
    return {
      roomId: row.room_id,
      branchId: row.branch_id,
      branchName: row.branch_name,
      roomName: row.room_name,
      capacity: row.capacity,
      lessons: row.lessons ?? [],
      isAvailable: row.is_available ?? false,
      conflictTypes: row.conflict_types ?? [],
    };
  }

  // ponytail: utcDayStart is copied from CrmService (also used by its schedule
  // date logic). Lift into a shared date helper alongside the mappers in B4.
  private utcDayStart(date: Date) {
    return new Date(
      Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
    );
  }

  private async roomAvailabilityBounds(
    actor: ActorContext,
    query: RoomAvailabilityQuery,
  ) {
    if ((query.dayFrom == null) !== (query.dayTo == null)) {
      throw new BadRequestException(
        "Границы локального дня должны быть переданы вместе.",
      );
    }
    if ((query.slotFromMinutes == null) !== (query.slotToMinutes == null)) {
      throw new BadRequestException(
        "Локальные границы слота должны быть переданы вместе.",
      );
    }
    if (
      query.slotFromMinutes != null &&
      query.slotToMinutes != null &&
      query.slotToMinutes <= query.slotFromMinutes
    ) {
      throw new BadRequestException(
        "Окончание локального слота должно быть позже начала.",
      );
    }

    if (query.dayFrom == null && query.branchId && query.date) {
      const zoned = await this.database.query<{
        day_from: Date | string;
        day_to: Date | string;
        slot_from: Date | string;
        slot_to: Date | string;
      }>(
        `
          select
            ($2::date::timestamp at time zone coalesce(branch.timezone_name, 'Europe/Moscow')) as day_from,
            (($2::date + 1)::timestamp at time zone coalesce(branch.timezone_name, 'Europe/Moscow')) as day_to,
            (($2::date::timestamp + make_interval(mins => $3::int))
              at time zone coalesce(branch.timezone_name, 'Europe/Moscow')) as slot_from,
            (($2::date::timestamp + make_interval(mins => $4::int))
              at time zone coalesce(branch.timezone_name, 'Europe/Moscow')) as slot_to
          from app.branches branch
          where branch.id = $1::uuid
            and branch.deleted_at is null
            and ${managerAdminRolesSql(currentActorRoleSql("$5"))}
            and ${managerBranchScopeSql({
              roleExpression: currentActorRoleSql("$5"),
              userIdExpression: "$5",
              branchExpression: "branch.id::text",
            })}
        `,
        [
          query.branchId,
          query.date,
          query.slotFromMinutes ?? 0,
          query.slotToMinutes ?? 1440,
          actor.userId,
        ],
      );
      const row = zoned.rows[0];
      if (row) {
        const iso = (value: Date | string) => new Date(value).toISOString();
        return {
          dayFrom: iso(row.day_from),
          dayTo: iso(row.day_to),
          slotFrom:
            query.slotFromMinutes == null && query.from
              ? new Date(query.from).toISOString()
              : iso(row.slot_from),
          slotTo:
            query.slotToMinutes == null && query.to
              ? new Date(query.to).toISOString()
              : iso(row.slot_to),
        };
      }
    }
    const reference = query.date
      ? new Date(query.date)
      : query.from
        ? new Date(query.from)
        : new Date();
    const dayStart = query.dayFrom
      ? new Date(query.dayFrom)
      : this.utcDayStart(reference);
    const dayEnd = query.dayTo
      ? new Date(query.dayTo)
      : new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
    if (dayEnd <= dayStart) {
      throw new BadRequestException(
        "Окончание локального дня должно быть позже начала.",
      );
    }
    const slotFrom =
      query.slotFromMinutes != null
        ? new Date(dayStart.getTime() + query.slotFromMinutes * 60 * 1000)
        : query.from
          ? new Date(query.from)
          : dayStart;
    const slotTo =
      query.slotToMinutes != null
        ? new Date(dayStart.getTime() + query.slotToMinutes * 60 * 1000)
        : query.to
          ? new Date(query.to)
          : query.from
            ? new Date(
                slotFrom.getTime() + (query.durationMinutes ?? 60) * 60 * 1000,
              )
            : dayEnd;

    return {
      dayFrom: dayStart.toISOString(),
      dayTo: dayEnd.toISOString(),
      slotFrom: slotFrom.toISOString(),
      slotTo: slotTo.toISOString(),
    };
  }

  async listRooms(actor: ActorContext, query: RoomListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const includeArchived = query.includeArchived ?? false;
    if (
      includeArchived &&
      actor.role !== "director" &&
      actor.role !== "system_admin"
    ) {
      throw new ForbiddenException(
        "Архив аудиторий доступен только директору.",
      );
    }
    if (includeArchived) {
      await authorizeCurrentCapability(this.database, actor, "config.crm.edit");
    }
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<RoomRow>(
      `
        select r.id, r.branch_id, b.name as branch_name, r.name, r.capacity,
          r.lifecycle_state, r.version, r.archived_at, r.archive_reason,
          r.archive_effective_date, r.created_at
        from app.rooms r
        left join app.branches b on b.id = r.branch_id
        where ($5::boolean or r.deleted_at is null)
          and (
            ${managerAdminRolesSql(currentActorRoleSql("$4"))}
            or ${currentActorRoleSql("$4")} = 'teacher'
          )
          and ${managerBranchScopeSql({
            roleExpression: currentActorRoleSql("$4"),
            userIdExpression: "$4",
            branchExpression: "r.branch_id::text",
          })}
          and ($1::uuid is null or r.branch_id = $1)
          and (
            $2::text is null
            or lower(coalesce(r.name, '') || ' ' || coalesce(b.name, '')) like lower('%' || $2 || '%')
          )
        order by b.name nulls last, r.name asc, r.id asc
        limit $3
      `,
      [query.branchId ?? null, q || null, limit, actor.userId, includeArchived],
    );

    return { items: result.rows.map((row) => this.toRoomDto(row)) };
  }

  async listRoomAvailability(
    actor: ActorContext,
    query: RoomAvailabilityQuery,
  ) {
    this.policy.assertManagerOnly(actor);
    const limit = Math.min(query.limit ?? 100, 200);
    const bounds = await this.roomAvailabilityBounds(actor, query);
    const result = await this.database.query<RoomAvailabilityRow>(
      `
        with room_rows as (
          select r.id as room_id, r.branch_id, b.name as branch_name,
            r.name as room_name, r.capacity
          from app.rooms r
          left join app.branches b on b.id = r.branch_id and b.deleted_at is null
           where r.deleted_at is null
             and ${managerAdminRolesSql(currentActorRoleSql("$9"))}
             and ($1::uuid is null or r.branch_id = $1)
             and ($2::uuid is null or r.id = $2)
             and ${managerBranchScopeSql({
               roleExpression: currentActorRoleSql("$9"),
               userIdExpression: "$9",
               branchExpression: "r.branch_id::text",
             })}
          order by b.name nulls last, r.name asc, r.id asc
          limit $8
        ),
        bounded_lessons as (
          select l.id, l.room_id, l.teacher_id, l.branch_id, l.scheduled_at,
            l.duration_minutes, l.status, l.is_trial,
            trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
            trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
            g.name as group_name,
            l.group_id
          from app.lessons l
          join room_rows rr on rr.room_id = l.room_id
          left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          left join app.students s on s.id = l.student_id and s.deleted_at is null
          left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          where l.deleted_at is null
            and l.room_id is not null
            and l.scheduled_at + l.duration_minutes * interval '1 minute' > $3::timestamptz
            and l.scheduled_at < $4::timestamptz
        ),
        slot_lessons as (
          select *
          from bounded_lessons
          where status <> 'cancelled'
            and scheduled_at < $6::timestamptz
            and scheduled_at + duration_minutes * interval '1 minute' > $5::timestamptz
        ),
        room_overlap_conflicts as (
          select distinct a.room_id
          from slot_lessons a
          join slot_lessons b
            on b.room_id = a.room_id
           and b.id <> a.id
           and (a.group_id is null or b.group_id is null or a.group_id <> b.group_id)
           and b.scheduled_at < a.scheduled_at + a.duration_minutes * interval '1 minute'
           and b.scheduled_at + b.duration_minutes * interval '1 minute' > a.scheduled_at
        )
        select rr.room_id, rr.branch_id, rr.branch_name, rr.room_name,
          rr.capacity,
          coalesce(
            jsonb_agg(
              jsonb_build_object(
                'id', bl.id,
                'teacherId', bl.teacher_id,
                'teacherName', nullif(bl.teacher_name, ''),
                'studentName', nullif(bl.student_name, ''),
                'groupName', bl.group_name,
                'scheduledAt', bl.scheduled_at,
                'durationMinutes', bl.duration_minutes,
                'status', bl.status,
                'isTrial', bl.is_trial
              )
              order by bl.scheduled_at asc, bl.id asc
            ) filter (where bl.id is not null),
            '[]'::jsonb
          ) as lessons,
          not exists (
            select 1
            from slot_lessons overlap_lesson
            where overlap_lesson.room_id = rr.room_id
          ) as is_available,
          array_remove(array[
            -- room_overlap = TWO lessons actually overlapping each other in the
            -- room (different groups), not merely the room being occupied during
            -- the queried window (which a whole-day window would always be).
            case when exists (
              select 1
              from room_overlap_conflicts roc
              where roc.room_id = rr.room_id
            ) then 'room_overlap' end,
            case when $7::uuid is not null and exists (
              select 1
              from slot_lessons teacher_lesson
              where teacher_lesson.teacher_id = $7
            ) then 'teacher_overlap' end
          ], null) as conflict_types
        from room_rows rr
        left join bounded_lessons bl on bl.room_id = rr.room_id
        group by rr.room_id, rr.branch_id, rr.branch_name, rr.room_name, rr.capacity
        order by rr.branch_name nulls last, rr.room_name asc, rr.room_id asc
      `,
      [
        query.branchId ?? null,
        query.roomId ?? null,
        bounds.dayFrom,
        bounds.dayTo,
        bounds.slotFrom,
        bounds.slotTo,
        query.teacherId ?? null,
        limit,
        actor.userId,
      ],
    );

    return {
      dateFrom: bounds.dayFrom,
      dateTo: bounds.dayTo,
      slotFrom: bounds.slotFrom,
      slotTo: bounds.slotTo,
      items: result.rows.map((row) => this.toRoomAvailabilityDto(row)),
    };
  }

  async createRoom(actor: ActorContext, dto: UpsertRoomDto) {
    this.policy.assertCanManageSystemSettings(actor);
    if (!dto.branchId) {
      throw new BadRequestException("Для аудитории необходимо выбрать филиал.");
    }
    await assertSettingsBranchScope(this.database, actor, dto.branchId);
    const name = dto.name?.trim();
    if (!name) {
      throw new BadRequestException("Название аудитории обязательно.");
    }

    const result = await this.database.query<RoomRow>(
      `
        with target_branch as (
          select id from app.branches where id = $1 and deleted_at is null
        ),
        inserted as (
          insert into app.rooms (branch_id, name, capacity)
          select id, $2, $3 from target_branch
          returning id, branch_id, name, capacity, lifecycle_state, version,
            archived_at, archive_reason, archive_effective_date, created_at
        ), aggregate_seed as (
          insert into app.aggregate_versions (
            aggregate_type, aggregate_id, version
          )
          select 'organization:room', id::text, version from inserted
          on conflict (aggregate_type, aggregate_id) do nothing
        )
        select i.id, i.branch_id, b.name as branch_name, i.name, i.capacity,
          i.lifecycle_state, i.version, i.archived_at, i.archive_reason,
          i.archive_effective_date, i.created_at
        from inserted i
        left join app.branches b on b.id = i.branch_id and b.deleted_at is null
      `,
      [dto.branchId, name, dto.capacity ?? null],
    );
    const room = result.rows[0];
    if (!room) throw new BadRequestException("Выбранный филиал недоступен.");
    await this.audit.record({
      actor,
      action: "crm.room_created",
      entityType: "room",
      entityId: room.id,
    });
    return this.toRoomDto(room);
  }

  async updateRoom(actor: ActorContext, roomId: string, dto: UpsertRoomDto) {
    this.policy.assertCanManageSystemSettings(actor);
    if (dto.branchId) {
      const currentBranchId = await this.roomBranch(roomId);
      if (dto.branchId !== currentBranchId) {
        throw new UnprocessableEntityException({
          code: "ROOM_BRANCH_TRANSFER_REQUIRES_REMEDIATION",
          message:
            "Нельзя перенести действующую аудиторию между филиалами обычным редактированием.",
        });
      }
    }
    if (actor.role === "manager") {
      await assertSettingsBranchScope(
        this.database,
        actor,
        await this.roomBranch(roomId),
      );
      if (dto.branchId) {
        await assertSettingsBranchScope(this.database, actor, dto.branchId);
      }
    }
    const name = dto.name?.trim();
    if (dto.name !== undefined && !name) {
      throw new BadRequestException("Название аудитории обязательно.");
    }

    const result = await this.database.query<RoomRow>(
      `
        with updated as (
          update app.rooms
          set branch_id = coalesce($2, branch_id),
            name = coalesce($3, name),
            capacity = case when $4::boolean then $5::integer else capacity end,
            updated_at = now()
          where id = $1 and deleted_at is null
          returning id, branch_id, name, capacity, lifecycle_state, version,
            archived_at, archive_reason, archive_effective_date, created_at
        )
        select u.id, u.branch_id, b.name as branch_name, u.name, u.capacity,
          u.lifecycle_state, u.version, u.archived_at, u.archive_reason,
          u.archive_effective_date, u.created_at
        from updated u
        left join app.branches b on b.id = u.branch_id and b.deleted_at is null
      `,
      [
        roomId,
        dto.branchId ?? null,
        name ?? null,
        Object.prototype.hasOwnProperty.call(dto, "capacity"),
        dto.capacity ?? null,
      ],
    );
    const room = result.rows[0];
    if (!room) throw new NotFoundException("Аудитория не найдена.");
    await this.audit.record({
      actor,
      action: "crm.room_updated",
      entityType: "room",
      entityId: room.id,
    });
    return this.toRoomDto(room);
  }

  async deleteRoom(actor: ActorContext, roomId: string) {
    this.policy.assertCanManageSystemSettings(actor);
    throw new UnprocessableEntityException({
      code: "ROOM_ARCHIVE_PREVIEW_REQUIRED",
      message:
        "Прямое удаление отключено. Сначала откройте проверку связей аудитории.",
      roomId,
    });
  }

  private async roomBranch(roomId: string): Promise<string> {
    const result = await this.database.query<{ branch_id: string | null }>(
      `select branch_id from app.rooms where id = $1 and deleted_at is null`,
      [roomId],
    );
    const branchId = result.rows[0]?.branch_id;
    if (!branchId) throw new NotFoundException("Аудитория не найдена.");
    return branchId;
  }
}
