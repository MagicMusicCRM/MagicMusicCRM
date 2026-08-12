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
               and lesson.original_scheduled_at is null
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
               and lesson.original_scheduled_at is null
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
               and lesson.original_scheduled_at is null
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
