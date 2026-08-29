import { Injectable, NotFoundException } from "@nestjs/common";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import { DatabaseService } from "../../db/database.service";
import { LessonRow, toLessonDto } from "../crm-mappers";
import type { CompleteLessonDraft } from "./lesson-required-field.validator";
import {
  CurrentLessonRow,
  toExistingLessonDraft,
} from "./lesson-command-integrity";

type Queryable = Pick<PoolClient, "query"> | DatabaseService;

export interface SettlementPlanSourceRow {
  version: number | string;
  lifecycle_state: string;
  branch_id: string;
  scheduled_at: Date | string;
}

export interface ReservedLessonAllocationRow {
  subscription_id: string;
  units: string;
}

function runQuery<T extends QueryResultRow>(
  queryable: Queryable,
  text: string,
  params: unknown[],
): Promise<QueryResult<T>> {
  return (
    queryable.query as (
      query: string,
      values?: unknown[],
    ) => Promise<QueryResult<T>>
  )(text, params);
}

@Injectable()
export class LessonCommandRepository {
  constructor(private readonly database: DatabaseService) {}

  insertLesson(
    client: PoolClient,
    lessonId: string,
    draft: CompleteLessonDraft,
    actorUserId: string,
  ) {
    return client.query(
      `
        insert into app.lessons (
          id, student_id, lead_id, teacher_id, branch_id, room_id,
          scheduled_at, duration_minutes, status, is_trial, notes,
          teacher_rate, created_by
        )
        values (
          $1,
          case when $2 = 'student' then $3::uuid else null end,
          case when $2 = 'lead' then $3::uuid else null end,
          $4, $5, $6, $7, $8, 'scheduled', $9, $10, $11, $12
        )
      `,
      [
        lessonId,
        draft.clientRef.type,
        draft.clientRef.id,
        draft.teacherId,
        draft.branchId,
        draft.roomId,
        draft.scheduledAt,
        draft.durationMinutes,
        draft.isTrial,
        draft.notes,
        draft.teacherCompensationType === "none"
          ? null
          : draft.teacherCompensationValue,
        actorUserId,
      ],
    );
  }

  async loadEffectiveTeacherRate(
    client: PoolClient,
    teacherId: string,
    scheduledAt: string,
  ): Promise<number> {
    const result = await client.query<{ rate: number | string }>(
      `select coalesce((
         select teacher_rate.rate
         from app.teacher_rates teacher_rate
         where teacher_rate.teacher_id = $1
           and teacher_rate.deleted_at is null
           and teacher_rate.effective_from <= $2::timestamptz::date
         order by teacher_rate.effective_from desc, teacher_rate.created_at desc
         limit 1
       ), 0)::numeric as rate`,
      [teacherId, scheduledAt],
    );
    return Number(result.rows[0]?.rate ?? 0);
  }

  updateNotes(
    client: PoolClient,
    lessonId: string,
    notes: string | null,
    expectedVersion: number,
  ) {
    return client.query<{ id: string; version: number | string }>(
      `
        update app.lessons
        set notes = $2,
            updated_at = now()
        where id = $1
          and deleted_at is null
          and version = $3
        returning id, version
      `,
      [lessonId, notes, expectedVersion],
    );
  }

  async loadExisting(queryable: Queryable, lessonId: string, lock = false) {
    const result = await runQuery<CurrentLessonRow>(
      queryable,
      `
        select
          lesson.id,
          lesson.version,
          lesson.student_id,
          lesson.lead_id,
          lesson.teacher_id,
          lesson.branch_id,
          lesson.room_id,
          lesson.scheduled_at,
          lesson.duration_minutes,
          lesson.is_trial,
          lesson.notes,
          snapshot.client_type as snapshot_client_type,
          snapshot.client_id as snapshot_client_id,
          snapshot.completion_type,
          snapshot.client_charge_type,
          snapshot.client_charge_value,
          snapshot.teacher_compensation_type,
          snapshot.teacher_compensation_value,
          snapshot.subscription_id,
          snapshot.trial as snapshot_trial,
          snapshot.validation_state
        from app.lessons lesson
        left join app.lesson_snapshots snapshot
          on snapshot.lesson_id = lesson.id
        where lesson.id = $1 and lesson.deleted_at is null
        ${lock ? "for update of lesson" : ""}
      `,
      [lessonId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    return toExistingLessonDraft(row);
  }

  async response(lessonId: string, version: number, replayed: boolean) {
    const result = await this.database.query<LessonRow>(
      `
        select
          lesson.id, lesson.student_id, lesson.group_id, lesson.lead_id,
          lesson.teacher_id, lesson.branch_id, lesson.room_id,
          lesson.scheduled_at, lesson.duration_minutes, lesson.status,
          lesson.is_trial, lesson.notes, lesson.teacher_rate,
          null::uuid as student_user_id,
          null::uuid as teacher_user_id,
          null::text as student_name,
          null::text as lead_name,
          null::text as teacher_name,
          null::text as branch_name,
          null::text as room_name,
          null::text as group_name,
          null::numeric as group_price_per_lesson
        from app.lessons lesson
        where lesson.id = $1 and lesson.deleted_at is null
      `,
      [lessonId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    return {
      ...toLessonDto(row),
      clientRef: row.lead_id
        ? { type: "lead" as const, id: row.lead_id }
        : { type: "student" as const, id: row.student_id! },
      version,
      replayed,
    };
  }

  async isLeadConverted(client: PoolClient, leadId: string) {
    const conversion = await client.query<{ converted: boolean }>(
      `
        select exists (
          select 1
          from app.client_conversion_links link
          where link.lead_id = $1
        ) as converted
      `,
      [leadId],
    );
    return conversion.rows[0]?.converted === true;
  }

  async loadSettlementSource(client: PoolClient, lessonId: string) {
    const lesson = await client.query<SettlementPlanSourceRow>(
      `select version, lifecycle_state, branch_id, scheduled_at
       from app.lessons
       where id = $1 and deleted_at is null
       for update`,
      [lessonId],
    );
    return lesson.rows[0] ?? null;
  }

  async listReservedAllocations(client: PoolClient, lessonId: string) {
    const result = await client.query<ReservedLessonAllocationRow>(
      `select subscription_id, units::text from app.lesson_reservations
       where lesson_id = $1 and state = 'reserved'
       order by subscription_id`,
      [lessonId],
    );
    return result.rows;
  }

  markCompletedForFinancialPreview(client: PoolClient, lessonId: string) {
    return client.query(
      `update app.lessons set lifecycle_state = 'successfully_completed'
       where id = $1`,
      [lessonId],
    );
  }

  touchSettlementPlan(
    client: PoolClient,
    lessonId: string,
    expectedVersion: number,
  ) {
    return client.query<{ version: number | string }>(
      `update app.lessons set updated_at = now()
       where id = $1 and version = $2 and lifecycle_state = 'scheduled'
       returning version`,
      [lessonId, expectedVersion],
    );
  }
}
