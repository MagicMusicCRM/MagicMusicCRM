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
            $7::uuid as exclude_lesson_id
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
                and exists (
                  select 1 from app.group_students membership
                  where membership.group_id = lesson.group_id
                    and membership.student_id = candidate.client_id
                    and membership.left_at is null
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
