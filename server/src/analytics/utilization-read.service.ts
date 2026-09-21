import { BadRequestException, Injectable } from "@nestjs/common";
import { authorizeCurrentCapability } from "../access-control/capability-request-authorizer";
import { ActorContext } from "../common/security/actor-context";
import {
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../crm/branch-scope";
import { DatabaseService } from "../db/database.service";
import { AnalyticsRangeQuery } from "./dto/analytics-range.query";

export interface TimeInterval {
  start: Date;
  end: Date;
}

interface EntityRow {
  entity_type: "teacher" | "room";
  entity_id: string;
  display_name: string;
}

interface WindowRow {
  entity_id: string;
  starts_at: Date | string;
  ends_at: Date | string;
}

interface AvailabilityRow extends WindowRow {
  available: boolean;
}

interface LessonRow {
  id: string;
  teacher_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string;
  ends_at: Date | string;
  lifecycle_state: string;
  attendance_count: string;
}

@Injectable()
export class UtilizationReadService {
  constructor(private readonly database: DatabaseService) {}

  async report(actor: ActorContext, query: AnalyticsRangeQuery) {
    await authorizeCurrentCapability(
      this.database,
      actor,
      "report.status.read",
    );
    const range = normalizeRange(query);
    const params = [
      range.start.toISOString(),
      range.end.toISOString(),
      query.branchId ?? null,
      actor.userId,
    ];
    const [entities, teacherWindows, roomWindows, availability, lessons] =
      await Promise.all([
        this.database.query<EntityRow>(this.entitiesSql(), params),
        this.database.query<WindowRow>(this.teacherWindowsSql(), params),
        this.database.query<WindowRow>(this.roomWindowsSql(), params),
        this.database.query<AvailabilityRow>(this.availabilitySql(), params),
        this.database.query<LessonRow>(this.lessonsSql(), params),
      ]);

    const entityRows = entities.rows;
    const lessonRows = lessons.rows.map((row) => ({
      ...row,
      interval: clipInterval(
        { start: date(row.scheduled_at), end: date(row.ends_at) },
        range,
      ),
    }));
    const teachers = entityRows
      .filter((row) => row.entity_type === "teacher")
      .map((row) => {
        const base = intervalsFor(teacherWindows.rows, row.entity_id, range);
        const rules = availability.rows.filter(
          (rule) => rule.entity_id === row.entity_id,
        );
        const positive = intervalsFromRows(
          rules.filter((rule) => rule.available),
          range,
        );
        const negative = intervalsFromRows(
          rules.filter((rule) => !rule.available),
          range,
        );
        const available = subtractIntervals(
          positive.length === 0 ? base : intersectIntervals(base, positive),
          negative,
        );
        return buildUtilizationRow(
          row,
          available,
          lessonRows.filter((lesson) => lesson.teacher_id === row.entity_id),
          query.branchId,
        );
      });
    const rooms = entityRows
      .filter((row) => row.entity_type === "room")
      .map((row) =>
        buildUtilizationRow(
          row,
          intervalsFor(roomWindows.rows, row.entity_id, range),
          lessonRows.filter((lesson) => lesson.room_id === row.entity_id),
          query.branchId,
        ),
      );
    return {
      from: range.start.toISOString(),
      to: range.end.toISOString(),
      branchId: query.branchId ?? null,
      generatedAt: new Date().toISOString(),
      teachers,
      rooms,
    };
  }

  private scope(branchExpression: string): string {
    return managerBranchScopeSql({
      roleExpression: currentActorRoleSql("$4"),
      userIdExpression: "$4",
      branchExpression,
    });
  }

  private entitiesSql(): string {
    const teacherScope = this.scope("branch.id::text");
    const roomScope = this.scope("room.branch_id::text");
    return `
      select distinct
        'teacher'::text as entity_type,
        teacher.id as entity_id,
        coalesce(
          nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), ''),
          'Преподаватель'
        ) as display_name
      from app.teachers teacher
      join app.teacher_branches assignment on assignment.teacher_id = teacher.id
      join app.branches branch on branch.id = assignment.branch_id
      left join app.profiles profile on profile.id = teacher.profile_id
      where teacher.deleted_at is null
        and branch.deleted_at is null
        and ($3::uuid is null or branch.id = $3::uuid)
        and assignment.active_from <= timezone(branch.timezone_name, $2::timestamptz)::date
        and (assignment.active_until is null
          or assignment.active_until >= timezone(branch.timezone_name, $1::timestamptz)::date)
        and ${teacherScope}

      union all

      select
        'room'::text,
        room.id,
        room.name
      from app.rooms room
      where room.deleted_at is null
        and ($3::uuid is null or room.branch_id = $3::uuid)
        and ${roomScope}
      order by entity_type desc, display_name, entity_id`;
  }

  private teacherWindowsSql(): string {
    return this.workingWindowsSql({
      selectEntity: "assignment.teacher_id",
      fromClause: `app.teacher_branches assignment
        join app.branches branch on branch.id = assignment.branch_id`,
      entityDateCondition: `and day.local_date between assignment.active_from
        and coalesce(assignment.active_until, 'infinity'::date)`,
      scope: this.scope("branch.id::text"),
    });
  }

  private roomWindowsSql(): string {
    return this.workingWindowsSql({
      selectEntity: "room.id",
      fromClause: `app.rooms room
        join app.branches branch on branch.id = room.branch_id`,
      entityDateCondition: "and room.deleted_at is null",
      scope: this.scope("branch.id::text"),
    });
  }

  private workingWindowsSql(options: {
    selectEntity: string;
    fromClause: string;
    entityDateCondition: string;
    scope: string;
  }): string {
    return `
      select
        ${options.selectEntity} as entity_id,
        (day.local_date + coalesce(exception.open_local, weekly.open_local))
          at time zone branch.timezone_name as starts_at,
        (day.local_date + coalesce(exception.close_local, weekly.close_local))
          at time zone branch.timezone_name as ends_at
      from ${options.fromClause}
      cross join lateral (
        select generated::date as local_date
        from generate_series(
          timezone(branch.timezone_name, $1::timestamptz)::date,
          timezone(branch.timezone_name, $2::timestamptz - interval '1 microsecond')::date,
          interval '1 day'
        ) generated
      ) day
      left join app.branch_hour_exceptions exception
        on exception.branch_id = branch.id
       and exception.local_date = day.local_date
      left join app.branch_hours weekly
        on weekly.branch_id = branch.id
       and weekly.weekday = extract(isodow from day.local_date)::int
      where branch.deleted_at is null
        and ($3::uuid is null or branch.id = $3::uuid)
        and ${options.scope}
        ${options.entityDateCondition}
        and coalesce(exception.closed, false) = false
        and coalesce(exception.open_local, weekly.open_local) is not null
        and coalesce(exception.close_local, weekly.close_local) is not null`;
  }

  private availabilitySql(): string {
    const scope = this.scope("assignment.branch_id::text");
    return `
      with scoped_teachers as (
        select distinct assignment.teacher_id
        from app.teacher_branches assignment
        where ($3::uuid is null or assignment.branch_id = $3::uuid)
          and ${scope}
      ), recurring as (
        select
          rule.teacher_id as entity_id,
          rule.available,
          (day.local_date + rule.local_start)
            at time zone rule.timezone_name as starts_at,
          (day.local_date + rule.local_end)
            at time zone rule.timezone_name as ends_at
        from app.teacher_availability_rules rule
        join scoped_teachers scoped on scoped.teacher_id = rule.teacher_id
        cross join lateral (
          select generated::date as local_date
          from generate_series(
            greatest(
              rule.valid_from,
              timezone(rule.timezone_name, $1::timestamptz)::date
            ),
            least(
              coalesce(rule.valid_until, 'infinity'::date),
              timezone(rule.timezone_name, $2::timestamptz - interval '1 microsecond')::date
            ),
            interval '1 day'
          ) generated
        ) day
        where rule.kind = 'recurring'
          and rule.weekday = extract(isodow from day.local_date)::int
      ), interval_rules as (
        select
          rule.teacher_id as entity_id,
          rule.available,
          greatest(rule.starts_at, $1::timestamptz) as starts_at,
          least(coalesce(rule.ends_at, $2::timestamptz), $2::timestamptz)
            as ends_at
        from app.teacher_availability_rules rule
        join scoped_teachers scoped on scoped.teacher_id = rule.teacher_id
        where rule.kind = 'interval'
          and rule.starts_at < $2::timestamptz
          and coalesce(rule.ends_at, $2::timestamptz) > $1::timestamptz
      )
      select * from recurring
      union all
      select * from interval_rules`;
  }

  private lessonsSql(): string {
    const scope = this.scope("lesson.branch_id::text");
    return `
      select
        lesson.id,
        lesson.teacher_id,
        lesson.room_id,
        lesson.scheduled_at,
        lesson.scheduled_at + make_interval(mins => lesson.duration_minutes)
          as ends_at,
        lesson.lifecycle_state,
        case
          when lesson.group_id is not null then count(distinct participation.student_id)
          when lesson.student_id is not null then 1
          else 0
        end::text as attendance_count
      from app.lessons lesson
      left join app.lesson_participation participation
        on participation.lesson_id = lesson.id
       and participation.attendance_kind in (
         'attended', 'free_lesson', 'partially_paid'
       )
      where lesson.deleted_at is null
        and lesson.successor_id is null
        and lesson.scheduled_at < $2::timestamptz
        and lesson.scheduled_at
          + make_interval(mins => lesson.duration_minutes) > $1::timestamptz
        and lesson.lifecycle_state in (
          'scheduled', 'settlement_pending', 'successfully_completed'
        )
        and ($3::uuid is null or lesson.branch_id = $3::uuid)
        and ${scope}
      group by lesson.id`;
  }
}

function buildUtilizationRow(
  entity: EntityRow,
  available: TimeInterval[],
  lessons: Array<LessonRow & { interval: TimeInterval | null }>,
  branchId: string | undefined,
) {
  const plannedLessons = lessons.filter((lesson) => lesson.interval != null);
  const actualLessons = plannedLessons.filter(
    (lesson) => lesson.lifecycle_state === "successfully_completed",
  );
  const availableMinutes = durationMinutes(available);
  const plannedMinutes = occupiedWithin(
    plannedLessons.map((lesson) => lesson.interval!),
    available,
  );
  const actualMinutes = occupiedWithin(
    actualLessons.map((lesson) => lesson.interval!),
    available,
  );
  return {
    id: entity.entity_id,
    name: entity.display_name,
    kind: entity.entity_type,
    availableMinutes,
    plannedMinutes,
    actualMinutes,
    plannedUtilization: utilizationPercent(plannedMinutes, availableMinutes),
    actualUtilization: utilizationPercent(actualMinutes, availableMinutes),
    plannedLessons: plannedLessons.length,
    actualLessons: actualLessons.length,
    attendances: actualLessons.reduce(
      (total, lesson) => total + Number(lesson.attendance_count),
      0,
    ),
    entityLink: {
      entityType: entity.entity_type,
      entityId: entity.entity_id,
      optionalFocus: {
        focus: "schedule",
        filter: {
          ...(entity.entity_type === "teacher"
            ? { teacherId: entity.entity_id }
            : { roomId: entity.entity_id }),
          ...(branchId ? { branchId } : {}),
        },
      },
    },
  };
}

function normalizeRange(query: AnalyticsRangeQuery): TimeInterval {
  const now = new Date();
  const to = query.to ? new Date(query.to) : now;
  const from = query.from
    ? new Date(query.from)
    : new Date(Date.UTC(to.getUTCFullYear(), to.getUTCMonth(), 1));
  if (
    Number.isNaN(from.getTime()) ||
    Number.isNaN(to.getTime()) ||
    from >= to ||
    to.getTime() - from.getTime() > 366 * 86_400_000
  ) {
    throw new BadRequestException({
      code: "INVALID_REPORT_RANGE",
      message: "Report date range is invalid or exceeds 366 days.",
    });
  }
  return { start: from, end: to };
}

function date(value: Date | string): Date {
  return value instanceof Date ? value : new Date(value);
}

function clipInterval(
  interval: TimeInterval,
  range: TimeInterval,
): TimeInterval | null {
  const start = interval.start > range.start ? interval.start : range.start;
  const end = interval.end < range.end ? interval.end : range.end;
  return start < end ? { start, end } : null;
}

function intervalsFromRows(
  rows: WindowRow[],
  range: TimeInterval,
): TimeInterval[] {
  return unionIntervals(
    rows
      .map((row) =>
        clipInterval(
          { start: date(row.starts_at), end: date(row.ends_at) },
          range,
        ),
      )
      .filter((interval): interval is TimeInterval => interval != null),
  );
}

function intervalsFor(
  rows: WindowRow[],
  entityId: string,
  range: TimeInterval,
): TimeInterval[] {
  return intervalsFromRows(
    rows.filter((row) => row.entity_id === entityId),
    range,
  );
}

export function unionIntervals(intervals: TimeInterval[]): TimeInterval[] {
  const sorted = intervals
    .filter((interval) => interval.start < interval.end)
    .map((interval) => ({ ...interval }))
    .sort((a, b) => a.start.getTime() - b.start.getTime());
  const result: TimeInterval[] = [];
  for (const interval of sorted) {
    const previous = result.at(-1);
    if (!previous || interval.start > previous.end) {
      result.push(interval);
    } else if (interval.end > previous.end) {
      previous.end = interval.end;
    }
  }
  return result;
}

export function intersectIntervals(
  left: TimeInterval[],
  right: TimeInterval[],
): TimeInterval[] {
  const a = unionIntervals(left);
  const b = unionIntervals(right);
  const result: TimeInterval[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const start = a[i]!.start > b[j]!.start ? a[i]!.start : b[j]!.start;
    const end = a[i]!.end < b[j]!.end ? a[i]!.end : b[j]!.end;
    if (start < end) result.push({ start, end });
    if (a[i]!.end < b[j]!.end) i += 1;
    else j += 1;
  }
  return result;
}

export function subtractIntervals(
  base: TimeInterval[],
  exclusions: TimeInterval[],
): TimeInterval[] {
  let result = unionIntervals(base);
  for (const exclusion of unionIntervals(exclusions)) {
    result = result.flatMap((interval) => {
      if (exclusion.end <= interval.start || exclusion.start >= interval.end) {
        return [interval];
      }
      const parts: TimeInterval[] = [];
      if (exclusion.start > interval.start) {
        parts.push({ start: interval.start, end: exclusion.start });
      }
      if (exclusion.end < interval.end) {
        parts.push({ start: exclusion.end, end: interval.end });
      }
      return parts;
    });
  }
  return result;
}

function durationMinutes(intervals: TimeInterval[]): number {
  return Math.round(
    unionIntervals(intervals).reduce(
      (total, interval) =>
        total + (interval.end.getTime() - interval.start.getTime()) / 60_000,
      0,
    ),
  );
}

function occupiedWithin(
  occupied: TimeInterval[],
  available: TimeInterval[],
): number {
  return durationMinutes(intersectIntervals(occupied, available));
}

export function utilizationPercent(
  occupiedMinutes: number,
  availableMinutes: number,
): number | null {
  return availableMinutes <= 0 ? null : occupiedMinutes / availableMinutes;
}
