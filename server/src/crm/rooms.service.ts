import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmListQuery } from "./dto/crm-list.query";
import { RoomAvailabilityQuery } from "./dto/room-availability.query";
import { UpsertRoomDto } from "./dto/upsert-room.dto";
import { CrmPolicy } from "./crm.policy";
import { assertSettingsBranchScope } from "./settings-branch-scope";

interface RoomRow {
  id: string;
  branch_id: string | null;
  branch_name: string | null;
  name: string;
  capacity: number | null;
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

  private roomAvailabilityBounds(query: RoomAvailabilityQuery) {
    const reference = query.date
      ? new Date(query.date)
      : query.from
        ? new Date(query.from)
        : new Date();
    const dayStart = this.utcDayStart(reference);
    const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
    const slotFrom = query.from ? new Date(query.from) : dayStart;
    const slotTo = query.to
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

  async listRooms(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<RoomRow>(
      `
        select r.id, r.branch_id, b.name as branch_name, r.name, r.capacity, r.created_at
        from app.rooms r
        left join app.branches b on b.id = r.branch_id and b.deleted_at is null
        where r.deleted_at is null
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
              where link.user_id = $5 and assignment.branch_id = r.branch_id
            )
          )
          and ($1::uuid is null or r.branch_id = $1)
          and (
            $2::text is null
            or lower(coalesce(r.name, '') || ' ' || coalesce(b.name, '')) like lower('%' || $2 || '%')
          )
        order by b.name nulls last, r.name asc, r.id asc
        limit $3
      `,
      [query.branchId ?? null, q || null, limit, actor.role, actor.userId],
    );

    return { items: result.rows.map((row) => this.toRoomDto(row)) };
  }

  async listRoomAvailability(
    actor: ActorContext,
    query: RoomAvailabilityQuery,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 200);
    const bounds = this.roomAvailabilityBounds(query);
    const result = await this.database.query<RoomAvailabilityRow>(
      `
        with room_rows as (
          select r.id as room_id, r.branch_id, b.name as branch_name,
            r.name as room_name, r.capacity
          from app.rooms r
          left join app.branches b on b.id = r.branch_id and b.deleted_at is null
          where r.deleted_at is null
            and ($1::uuid is null or r.branch_id = $1)
            and ($2::uuid is null or r.id = $2)
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
          returning id, branch_id, name, capacity, created_at
        )
        select i.id, i.branch_id, b.name as branch_name, i.name, i.capacity, i.created_at
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
          returning id, branch_id, name, capacity, created_at
        )
        select u.id, u.branch_id, b.name as branch_name, u.name, u.capacity, u.created_at
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
    if (actor.role === "manager") {
      await assertSettingsBranchScope(
        this.database,
        actor,
        await this.roomBranch(roomId),
      );
    }
    const result = await this.database.query<{ id: string }>(
      `
        update app.rooms
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [roomId],
    );
    const room = result.rows[0];
    if (!room) throw new NotFoundException("Аудитория не найдена.");
    await this.audit.record({
      actor,
      action: "crm.room_deleted",
      entityType: "room",
      entityId: room.id,
    });
    return { success: true };
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
