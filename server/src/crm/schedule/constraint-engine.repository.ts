import { unchangedScheduleLessonSql } from "./schedule-lesson-template";
import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { AvailabilityRepository } from "./availability.repository";
import {
  LessonConflict,
  LessonConstraintDraft,
} from "./constraint-engine.types";

interface ConflictRow {
  code: LessonConflict["code"];
  resource_type: "teacher" | "client" | "room";
  resource_id: string;
  lesson_id: string;
}

export interface AlternativeRoom {
  id: string;
  name: string;
}

export interface AlternativeTeacher {
  id: string;
  name: string;
  sharedDisciplineCount: number;
}

@Injectable()
export class ConstraintEngineRepository {
  constructor(
    private readonly database: DatabaseService,
    private readonly availability: AvailabilityRepository,
  ) {}

  resolveReference(
    draft: LessonConstraintDraft,
    startAt: Date,
    endAt: Date,
    client?: PoolClient,
  ) {
    return this.availability.resolve(
      draft.branchId,
      draft.teacherId,
      startAt,
      endAt,
      client,
    );
  }

  async roomMatchesBranch(
    roomId: string,
    branchId: string,
    client?: PoolClient,
  ): Promise<boolean> {
    const query = client
      ? client.query.bind(client)
      : this.database.query.bind(this.database);
    const result = await query<{ matches: boolean }>(
      `select exists (
         select 1
         from app.rooms room
         where room.id = $1
           and room.branch_id = $2
           and room.deleted_at is null
       ) as matches`,
      [roomId, branchId],
    );
    return result.rows[0]?.matches ?? false;
  }

  async listAlternativeRooms(
    branchId: string,
    currentRoomId: string,
    client?: PoolClient,
  ): Promise<AlternativeRoom[]> {
    const query = client
      ? client.query.bind(client)
      : this.database.query.bind(this.database);
    const result = await query<{ id: string; name: string }>(
      `select room.id, room.name
       from app.rooms room
       where room.branch_id = $1
         and room.id <> $2
         and room.deleted_at is null
         and room.lifecycle_state = 'active'
       order by room.name, room.id
       limit 6`,
      [branchId, currentRoomId],
    );
    return result.rows;
  }

  async listAlternativeTeachers(
    currentTeacherId: string,
    branchId: string,
    startsAt: Date,
    client?: PoolClient,
  ): Promise<AlternativeTeacher[]> {
    const query = client
      ? client.query.bind(client)
      : this.database.query.bind(this.database);
    const result = await query<{
      id: string;
      name: string;
      shared_discipline_count: number | string;
    }>(
      `select candidate.id,
          coalesce(
            nullif(trim(concat_ws(' ', profile.first_name, profile.last_name)), ''),
            nullif(trim(concat_ws(
              ' ',
              candidate.custom_data->>'firstName',
              candidate.custom_data->>'lastName'
            )), ''),
            candidate.id::text
          ) as name,
          count(distinct candidate_discipline.discipline_id) as shared_discipline_count
       from app.teachers candidate
       join app.teacher_branches assignment
         on assignment.teacher_id = candidate.id
        and assignment.branch_id = $2
       join app.branches branch
         on branch.id = assignment.branch_id
        and branch.deleted_at is null
       join app.teacher_disciplines candidate_discipline
         on candidate_discipline.teacher_id = candidate.id
       join app.teacher_disciplines current_discipline
         on current_discipline.teacher_id = $1
        and current_discipline.discipline_id = candidate_discipline.discipline_id
       left join app.profiles profile
         on profile.id = candidate.profile_id
        and profile.deleted_at is null
       where candidate.id <> $1
         and candidate.deleted_at is null
         and candidate.lifecycle_state = 'active'
         and candidate.status = 'active'
         and assignment.active_from <= ($3::timestamptz at time zone branch.timezone_name)::date
         and (
           assignment.active_until is null
           or assignment.active_until >= ($3::timestamptz at time zone branch.timezone_name)::date
         )
       group by candidate.id, profile.first_name, profile.last_name
       order by shared_discipline_count desc, name, candidate.id
       limit 6`,
      [currentTeacherId, branchId, startsAt],
    );
    return result.rows.map((row) => ({
      id: row.id,
      name: row.name,
      sharedDisciplineCount: Number(row.shared_discipline_count),
    }));
  }

  async findConflicts(
    draft: LessonConstraintDraft,
    startAt: Date,
    endAt: Date,
    client?: PoolClient,
  ): Promise<LessonConflict[]> {
    const query = client
      ? client.query.bind(client)
      : this.database.query.bind(this.database);
    const result = await query<ConflictRow>(
      `
        with candidate as (
          select
            $1::uuid as teacher_id,
            $2::uuid as room_id,
            $3::text as client_type,
            $4::uuid as client_id,
            $5::timestamptz as starts_at,
            $6::timestamptz as ends_at,
            $7::uuid as exclude_lesson_id,
            $8::uuid[] as exclude_schedule_series_ids
        ),
        teacher_conflicts as (
          select
            'TEACHER_OVERLAP'::text as code,
            'teacher'::text as resource_type,
            lesson.teacher_id as resource_id,
            lesson.id as lesson_id
          from candidate
          join app.lessons lesson
            on lesson.teacher_id = candidate.teacher_id
           and lesson.deleted_at is null
           and lesson.status <> 'cancelled'
           and lesson.lifecycle_state = 'scheduled'
           and lesson.scheduled_at < candidate.ends_at
           and lesson.scheduled_at
                 + lesson.duration_minutes * interval '1 minute'
               > candidate.starts_at
           and (
             candidate.exclude_lesson_id is null
             or lesson.id <> candidate.exclude_lesson_id
           )
           and (
             candidate.exclude_schedule_series_ids is null
             or lesson.series_id is null
             or not (
               lesson.series_id = any(candidate.exclude_schedule_series_ids)
               and exists (select 1 from app.schedule_series series
                 where series.id = lesson.series_id and (
                   (series.plan_id is null and lesson.original_scheduled_at is null)
                   or (series.plan_id is not null and (${unchangedScheduleLessonSql}))))
             )
           )
        ),
        room_conflicts as (
          select
            'ROOM_OVERLAP'::text as code,
            'room'::text as resource_type,
            lesson.room_id as resource_id,
            lesson.id as lesson_id
          from candidate
          join app.lessons lesson
            on lesson.room_id = candidate.room_id
           and lesson.deleted_at is null
           and lesson.status <> 'cancelled'
           and lesson.lifecycle_state = 'scheduled'
           and lesson.scheduled_at < candidate.ends_at
           and lesson.scheduled_at
                 + lesson.duration_minutes * interval '1 minute'
               > candidate.starts_at
           and (
             candidate.exclude_lesson_id is null
             or lesson.id <> candidate.exclude_lesson_id
           )
           and (
             candidate.exclude_schedule_series_ids is null
             or lesson.series_id is null
             or not (
               lesson.series_id = any(candidate.exclude_schedule_series_ids)
               and exists (select 1 from app.schedule_series series
                 where series.id = lesson.series_id and (
                   (series.plan_id is null and lesson.original_scheduled_at is null)
                   or (series.plan_id is not null and (${unchangedScheduleLessonSql}))))
             )
           )
        ),
        client_conflicts as (
          select
            'CLIENT_OVERLAP'::text as code,
            'client'::text as resource_type,
            candidate.client_id as resource_id,
            lesson.id as lesson_id
          from candidate
          join app.lessons lesson
            on (
              (
                candidate.client_type = 'student'
                and lesson.student_id = candidate.client_id
              )
              or (
                candidate.client_type = 'student'
                and (
                  exists (
                    select 1 from app.lesson_snapshot_participants participant
                    where participant.lesson_id = lesson.id
                      and participant.student_id = candidate.client_id
                  )
                  or exists (
                    select 1 from app.group_students membership
                    where membership.group_id = lesson.group_id
                      and membership.student_id = candidate.client_id
                      and membership.left_at is null
                  )
                )
              )
              or (
                candidate.client_type = 'lead'
                and lesson.lead_id = candidate.client_id
              )
            )
           and lesson.deleted_at is null
           and lesson.lifecycle_state = 'scheduled'
           and lesson.scheduled_at < candidate.ends_at
           and lesson.scheduled_at
                 + lesson.duration_minutes * interval '1 minute'
               > candidate.starts_at
           and (
             candidate.exclude_lesson_id is null
             or lesson.id <> candidate.exclude_lesson_id
           )
           and (
             candidate.exclude_schedule_series_ids is null
             or lesson.series_id is null
             or not (
               lesson.series_id = any(candidate.exclude_schedule_series_ids)
               and exists (select 1 from app.schedule_series series
                 where series.id = lesson.series_id and (
                   (series.plan_id is null and lesson.original_scheduled_at is null)
                   or (series.plan_id is not null and (${unchangedScheduleLessonSql}))))
             )
           )
        )
        select code, resource_type, resource_id, lesson_id
        from teacher_conflicts
        union all
        select code, resource_type, resource_id, lesson_id
        from client_conflicts
        union all
        select code, resource_type, resource_id, lesson_id
        from room_conflicts
        order by code, resource_id, lesson_id
      `,
      [
        draft.teacherId,
        draft.roomId,
        draft.clientRef.type,
        draft.clientRef.id,
        startAt,
        endAt,
        draft.excludeLessonId ?? null,
        draft.excludeScheduleSeriesIds?.length
          ? draft.excludeScheduleSeriesIds
          : null,
      ],
    );
    return result.rows.map((row) => ({
      code: row.code,
      resource: {
        type: row.resource_type,
        id: row.resource_id,
      },
      lessonId: row.lesson_id,
    }));
  }
}
