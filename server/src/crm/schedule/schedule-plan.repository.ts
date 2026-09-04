import { Injectable, NotFoundException } from "@nestjs/common";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import {
  SchedulePlanParticipantDto,
  SchedulePlanQuery,
  SchedulePlanRowDto,
} from "../dto/schedule-plan.dto";
import {
  LessonFinancialDecision,
  PreparedLessonSettlementPlan,
} from "../commerce/lesson-settlement.port";
import type {
  SchedulePlanTimelineInput,
  SchedulePlanTimelineLessonInput,
  SchedulePlanTimelineRuleInput,
} from "./schedule-plan-timeline";

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

export interface SchedulePlanSeriesSnapshot {
  id: string;
  valid_from: string;
  teacher_id: string;
  room_id: string;
  branch_id: string;
  weekday: number;
  begin_time: string;
  duration_minutes: number;
  notes: string | null;
  planned_financial_decision: LessonFinancialDecision | null;
  settlement_revision_id: string;
  compensation_revision_id: string;
}

export interface SchedulePlanEndImpact {
  series: Array<{
    id: string;
    version: number;
    validFrom: string;
    validUntil: string | null;
  }>;
  lessons: Array<{
    id: string;
    version: number;
    lifecycleState: "scheduled" | "settlement_pending";
  }>;
  reservations: Array<{
    id: string;
    lessonId: string;
    subscriptionId: string;
    version: number;
    units: string;
  }>;
  terminalLessonCount: number;
}

export interface SchedulePlanTrayCursor {
  scheduledAt: string;
  id: string;
}

export interface SchedulePlanListTimelineSource {
  timelineInput: SchedulePlanTimelineInput;
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
      ended_at: Date | string | null;
      ended_by: string | null;
      ended_by_name: string | null;
      end_reason: string | null;
      participants: Record<string, unknown>[];
      scheduled_lesson_count: string;
      covered_lesson_count: string;
    }>(
      `
        with visible_plans as (
          select plan.*,
            row_number() over (
              partition by plan.status
              order by plan.active_from desc, plan.id
            ) as status_rank
          from app.schedule_plans plan
          where ($3::uuid is null or plan.student_id = $3 or exists (
              select 1 from app.schedule_plan_participants student_participant
              where student_participant.plan_id = plan.id
                and student_participant.student_id = $3
            ))
            and ($4::uuid is null or plan.group_id = $4)
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
        )
        select plan.id, plan.kind, plan.title, plan.student_id, plan.group_id,
          plan.subscription_id, plan.active_from::text,
          plan.active_until::text, plan.status, plan.version, plan.ended_at,
          case when $1::text = any(array['admin','manager','director','system_admin'])
            then plan.ended_by end as ended_by,
          case when $1::text = any(array['admin','manager','director','system_admin'])
            then plan.end_reason end as end_reason,
          case when $1::text = any(array['admin','manager','director','system_admin'])
            then nullif(trim(coalesce(ended_by_profile.first_name, '') || ' ' ||
              coalesce(ended_by_profile.last_name, '')), '')
            end as ended_by_name,
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
          ), '[]'::jsonb) as participants,
          lesson_counts.scheduled as scheduled_lesson_count,
          lesson_counts.covered as covered_lesson_count
        from visible_plans plan
        left join lateral (
          select count(*)::text as scheduled,
            count(*) filter (where lesson.student_id is not null and exists (
              select 1 from app.lesson_reservations reservation
              where reservation.lesson_id = lesson.id and reservation.state = 'reserved'
            ))::text as covered
          from app.lessons lesson
          join app.schedule_series series on series.id = lesson.series_id
          where series.plan_id = plan.id and lesson.deleted_at is null
            and lesson.lifecycle_state = 'scheduled'
        ) lesson_counts on true
        left join app.profiles ended_by_profile
          on ended_by_profile.user_id = plan.ended_by
          and ended_by_profile.deleted_at is null
        where ($5::boolean or plan.status = 'active')
          and (plan.status = 'active' or plan.status_rank <= 20)
        order by (plan.status = 'active') desc, plan.active_from desc, plan.id
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.groupId ?? null,
        query.includeEnded === true,
      ],
    );
    const planIds = result.rows.map((row) => row.id);
    if (planIds.length === 0) return { items: [] };
    const seriesResult = await this.database.query<{
      plan_id: string;
      id: string;
      teacher_id: string;
      teacher_name: string | null;
      room_id: string;
      room_name: string | null;
      branch_id: string;
      branch_name: string | null;
      weekday: number;
      begin_time: string;
      duration_minutes: number;
      valid_from: string;
      valid_until: string | null;
      notes: string | null;
      planned_financial_decision: LessonFinancialDecision | null;
      superseded_by: string | null;
      deleted_at: Date | string | null;
    }>(
      `select series.plan_id, series.id, series.teacher_id,
         nullif(trim(coalesce(teacher_profile.first_name, '') || ' ' ||
           coalesce(teacher_profile.last_name, '')), '') as teacher_name,
         series.room_id, room.name as room_name,
         series.branch_id, branch.name as branch_name,
         series.weekday, to_char(series.begin_time, 'HH24:MI') as begin_time,
         series.duration_minutes, series.valid_from::text,
         series.valid_until::text, series.notes,
         series.planned_financial_decision, series.superseded_by,
         series.deleted_at
       from app.schedule_series series
       left join app.teachers teacher on teacher.id = series.teacher_id
       left join app.profiles teacher_profile on teacher_profile.id = teacher.profile_id
       left join app.rooms room on room.id = series.room_id
       left join app.branches branch on branch.id = series.branch_id
       where series.plan_id = any($1::uuid[])
       order by series.plan_id, series.valid_from, series.weekday,
         series.begin_time, series.id`,
      [planIds],
    );
    const exceptionResult = await this.database.query<{
      plan_id: string;
      lesson_id: string;
      source_series_id: string;
      series_id: string | null;
      scheduled_at: Date | string;
      expected_scheduled_at: Date | string;
      scheduled_date: string;
      teacher_id: string;
      teacher_name: string | null;
      room_id: string;
      room_name: string | null;
      branch_id: string;
      branch_name: string | null;
      weekday: number;
      begin_time: string;
      duration_minutes: number;
      predecessor_id: string | null;
    }>(
      `with recursive lesson_lineage (
         current_lesson_id, source_series_id, source_series_date,
         successor_id, plan_id, path, depth
       ) as (
         select lesson.id, series.id, lesson.series_date, lesson.successor_id,
           series.plan_id, array[lesson.id], 0
         from app.lessons lesson
         join app.schedule_series series on series.id = lesson.series_id
         where series.plan_id = any($1::uuid[])
           and lesson.series_date is not null
           and lesson.deleted_at is null
         union all
         select successor.id, lineage.source_series_id,
           lineage.source_series_date, successor.successor_id,
           lineage.plan_id, lineage.path || successor.id, lineage.depth + 1
         from lesson_lineage lineage
         join app.lessons successor on successor.id = lineage.successor_id
         where lineage.depth < 100
           and successor.deleted_at is null
           and not successor.id = any(lineage.path)
       ), resolved as (
         select distinct on (lineage.current_lesson_id)
           lineage.current_lesson_id, lineage.source_series_id,
           lineage.source_series_date, lineage.plan_id, lineage.depth
         from lesson_lineage lineage
         order by lineage.current_lesson_id, lineage.depth desc
       )
       select resolved.plan_id, lesson.id as lesson_id,
         source_series.id as source_series_id, lesson.series_id,
         lesson.scheduled_at,
         (resolved.source_series_date + source_series.begin_time) at time zone
           coalesce(source_series.timezone_name, source_branch.timezone_name,
             'Europe/Moscow') as expected_scheduled_at,
         to_char(timezone(coalesce(lesson_branch.timezone_name,
           source_branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at),
           'YYYY-MM-DD') as scheduled_date,
         lesson.teacher_id,
         nullif(trim(coalesce(teacher_profile.first_name, '') || ' ' ||
           coalesce(teacher_profile.last_name, '')), '') as teacher_name,
         lesson.room_id, room.name as room_name,
         lesson.branch_id, lesson_branch.name as branch_name,
         extract(isodow from timezone(coalesce(lesson_branch.timezone_name,
           source_branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at))::int
           as weekday,
         to_char(timezone(coalesce(lesson_branch.timezone_name,
           source_branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at),
           'HH24:MI') as begin_time,
         lesson.duration_minutes, lesson.predecessor_id
       from resolved
       join app.lessons lesson on lesson.id = resolved.current_lesson_id
       join app.schedule_series source_series
         on source_series.id = resolved.source_series_id
       left join app.branches source_branch on source_branch.id = source_series.branch_id
       left join app.branches lesson_branch on lesson_branch.id = lesson.branch_id
       left join app.teachers teacher on teacher.id = lesson.teacher_id
       left join app.profiles teacher_profile on teacher_profile.id = teacher.profile_id
       left join app.rooms room on room.id = lesson.room_id
       order by resolved.plan_id, lesson.scheduled_at, lesson.id`,
      [planIds],
    );
    const seriesByPlan = new Map<string, typeof seriesResult.rows>();
    for (const series of seriesResult.rows) {
      const rows = seriesByPlan.get(series.plan_id) ?? [];
      rows.push(series);
      seriesByPlan.set(series.plan_id, rows);
    }
    const exceptionsByPlan = new Map<string, typeof exceptionResult.rows>();
    for (const exception of exceptionResult.rows) {
      const rows = exceptionsByPlan.get(exception.plan_id) ?? [];
      rows.push(exception);
      exceptionsByPlan.set(exception.plan_id, rows);
    }
    return {
      items: result.rows.map((row) => {
        const series = seriesByPlan.get(row.id) ?? [];
        const timelineRules: SchedulePlanTimelineRuleInput[] = series.map(
          (item) => ({
            id: item.id,
            activeFrom: item.valid_from,
            activeUntil: item.valid_until,
            teacherId: item.teacher_id,
            teacherName: item.teacher_name,
            roomId: item.room_id,
            roomName: item.room_name,
            branchId: item.branch_id,
            branchName: item.branch_name,
            weekday: item.weekday,
            beginTime: item.begin_time,
            durationMinutes: item.duration_minutes,
          }),
        );
        const timelineLessons: SchedulePlanTimelineLessonInput[] = (
          exceptionsByPlan.get(row.id) ?? []
        ).map((item) => ({
          id: item.lesson_id,
          sourceSeriesId: item.source_series_id,
          seriesId: item.series_id,
          scheduledAt: new Date(item.scheduled_at).toISOString(),
          expectedScheduledAt: new Date(item.expected_scheduled_at).toISOString(),
          scheduledDate: item.scheduled_date,
          teacherId: item.teacher_id,
          teacherName: item.teacher_name,
          roomId: item.room_id,
          roomName: item.room_name,
          branchId: item.branch_id,
          branchName: item.branch_name,
          weekday: item.weekday,
          beginTime: item.begin_time,
          durationMinutes: item.duration_minutes,
          predecessorId: item.predecessor_id,
        }));
        return {
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
          endedAt:
            row.ended_at == null ? null : new Date(row.ended_at).toISOString(),
          endedBy: row.ended_by,
          endedByName: row.ended_by_name,
          endReason: row.end_reason,
          rows: series
            .filter(
              (item) => item.deleted_at === null && item.superseded_by === null,
            )
            .map((item) => ({
              id: item.id,
              teacherId: item.teacher_id,
              teacherName: item.teacher_name,
              roomId: item.room_id,
              roomName: item.room_name,
              branchId: item.branch_id,
              branchName: item.branch_name,
              weekday: item.weekday,
              beginTime: item.begin_time,
              durationMinutes: item.duration_minutes,
              validFrom: item.valid_from,
              validUntil: item.valid_until,
              notes: item.notes,
              financialDecision: item.planned_financial_decision,
              supersededBy: item.superseded_by,
              active: true,
            })),
          participants: row.participants,
          scheduledLessonCount: Number(row.scheduled_lesson_count),
          coveredLessonCount:
            row.kind === "individual"
              ? Number(row.covered_lesson_count)
              : null,
          timelineInput: {
            rules: timelineRules,
            lessons: timelineLessons,
          },
        } satisfies SchedulePlanListTimelineSource & Record<string, unknown>;
      }),
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
    if (!result.rows[0])
      throw new NotFoundException("План расписания не найден.");
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
      settlementPlan: PreparedLessonSettlementPlan;
      subscriptionId?: string | null;
      supersededBy?: string | null;
    },
  ) {
    return client.query(
      `insert into app.schedule_series (
         id, plan_id, student_id, group_id, teacher_id, room_id, branch_id,
         weekday, begin_time, duration_minutes, valid_from, valid_until,
         notes, created_by, version, planned_financial_decision,
         settlement_revision_id, compensation_revision_id, subscription_id,
         superseded_by
       ) values (
         $1,$2,$3,$4,$5,$6,$7,$8,$9::time,$10,$11::date,$12::date,
         $13,$14,$15,$16::jsonb,$17,$18,$19,$20
       )`,
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
        JSON.stringify(input.settlementPlan.decision),
        input.settlementPlan.settlementRevisionId,
        input.settlementPlan.compensationRevisionId,
        input.subscriptionId ?? null,
        input.supersededBy ?? null,
      ],
    );
  }

  activeSeries(client: PoolClient, planId: string) {
    return client.query<SchedulePlanSeriesSnapshot>(
      `select id, valid_from::text, teacher_id, room_id, branch_id, weekday,
         to_char(begin_time, 'HH24:MI') as begin_time, duration_minutes, notes,
         planned_financial_decision, settlement_revision_id,
         compensation_revision_id
       from app.schedule_series
       where plan_id = $1 and deleted_at is null and superseded_by is null
       order by id for update`,
      [planId],
    );
  }

  freezeActiveSeriesSubscription(
    client: PoolClient,
    seriesIds: string[],
    subscriptionId: string,
  ) {
    return client.query(
      `update app.schedule_series
       set subscription_id = $2, updated_at = now()
       where id = any($1::uuid[]) and subscription_id is null`,
      [seriesIds, subscriptionId],
    );
  }

  async hasImmutableLessonsInRange(
    client: PoolClient,
    planId: string,
    from: string,
    untilExclusive: string,
  ) {
    const result = await client.query<{ immutable: boolean }>(
      `select (
         lesson.deleted_at is not null
         or lesson.lifecycle_state <> 'scheduled'
         or lesson.original_scheduled_at is not null
       ) as immutable
       from app.lessons lesson
       join app.schedule_series series on series.id = lesson.series_id
       where series.plan_id = $1 and lesson.series_date >= $2::date
         and lesson.series_date < $3::date
       order by lesson.series_date, lesson.id
       for update of lesson`,
      [planId, from, untilExclusive],
    );
    return result.rows.some((row) => row.immutable);
  }

  async deleteScheduledLessonsInRange(
    client: PoolClient,
    planId: string,
    from: string,
    untilExclusive: string,
  ) {
    const removed = await client.query<{ id: string }>(
      `update app.lessons lesson set deleted_at = now(), updated_at = now()
       from app.schedule_series series
       where series.plan_id = $1 and lesson.series_id = series.id
         and lesson.series_date >= $2::date and lesson.series_date < $3::date
         and lesson.lifecycle_state = 'scheduled'
         and lesson.original_scheduled_at is null and lesson.deleted_at is null
       returning lesson.id`,
      [planId, from, untilExclusive],
    );
    if (removed.rows.length) {
      await client.query(
        `update app.lesson_reservations set state = 'released', updated_at = now()
         where lesson_id = any($1::uuid[]) and state = 'reserved'`,
        [removed.rows.map((row) => row.id)],
      );
    }
    return removed.rows.map((row) => row.id);
  }

  async isSimpleStartMove(
    client: PoolClient,
    plan: LockedSchedulePlan,
    activeSeriesIds: string[],
  ) {
    const series = await client.query<{
      id: string;
      valid_from: string;
      deleted_at: Date | string | null;
      superseded_by: string | null;
    }>(
      `select id, valid_from::text, deleted_at, superseded_by
       from app.schedule_series where plan_id = $1 order by id for update`,
      [plan.id],
    );
    const activeIds = new Set(activeSeriesIds);
    const simpleSeries =
      series.rows.length === activeIds.size &&
      series.rows.every(
        (row) =>
          activeIds.has(row.id) &&
          row.valid_from === plan.active_from &&
          row.deleted_at === null &&
          row.superseded_by === null,
      );
    if (!simpleSeries || plan.kind !== "group") return simpleSeries;
    const participants = await client.query<{
      effective_from: string;
      effective_until: string | null;
    }>(
      `select effective_from::text, effective_until::text
       from app.schedule_plan_participants
       where plan_id = $1 order by id for update`,
      [plan.id],
    );
    return participants.rows.every(
      (row) =>
        row.effective_from === plan.active_from &&
        row.effective_until === plan.active_until,
    );
  }

  moveSeriesStart(
    client: PoolClient,
    seriesIds: string[],
    activeFrom: string,
    version: number,
  ) {
    return client.query(
      `update app.schedule_series set valid_from = $2::date, version = $3,
         updated_at = now() where id = any($1::uuid[])`,
      [seriesIds, activeFrom, version],
    );
  }

  moveParticipantStart(
    client: PoolClient,
    planId: string,
    activeFrom: string,
    version: number,
  ) {
    return client.query(
      `update app.schedule_plan_participants
       set effective_from = $2::date, version = $3, updated_at = now()
       where plan_id = $1`,
      [planId, activeFrom, version],
    );
  }

  currentSeriesIds(client: PoolClient, planId: string) {
    return client.query<{ id: string }>(
      `select id from app.schedule_series
       where plan_id = $1 and deleted_at is null and superseded_by is null
       order by id`,
      [planId],
    );
  }

  async hasTerminalHistoricalLesson(
    client: PoolClient,
    effectiveFrom: string,
    seriesIds: string[],
  ): Promise<boolean> {
    if (seriesIds.length === 0) return false;
    const terminal = await client.query<{ id: string }>(
      `select lesson.id
         from app.lessons lesson
         join app.schedule_series series on series.id = lesson.series_id
         left join app.branches branch on branch.id = series.branch_id
        where series.id = any($1::uuid[])
          and lesson.series_date >= $2::date
          and lesson.series_date < timezone(
            coalesce(series.timezone_name, branch.timezone_name, 'Europe/Moscow'),
            now()
          )::date
          and (lesson.lifecycle_state <> 'scheduled'
            or lesson.original_scheduled_at is not null)
        order by lesson.series_date, lesson.id
        limit 1
        for update of lesson`,
      [seriesIds, effectiveFrom],
    );
    return Boolean(terminal.rows[0]);
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
    // Terminal, rescheduled and deleted lessons are immutable facts. They stay
    // attached to the exact series snapshot that created them; the materializer
    // treats their date as occupied throughout this plan row's lineage.
    const removed = await client.query<{ id: string; series_date: string }>(
      `update app.lessons lesson
          set deleted_at = now(), updated_at = now()
         from app.schedule_series series
        where series.id = $1 and lesson.series_id = series.id
          and lesson.series_date >= $2::date
          and lesson.lifecycle_state = 'scheduled'
          and lesson.original_scheduled_at is null
          and lesson.deleted_at is null
        returning lesson.id, lesson.series_date::text`,
      [seriesId, effectiveFrom],
    );
    if (removed.rows.length) {
      await client.query(
        `update app.lesson_reservations set state = 'released', updated_at = now()
         where lesson_id = any($1::uuid[]) and state = 'reserved'`,
        [removed.rows.map((row) => row.id)],
      );
    }
    return removed.rows.map((row) => row.series_date);
  }

  updatePlan(
    client: PoolClient,
    input: {
      planId: string;
      title: string;
      subscriptionId: string | null;
      activeFrom: string;
      activeUntil: string | null;
      version: number;
    },
  ) {
    return client.query(
      `update app.schedule_plans
       set title = $2, subscription_id = $3, active_from = $4::date,
         active_until = $5::date, version = $6, updated_at = now()
       where id = $1`,
      [
        input.planId,
        input.title,
        input.subscriptionId,
        input.activeFrom,
        input.activeUntil,
        input.version,
      ],
    );
  }

  extendPlanStart(
    client: PoolClient,
    input: {
      planId: string;
      activeFrom: string;
      title: string;
      version: number;
    },
  ) {
    return client.query(
      `update app.schedule_plans
       set active_from = $2::date, title = $3, version = $4, updated_at = now()
       where id = $1`,
      [input.planId, input.activeFrom, input.title, input.version],
    );
  }

  async endImpact(
    client: PoolClient,
    planId: string,
    lastDate: string,
    lock = false,
  ): Promise<SchedulePlanEndImpact> {
    const series = await client.query<{
      id: string;
      version: string | number;
      valid_from: string;
      valid_until: string | null;
    }>(
      `select id, version, valid_from::text, valid_until::text
       from app.schedule_series
       where plan_id = $1 and deleted_at is null and superseded_by is null
       order by id ${lock ? "for update" : ""}`,
      [planId],
    );
    const lessons = await client.query<{
      id: string;
      version: string | number;
      lifecycle_state: "scheduled" | "settlement_pending";
    }>(
      `select lesson.id, lesson.version, lesson.lifecycle_state
       from app.lessons lesson
       join app.schedule_series series on series.id = lesson.series_id
       where series.plan_id = $1 and lesson.series_date > $2::date
         and lesson.deleted_at is null
         and lesson.lifecycle_state in ('scheduled', 'settlement_pending')
       order by lesson.id ${lock ? "for update of lesson" : ""}`,
      [planId, lastDate],
    );
    const lessonIds = lessons.rows.map((row) => row.id);
    const reservations = lessonIds.length
      ? await client.query<{
          id: string;
          lesson_id: string;
          subscription_id: string;
          version: string | number;
          units: string;
        }>(
          `select id, lesson_id, subscription_id, version, units::text
           from app.lesson_reservations
           where lesson_id = any($1::uuid[]) and state = 'reserved'
           order by id ${lock ? "for update" : ""}`,
          [lessonIds],
        )
      : { rows: [] };
    const terminal = await client.query<{ count: string }>(
      `select count(*)::text as count
       from app.lessons lesson
       join app.schedule_series series on series.id = lesson.series_id
       where series.plan_id = $1 and lesson.series_date > $2::date
         and lesson.deleted_at is null
         and lesson.lifecycle_state not in ('scheduled', 'settlement_pending')`,
      [planId, lastDate],
    );
    return {
      series: series.rows.map((row) => ({
        id: row.id,
        version: Number(row.version),
        validFrom: row.valid_from,
        validUntil: row.valid_until,
      })),
      lessons: lessons.rows.map((row) => ({
        id: row.id,
        version: Number(row.version),
        lifecycleState: row.lifecycle_state,
      })),
      reservations: reservations.rows.map((row) => ({
        id: row.id,
        lessonId: row.lesson_id,
        subscriptionId: row.subscription_id,
        version: Number(row.version),
        units: row.units,
      })),
      terminalLessonCount: Number(terminal.rows[0]?.count ?? 0),
    };
  }

  async finish(
    client: PoolClient,
    input: {
      planId: string;
      expectedVersion: number;
      version: number;
      lastDate: string;
      actorUserId: string;
      reasonText: string;
    },
  ) {
    await client.query(
      `update app.schedule_series
       set valid_until = case when valid_from <= $2::date
             then least(coalesce(valid_until, $2::date), $2::date)
             else valid_until end,
           deleted_at = case when valid_from > $2::date
             then coalesce(deleted_at, now()) else deleted_at end,
           updated_at = now()
       where plan_id = $1 and deleted_at is null and superseded_by is null`,
      [input.planId, input.lastDate],
    );
    return client.query(
      `update app.schedule_plans set status = 'ended', active_until = $3::date,
         version = $4, ended_at = now(), ended_by = $5, end_reason = $6,
         updated_at = now()
       where id = $1 and status = 'active' and version = $2
       returning id`,
      [
        input.planId,
        input.expectedVersion,
        input.lastDate,
        input.version,
        input.actorUserId,
        input.reasonText,
      ],
    );
  }

  cancelLesson(client: PoolClient, lessonId: string, expectedVersion: number) {
    return client.query<{ version: string | number }>(
      `update app.lessons set lifecycle_state = 'cancelled', updated_at = now()
       where id = $1 and version = $2
         and lifecycle_state in ('scheduled', 'settlement_pending')
       returning version`,
      [lessonId, expectedVersion],
    );
  }

  async localToday(client: PoolClient, planId: string): Promise<string> {
    const result = await client.query<{ today: string }>(
      `select max(timezone(branch.timezone_name, now())::date)::text as today
       from app.schedule_series series
       join app.branches branch on branch.id = series.branch_id
       where series.plan_id = $1`,
      [planId],
    );
    return result.rows[0]?.today ?? new Date().toISOString().slice(0, 10);
  }

  async trayPage(
    actor: ActorContext,
    planId: string,
    direction: "previous" | "next",
    cursor: SchedulePlanTrayCursor,
    limit: number,
    inclusive = false,
  ) {
    const comparison = direction === "previous" ? "<" : inclusive ? ">=" : ">";
    const order = direction === "previous" ? "desc" : "asc";
    const result = await this.database.query<{
      id: string;
      scheduled_at: Date | string;
      local_date: string;
      local_time: string;
      lifecycle_state: string;
      predecessor_id: string | null;
      successor_id: string | null;
      teacher_id: string | null;
      teacher_name: string | null;
      room_id: string | null;
      room_name: string | null;
      markers: Array<Record<string, unknown>>;
    }>(
      `with visible_plan as (
         select plan.id from app.schedule_plans plan
         where plan.id = $3 and (
           $1::text = any(array['admin','manager','director','system_admin'])
           or ($1::text = 'teacher' and exists (
             select 1 from app.schedule_series scoped_series
             join app.teachers teacher on teacher.id = scoped_series.teacher_id
             join app.profiles profile on profile.id = teacher.profile_id
             where scoped_series.plan_id = plan.id and profile.user_id = $2::uuid
           ))
           or ($1::text = 'client' and (
             exists (
               select 1 from app.students student join app.profiles profile
                 on profile.id = student.profile_id
               where student.id = plan.student_id and profile.user_id = $2::uuid
             ) or exists (
               select 1 from app.schedule_plan_participants participant
               join app.students student on student.id = participant.student_id
               join app.profiles profile on profile.id = student.profile_id
               where participant.plan_id = plan.id and profile.user_id = $2::uuid
             )
           ))
         )
       )
       select lesson.id, lesson.scheduled_at,
         to_char(timezone(coalesce(branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at),
           'YYYY-MM-DD') as local_date,
         to_char(timezone(coalesce(branch.timezone_name, 'Europe/Moscow'), lesson.scheduled_at),
           'HH24:MI') as local_time,
         lesson.lifecycle_state, lesson.predecessor_id, lesson.successor_id,
         teacher.id as teacher_id,
         nullif(trim(coalesce(profile.first_name, '') || ' ' || coalesce(profile.last_name, '')), '')
           as teacher_name,
         room.id as room_id, room.name as room_name,
         coalesce(marker.markers, '[]'::jsonb) as markers
       from visible_plan
       join app.schedule_series series on series.plan_id = visible_plan.id
       join app.lessons lesson on lesson.series_id = series.id and lesson.deleted_at is null
       left join app.branches branch on branch.id = lesson.branch_id
       left join app.teachers teacher on teacher.id = lesson.teacher_id
       left join app.profiles profile on profile.id = teacher.profile_id
       left join app.rooms room on room.id = lesson.room_id
       left join lateral (
         select jsonb_agg(jsonb_build_object(
           'key', item.settlement_type_key,
           'label', item.settlement_label,
           'colorToken', item.settlement_color_token
         ) order by item.settlement_type_key) as markers
         from (
           select distinct settlement_type_key, settlement_label, settlement_color_token
           from app.lesson_client_charge_facts_effective fact
           where fact.lesson_id = lesson.id and fact.settlement_type_key is not null
           union all
           select 'subscription_reserved', 'Покрыто абонементом', 'success'
           where lesson.student_id is not null and lesson.lifecycle_state = 'scheduled'
             and exists (
               select 1 from app.lesson_reservations reservation
               where reservation.lesson_id = lesson.id and reservation.state = 'reserved'
             )
         ) item
       ) marker on true
       where (lesson.scheduled_at, lesson.id) ${comparison}
         ($4::timestamptz, $5::uuid)
       order by lesson.scheduled_at ${order}, lesson.id ${order}
       limit $6`,
      [
        actor.role,
        actor.userId,
        planId,
        cursor.scheduledAt,
        cursor.id,
        limit + 1,
      ],
    );
    return result.rows;
  }
}
