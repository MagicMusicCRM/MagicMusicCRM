import { Injectable } from "@nestjs/common";
import { PoolClient, QueryResultRow } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  BranchHoursExceptionDto,
  BranchWeeklyHoursDto,
  TeacherAvailabilityRuleDto,
  TeacherBranchAssignmentDto,
} from "./availability.dto";

interface BranchReferenceRow {
  id: string;
  timezone_name: string;
  schedule_reference_version: number | string;
}

interface TeacherReferenceRow {
  id: string;
  schedule_reference_version: number | string;
  owner_user_id: string | null;
}

@Injectable()
export class AvailabilityRepository {
  constructor(private readonly database: DatabaseService) {}

  getTeacherOwner(teacherId: string, client?: PoolClient) {
    const query = <T extends QueryResultRow>(
      sql: string,
      params: unknown[],
    ) =>
      client
        ? client.query<T>(sql, params)
        : this.database.query<T>(sql, params);
    return query<TeacherReferenceRow>(
      `
        select
          teacher.id,
          teacher.schedule_reference_version,
          profile.user_id as owner_user_id
        from app.teachers teacher
        left join app.profiles profile on profile.id = teacher.profile_id
        where teacher.id = $1 and teacher.deleted_at is null
      `,
      [teacherId],
    );
  }

  async resolve(
    branchId: string,
    teacherId: string,
    from: Date,
    to: Date,
    client?: PoolClient,
  ) {
    const query = <T extends QueryResultRow>(
      sql: string,
      params: unknown[],
    ) =>
      client
        ? client.query<T>(sql, params)
        : this.database.query<T>(sql, params);
    const branch = await query<BranchReferenceRow>(
      `
        select id, timezone_name, schedule_reference_version
        from app.branches
        where id = $1 and deleted_at is null
      `,
      [branchId],
    );
    const branchRow = branch.rows[0];
    if (!branchRow) return null;

    const teacher = await this.getTeacherOwner(teacherId, client);
    const teacherRow = teacher.rows[0];
    if (!teacherRow) return null;

    const assignment = await query<{ assigned: boolean }>(
      `
          with local_bounds as (
            select
              timezone($3, $1::timestamptz)::date as from_date,
              timezone($3, $2::timestamptz)::date as to_date
          )
          select exists (
            select 1
            from app.teacher_branches assignment, local_bounds bounds
            where assignment.teacher_id = $4
              and assignment.branch_id = $5
              and assignment.active_from <= bounds.from_date
              and coalesce(assignment.active_until, 'infinity'::date)
                    >= bounds.to_date
          ) as assigned
        `,
      [from, to, branchRow.timezone_name, teacherId, branchId],
    );
    const branchWindows = await query<{
      local_date: string;
      opens_at: Date | string;
      closes_at: Date | string;
      source: "weekly" | "exception";
    }>(
      `
          with bounds as (
            select
              timezone($3, $1::timestamptz)::date as from_date,
              timezone($3, $2::timestamptz)::date as to_date
          ),
          dates as (
            select day::date as local_date
            from bounds,
              generate_series(from_date, to_date, interval '1 day') day
          ),
          effective as (
            select
              dates.local_date,
              coalesce(exception.open_local, weekly.open_local) as open_local,
              coalesce(exception.close_local, weekly.close_local) as close_local,
              case when exception.id is null then 'weekly' else 'exception' end
                as source,
              coalesce(exception.closed, false) as closed
            from dates
            left join app.branch_hours weekly
              on weekly.branch_id = $4
             and weekly.weekday = extract(isodow from dates.local_date)
            left join app.branch_hour_exceptions exception
              on exception.branch_id = $4
             and exception.local_date = dates.local_date
          )
          select
            local_date::text as local_date,
            (local_date + open_local) at time zone $3 as opens_at,
            (local_date + close_local) at time zone $3 as closes_at,
            source
          from effective
          where not closed
            and open_local is not null
            and close_local is not null
            and (local_date + close_local) at time zone $3 > $1
            and (local_date + open_local) at time zone $3 < $2
          order by local_date
        `,
      [from, to, branchRow.timezone_name, branchId],
    );
    const availability = await query<{
      id: string;
      available: boolean;
      starts_at: Date | string;
      ends_at: Date | string | null;
      source: "recurring" | "interval";
      reason: string | null;
    }>(
      `
          with recurring as (
            select
              rule.id,
              rule.available,
              (dates.local_date + rule.local_start)
                at time zone rule.timezone_name as starts_at,
              (dates.local_date + rule.local_end)
                at time zone rule.timezone_name as ends_at,
              'recurring'::text as source,
              rule.reason
            from app.teacher_availability_rules rule
            cross join lateral (
              select day::date as local_date
              from generate_series(
                timezone(rule.timezone_name, $1::timestamptz)::date,
                timezone(rule.timezone_name, $2::timestamptz)::date,
                interval '1 day'
              ) day
            ) dates
            where rule.teacher_id = $3
              and rule.kind = 'recurring'
              and extract(isodow from dates.local_date) = rule.weekday
              and dates.local_date >= rule.valid_from
              and (
                rule.valid_until is null
                or dates.local_date <= rule.valid_until
              )
          ),
          intervals as (
            select
              rule.id,
              rule.available,
              rule.starts_at,
              rule.ends_at,
              'interval'::text as source,
              rule.reason
            from app.teacher_availability_rules rule
            where rule.teacher_id = $3
              and rule.kind = 'interval'
          )
          select id, available, starts_at, ends_at, source, reason
          from (
            select * from recurring
            union all
            select * from intervals
          ) rules
          where coalesce(ends_at, 'infinity'::timestamptz) > $1
            and starts_at < $2
          order by starts_at, id
        `,
      [from, to, teacherId],
    );

    return {
      branch: {
        id: branchRow.id,
        timezone: branchRow.timezone_name,
        version: Number(branchRow.schedule_reference_version),
      },
      teacher: {
        id: teacherRow.id,
        version: Number(teacherRow.schedule_reference_version),
      },
      teacherBranchAssigned: assignment.rows[0]?.assigned ?? false,
      branchWindows: branchWindows.rows.map((row) => ({
        localDate: row.local_date,
        opensAt: row.opens_at,
        closesAt: row.closes_at,
        source: row.source,
      })),
      teacherRules: availability.rows.map((row) => ({
        id: row.id,
        available: row.available,
        startsAt: row.starts_at,
        endsAt: row.ends_at,
        source: row.source,
        reason: row.reason,
      })),
    };
  }

  async replaceBranchHours(
    client: PoolClient,
    input: {
      branchId: string;
      expectedVersion: number;
      timezone: string;
      weekly: BranchWeeklyHoursDto[];
      exceptions: BranchHoursExceptionDto[];
    },
  ) {
    const branch = await client.query<BranchReferenceRow>(
      `
        update app.branches
        set timezone_name = $3,
            schedule_reference_version = schedule_reference_version + 1,
            updated_at = now()
        where id = $1
          and deleted_at is null
          and schedule_reference_version = $2
        returning id, timezone_name, schedule_reference_version
      `,
      [input.branchId, input.expectedVersion, input.timezone],
    );
    if (!branch.rows[0]) return null;
    await client.query("delete from app.branch_hours where branch_id = $1", [
      input.branchId,
    ]);
    await client.query(
      "delete from app.branch_hour_exceptions where branch_id = $1",
      [input.branchId],
    );
    for (const row of input.weekly) {
      await client.query(
        `
          insert into app.branch_hours (
            branch_id, weekday, open_local, close_local
          )
          values ($1, $2, $3::time, $4::time)
        `,
        [input.branchId, row.weekday, row.open, row.close],
      );
    }
    for (const row of input.exceptions) {
      await client.query(
        `
          insert into app.branch_hour_exceptions (
            branch_id, local_date, closed, open_local, close_local, reason
          )
          values ($1, $2::date, $3, $4::time, $5::time, $6)
        `,
        [
          input.branchId,
          row.date,
          row.closed,
          row.open ?? null,
          row.close ?? null,
          row.reason?.trim() || null,
        ],
      );
    }
    return {
      branchId: input.branchId,
      timezone: branch.rows[0].timezone_name,
      version: Number(branch.rows[0].schedule_reference_version),
    };
  }

  async replaceTeacherBranches(
    client: PoolClient,
    input: {
      teacherId: string;
      expectedVersion: number;
      assignments: TeacherBranchAssignmentDto[];
    },
  ) {
    const teacher = await this.bumpTeacher(client, input);
    if (!teacher) return null;
    await client.query(
      "delete from app.teacher_branches where teacher_id = $1",
      [input.teacherId],
    );
    for (const row of input.assignments) {
      await client.query(
        `
          insert into app.teacher_branches (
            teacher_id, branch_id, active_from, active_until
          )
          values ($1, $2, coalesce($3::date, date '1970-01-01'), $4::date)
        `,
        [
          input.teacherId,
          row.branchId,
          row.activeFrom ?? null,
          row.activeUntil ?? null,
        ],
      );
    }
    return {
      teacherId: input.teacherId,
      version: Number(teacher.schedule_reference_version),
    };
  }

  async replaceTeacherAvailability(
    client: PoolClient,
    input: {
      teacherId: string;
      expectedVersion: number;
      rules: TeacherAvailabilityRuleDto[];
    },
  ) {
    const teacher = await this.bumpTeacher(client, input);
    if (!teacher) return null;
    await client.query(
      "delete from app.teacher_availability_rules where teacher_id = $1",
      [input.teacherId],
    );
    for (const row of input.rules) {
      await client.query(
        `
          insert into app.teacher_availability_rules (
            teacher_id, kind, available, timezone_name,
            weekday, local_start, local_end, valid_from, valid_until,
            starts_at, ends_at, reason
          )
          values (
            $1, $2, $3, coalesce($4, 'Europe/Moscow'),
            $5, $6::time, $7::time, $8::date, $9::date,
            $10::timestamptz, $11::timestamptz, $12
          )
        `,
        [
          input.teacherId,
          row.kind,
          row.available,
          row.timezone ?? null,
          row.weekday ?? null,
          row.localStart ?? null,
          row.localEnd ?? null,
          row.validFrom ?? null,
          row.validUntil ?? null,
          row.startsAt ?? null,
          row.endsAt ?? null,
          row.reason?.trim() || null,
        ],
      );
    }
    return {
      teacherId: input.teacherId,
      version: Number(teacher.schedule_reference_version),
    };
  }

  private async bumpTeacher(
    client: PoolClient,
    input: { teacherId: string; expectedVersion: number },
  ) {
    const teacher = await client.query<TeacherReferenceRow>(
      `
        update app.teachers
        set schedule_reference_version = schedule_reference_version + 1,
            updated_at = now()
        where id = $1
          and deleted_at is null
          and schedule_reference_version = $2
        returning id, schedule_reference_version, null::uuid as owner_user_id
      `,
      [input.teacherId, input.expectedVersion],
    );
    return teacher.rows[0] ?? null;
  }
}
