import { Injectable, NotFoundException } from "@nestjs/common";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import {
  SchedulePlanParticipantDto,
  SchedulePlanQuery,
  SchedulePlanRowDto,
} from "../dto/schedule-plan.dto";

export interface LockedSchedulePlan {
  id: string;
  kind: "individual" | "group";
  title: string;
  student_id: string | null;
  group_id: string | null;
  subscription_id: string | null;
  active_from: string;
  active_until: string | null;
  status: "active" | "ended";
  version: string | number;
}

@Injectable()
export class SchedulePlanRepository {
  constructor(private readonly database: DatabaseService) {}

  async list(actor: ActorContext, query: SchedulePlanQuery) {
    const result = await this.database.query<{
      id: string;
      kind: "individual" | "group";
      title: string;
      student_id: string | null;
      group_id: string | null;
      subscription_id: string | null;
      active_from: string;
      active_until: string | null;
      status: "active" | "ended";
      version: string | number;
      series: Record<string, unknown>[];
      participants: Record<string, unknown>[];
    }>(
      `
        select plan.id, plan.kind, plan.title, plan.student_id, plan.group_id,
          plan.subscription_id, plan.active_from::text,
          plan.active_until::text, plan.status, plan.version,
          coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', series.id,
              'teacherId', series.teacher_id,
              'roomId', series.room_id,
              'branchId', series.branch_id,
              'weekday', series.weekday,
              'beginTime', to_char(series.begin_time, 'HH24:MI'),
              'durationMinutes', series.duration_minutes,
              'validFrom', series.valid_from,
              'validUntil', series.valid_until,
              'notes', series.notes,
              'supersededBy', series.superseded_by,
              'active', series.deleted_at is null and series.superseded_by is null
            ) order by series.valid_from, series.weekday, series.begin_time, series.id)
            from app.schedule_series series where series.plan_id = plan.id
          ), '[]'::jsonb) as series,
          coalesce((
            select jsonb_agg(jsonb_build_object(
              'id', participant.id,
              'studentId', participant.student_id,
              'subscriptionId', participant.subscription_id,
              'effectiveFrom', participant.effective_from,
              'effectiveUntil', participant.effective_until,
              'version', participant.version
            ) order by participant.effective_from, participant.student_id)
            from app.schedule_plan_participants participant
            where participant.plan_id = plan.id
          ), '[]'::jsonb) as participants
        from app.schedule_plans plan
        where ($3::uuid is null or plan.student_id = $3)
          and ($4::uuid is null or plan.group_id = $4)
          and ($5::boolean or plan.status = 'active')
          and (
            $1::text = any(array['admin','manager','director','system_admin'])
            or ($1::text = 'teacher' and exists (
              select 1 from app.schedule_series scoped_series
              join app.teachers teacher on teacher.id = scoped_series.teacher_id
              join app.profiles profile on profile.id = teacher.profile_id
              where scoped_series.plan_id = plan.id
                and profile.user_id = $2::uuid
            ))
            or ($1::text = 'client' and (
              exists (
                select 1 from app.students student
                join app.profiles profile on profile.id = student.profile_id
                where student.id = plan.student_id and profile.user_id = $2::uuid
              )
              or exists (
                select 1 from app.schedule_plan_participants participant
                join app.students student on student.id = participant.student_id
                join app.profiles profile on profile.id = student.profile_id
                where participant.plan_id = plan.id and profile.user_id = $2::uuid
              )
            ))
          )
        order by (plan.status = 'active') desc, plan.active_from desc, plan.id
        limit 100
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.groupId ?? null,
        query.includeEnded === true,
      ],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        kind: row.kind,
        title: row.title,
        studentId: row.student_id,
        groupId: row.group_id,
        subscriptionId: row.subscription_id,
        activeFrom: row.active_from,
        activeUntil: row.active_until,
        status: row.status,
        version: Number(row.version),
        rows: row.series,
        participants: row.participants,
      })),
    };
  }

  insertPlan(
    client: PoolClient,
    input: {
      id: string;
      kind: "individual" | "group";
      title: string;
      studentId: string | null;
      groupId: string | null;
      subscriptionId: string | null;
      activeFrom: string;
      activeUntil: string | null;
      actorUserId: string;
      version: number;
    },
  ) {
    return client.query(
      `insert into app.schedule_plans (
         id, kind, title, student_id, group_id, subscription_id,
         active_from, active_until, created_by, version
       ) values ($1,$2,$3,$4,$5,$6,$7::date,$8::date,$9,$10)`,
      [
        input.id,
        input.kind,
        input.title,
        input.studentId,
        input.groupId,
        input.subscriptionId,
        input.activeFrom,
        input.activeUntil,
        input.actorUserId,
        input.version,
      ],
    );
  }

  async lock(client: PoolClient, planId: string): Promise<LockedSchedulePlan> {
    const result = await client.query<LockedSchedulePlan>(
      `select id, kind, title, student_id, group_id, subscription_id,
         active_from::text, active_until::text, status, version
       from app.schedule_plans where id = $1 for update`,
      [planId],
    );
    if (!result.rows[0]) throw new NotFoundException("План расписания не найден.");
    return result.rows[0];
  }

  insertParticipants(
    client: PoolClient,
    planId: string,
    participants: SchedulePlanParticipantDto[],
    effectiveFrom: string,
    effectiveUntil: string | null,
    version: number,
  ) {
    return Promise.all(
      participants.map((participant) =>
        client.query(
          `insert into app.schedule_plan_participants (
             plan_id, student_id, subscription_id,
             effective_from, effective_until, version
           ) values ($1,$2,$3,$4::date,$5::date,$6)`,
          [
            planId,
            participant.studentId,
            participant.subscriptionId,
            effectiveFrom,
            effectiveUntil,
            version,
          ],
        ),
      ),
    );
  }

  async replaceParticipants(
    client: PoolClient,
    planId: string,
    participants: SchedulePlanParticipantDto[],
    effectiveFrom: string,
    effectiveUntil: string | null,
    version: number,
  ) {
    await client.query(
      `update app.schedule_plan_participants
       set effective_until = ($2::date - 1)::date, updated_at = now(), version = $3
       where plan_id = $1 and effective_from < $2::date
         and (effective_until is null or effective_until >= $2::date)`,
      [planId, effectiveFrom, version],
    );
    await client.query(
      `delete from app.schedule_plan_participants
       where plan_id = $1 and effective_from >= $2::date`,
      [planId, effectiveFrom],
    );
    await this.insertParticipants(
      client,
      planId,
      participants,
      effectiveFrom,
      effectiveUntil,
      version,
    );
  }

  insertSeries(
    client: PoolClient,
    input: {
      id: string;
      planId: string;
      studentId: string | null;
      groupId: string | null;
      validFrom: string;
      validUntil: string | null;
      row: SchedulePlanRowDto;
      actorUserId: string;
      version: number;
    },
  ) {
    return client.query(
      `insert into app.schedule_series (
         id, plan_id, student_id, group_id, teacher_id, room_id, branch_id,
         weekday, begin_time, duration_minutes, valid_from, valid_until,
         notes, created_by, version
       ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9::time,$10,$11::date,$12::date,$13,$14,$15)`,
      [
        input.id,
        input.planId,
        input.studentId,
        input.groupId,
        input.row.teacherId,
        input.row.roomId,
        input.row.branchId,
        input.row.weekday,
        input.row.beginTime,
        input.row.durationMinutes ?? 60,
        input.validFrom,
        input.validUntil,
        input.row.notes?.trim() || null,
        input.actorUserId,
        input.version,
      ],
    );
  }

  activeSeries(client: PoolClient, planId: string) {
    return client.query<{ id: string }>(
      `select id from app.schedule_series
       where plan_id = $1 and deleted_at is null and superseded_by is null
       order by id for update`,
      [planId],
    );
  }

  async retireSeries(
    client: PoolClient,
    seriesId: string,
    effectiveFrom: string,
    continuationId: string | null,
  ) {
    await client.query(
      `update app.schedule_series
       set valid_until = case when valid_from < $2::date then least(
             coalesce(valid_until, ($2::date - 1)::date),
             ($2::date - 1)::date
           ) else valid_until end,
           deleted_at = case when valid_from >= $2::date
             then coalesce(deleted_at, now()) else deleted_at end,
           superseded_by = $3::uuid,
           updated_at = now()
       where id = $1 and superseded_by is null`,
      [seriesId, effectiveFrom, continuationId],
    );
    if (continuationId) {
      await client.query(
        `update app.lessons set series_id = $2, updated_at = now()
         where series_id = $1 and series_date >= $3::date
           and (deleted_at is not null or lifecycle_state <> 'scheduled'
             or original_scheduled_at is not null)`,
        [seriesId, continuationId, effectiveFrom],
      );
    }
    const removed = await client.query<{ id: string }>(
      `update app.lessons set deleted_at = now(), updated_at = now()
       where series_id = $1 and series_date >= $2::date
         and lifecycle_state = 'scheduled' and original_scheduled_at is null
         and deleted_at is null returning id`,
      [seriesId, effectiveFrom],
    );
    if (removed.rows.length) {
      await client.query(
        `update app.lesson_reservations set state = 'released', updated_at = now()
         where lesson_id = any($1::uuid[]) and state = 'reserved'`,
        [removed.rows.map((row) => row.id)],
      );
    }
  }

  updatePlan(
    client: PoolClient,
    input: {
      planId: string;
      title: string;
      subscriptionId: string | null;
      activeUntil: string | null;
      version: number;
    },
  ) {
    return client.query(
      `update app.schedule_plans
       set title = $2, subscription_id = $3, active_until = $4::date,
         version = $5, updated_at = now()
       where id = $1`,
      [
        input.planId,
        input.title,
        input.subscriptionId,
        input.activeUntil,
        input.version,
      ],
    );
  }
}
