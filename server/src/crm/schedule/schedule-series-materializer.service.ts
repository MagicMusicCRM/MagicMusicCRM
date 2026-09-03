import {
  ConflictException,
  Injectable,
  Logger,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import {
  acquireScheduleLockKeys,
  acquireScheduleSeriesLock,
  ScheduleQueryExecutor,
} from "./schedule-locks";

interface SeriesConstraintClientRef {
  type: "lead" | "student";
  id: string;
}

interface SeriesConstraintCandidate {
  series_date: string;
  plan_id: string | null;
  group_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  starts_at: Date | string;
  ends_at: Date | string;
  client_refs: SeriesConstraintClientRef[] | null;
}

interface ScheduleMaterializationOptions {
  includePast?: boolean;
  deferPlanReservations?: boolean;
  replaceableLineageDates?: string[];
}

@Injectable()
export class ScheduleSeriesMaterializerService {
  private readonly logger = new Logger(ScheduleSeriesMaterializerService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly constraints: ScheduleConstraintEngine,
    private readonly reservations?: SubscriptionReservationService,
  ) {}

  // ── KVA-236: постоянное расписание (серии) ────────────────────────────────

  /** Горизонт материализации занятий серии, дней вперёд. */
  static readonly MAX_BOOKING_AHEAD_DAYS = 365;
  private static readonly OPEN_ENDED_PLAN_HORIZON_DAYS = 365;
  private static readonly GROUP_SERIES_HORIZON_DAYS = 400;

  /**
   * Догенерировать занятия серии до горизонта. Идемпотентно: дата серии,
   * уже закрытая строкой lessons.series_date (включая перенесённые и
   * отменённые), повторно не создаётся.
   */
  private async seriesConstraintCandidates(
    seriesId: string,
    executor: ScheduleQueryExecutor = this.database,
    options: ScheduleMaterializationOptions = {},
  ): Promise<SeriesConstraintCandidate[]> {
    const result = await executor.query<SeriesConstraintCandidate>(
      `
        with recursive target as (
          select s.*,
            coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow')
              as effective_timezone,
            timezone(
              coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              now()
            )::date as local_today
          from app.schedule_series s
          left join app.branches branch
            on branch.id = s.branch_id and branch.deleted_at is null
          where s.id = $1 and s.deleted_at is null
        ), lineage(series_id, plan_id) as (
          select id, plan_id from target
          union
          select previous.id, previous.plan_id
            from app.schedule_series previous
            join lineage continuation
              on continuation.plan_id is not null
             and previous.plan_id = continuation.plan_id
             and previous.superseded_by = continuation.series_id
        ), candidates as (
          select s.id as series_id, s.plan_id, s.client_type, s.client_id,
            s.student_id, s.group_id, s.teacher_id, s.branch_id, s.room_id,
            d::date as series_date,
            (d::date + s.begin_time) at time zone s.effective_timezone
              as starts_at,
            (d::date + s.begin_time) at time zone s.effective_timezone
              + s.duration_minutes * interval '1 minute' as ends_at
          from target s
          cross join lateral generate_series(
            case when $4::boolean then s.valid_from else greatest(s.valid_from, s.local_today) end::timestamp,
            coalesce(s.valid_until, greatest(s.valid_from, s.local_today)
                + case when s.plan_id is not null or s.group_id is null
                    then $2::int else $3::int end
            )::timestamp,
            interval '1 day'
          ) as d
          where extract(isodow from d) = s.weekday
            and not exists (
              select 1
                from app.lessons lesson
                join app.schedule_series owner on owner.id = lesson.series_id
              where owner.id in (select series_id from lineage)
                and lesson.series_date = d::date
                and not (
                  lesson.series_date = any($5::date[])
                  and lesson.deleted_at is not null
                  and lesson.lifecycle_state = 'scheduled'
                  and lesson.original_scheduled_at is null
                )
            )
        )
        select candidate.series_date::text, candidate.plan_id,
          candidate.group_id, candidate.teacher_id, candidate.branch_id,
          candidate.room_id, candidate.starts_at, candidate.ends_at,
          case
            when candidate.client_type is not null
              and candidate.client_id is not null
              then jsonb_build_array(jsonb_build_object(
                'type', candidate.client_type,
                'id', candidate.client_id
              ))
            when candidate.student_id is not null
              then jsonb_build_array(jsonb_build_object(
                'type', 'student',
                'id', candidate.student_id
              ))
            when candidate.plan_id is not null then coalesce((
              select jsonb_agg(
                jsonb_build_object('type', 'student', 'id', participant.student_id)
                order by participant.student_id
              )
              from app.schedule_plan_participants participant
              where participant.plan_id = candidate.plan_id
                and participant.effective_from <= candidate.series_date
                and (participant.effective_until is null
                  or participant.effective_until >= candidate.series_date)
            ), '[]'::jsonb)
            when candidate.group_id is not null then coalesce((
              select jsonb_agg(
                jsonb_build_object('type', 'student', 'id', membership.student_id)
                order by membership.student_id
              )
              from app.group_students membership
              join app.students student
                on student.id = membership.student_id and student.deleted_at is null
              where membership.group_id = candidate.group_id
                and membership.left_at is null
            ), '[]'::jsonb)
            else '[]'::jsonb
          end as client_refs
        from candidates candidate
        order by candidate.series_date
      `,
      [
        seriesId,
        ScheduleSeriesMaterializerService.OPEN_ENDED_PLAN_HORIZON_DAYS,
        ScheduleSeriesMaterializerService.GROUP_SERIES_HORIZON_DAYS,
        options.includePast ?? false,
        options.replaceableLineageDates ?? [],
      ],
    );
    return result.rows;
  }

  private seriesConstraintLockKeys(candidates: SeriesConstraintCandidate[]) {
    return candidates.flatMap((candidate) => [
      candidate.plan_id ? `plan:${candidate.plan_id}` : null,
      candidate.branch_id ? `branch:${candidate.branch_id}` : null,
      candidate.room_id ? `room:${candidate.room_id}` : null,
      candidate.teacher_id ? `teacher:${candidate.teacher_id}` : null,
      ...(candidate.client_refs ?? []).map(
        (clientRef) => `client:${clientRef.type}:${clientRef.id}`,
      ),
    ]);
  }

  private async assertNoScheduleSeriesConflicts(
    seriesId: string,
    executor: ScheduleQueryExecutor = this.database,
    options: ScheduleMaterializationOptions = {},
  ): Promise<void> {
    const beforeLock = await this.seriesConstraintCandidates(
      seriesId,
      executor,
      options,
    );
    const lockedKeys = this.seriesConstraintLockKeys(beforeLock);
    await acquireScheduleLockKeys(executor, lockedKeys);
    await acquireScheduleSeriesLock(executor, seriesId);

    // A Plan edit can finish while the worker waits for its locks. Re-read after
    // locking and fail closed if the series moved to resources we did not lock.
    const candidates = await this.seriesConstraintCandidates(
      seriesId,
      executor,
      options,
    );
    const normalizedLockedKeys = new Set(
      lockedKeys
        .filter((key): key is string => typeof key === "string")
        .map((key) => key.toLowerCase()),
    );
    if (
      this.seriesConstraintLockKeys(candidates).some(
        (key) => key != null && !normalizedLockedKeys.has(key.toLowerCase()),
      )
    ) {
      throw new ConflictException({
        code: "SCHEDULE_SERIES_RESOURCES_CHANGED",
        message: "Schedule series resources changed during materialization.",
      });
    }

    for (const candidate of candidates) {
      if (!candidate.teacher_id || !candidate.branch_id || !candidate.room_id) {
        throw new UnprocessableEntityException({
          code: "LESSON_SERIES_REQUIRED_RESOURCES_MISSING",
          message: "Lesson series requires teacher, branch and room.",
          occurrence: { localDate: candidate.series_date },
        });
      }
      const clientRefs = candidate.client_refs?.length
        ? candidate.client_refs
        : [
            {
              type: "student" as const,
              id: candidate.group_id ?? seriesId,
            },
          ];
      for (const clientRef of clientRefs) {
        const result = await this.constraints.validate(
          {
            clientRef,
            teacherId: candidate.teacher_id,
            branchId: candidate.branch_id,
            roomId: candidate.room_id,
            startAt: candidate.starts_at,
            endAt: candidate.ends_at,
            excludeScheduleSeriesIds: [seriesId],
          },
          executor as unknown as PoolClient,
        );
        if (!result.valid) {
          throw new UnprocessableEntityException({
            code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
            message: "Lesson series occurrence violates schedule constraints.",
            occurrence: {
              localDate: candidate.series_date,
              startAt: new Date(candidate.starts_at).toISOString(),
              endAt: new Date(candidate.ends_at).toISOString(),
            },
            clientRef,
            violations: result.violations,
          });
        }
      }
    }
  }

  async materializeSeries(
    seriesId: string,
    executor: ScheduleQueryExecutor = this.database,
    options: ScheduleMaterializationOptions = {},
  ): Promise<number> {
    // The worker, edit and stop flows all serialize on the same key. Without
    // this lock a worker can commit old future lessons after an edit deleted
    // them, or two edits can create competing continuations.
    await this.assertNoScheduleSeriesConflicts(seriesId, executor, options);
    const result = await executor.query<{ id: string }>(
      `
        with recursive target as (
          select series.*
            from app.schedule_series series
           where series.id = $1 and series.deleted_at is null
        ), lineage(series_id, plan_id) as (
          select id, plan_id from target
          union
          select previous.id, previous.plan_id
            from app.schedule_series previous
            join lineage continuation
              on continuation.plan_id is not null
             and previous.plan_id = continuation.plan_id
             and previous.superseded_by = continuation.series_id
        )
        insert into app.lessons (
          student_id, group_id, teacher_id, branch_id, room_id,
          scheduled_at, duration_minutes, status, is_trial,
          series_id, series_date, created_by
        )
        select s.student_id, s.group_id, s.teacher_id, s.branch_id, s.room_id,
          (d::date + s.begin_time) at time zone
            coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
          s.duration_minutes, 'scheduled', false,
          s.id, d::date, s.created_by
        from target s
        left join app.branches branch
          on branch.id = s.branch_id and branch.deleted_at is null
        cross join lateral generate_series(
          case when $4::boolean then s.valid_from else greatest(
            s.valid_from,
            timezone(
              coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              now()
            )::date
          ) end::timestamp,
          coalesce(s.valid_until, greatest(s.valid_from, timezone(
                coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
                now()
              )::date)
                + case when s.plan_id is not null or s.group_id is null
                    then $2::int else $3::int end
          )::timestamp,
          interval '1 day'
        ) as d
        where extract(isodow from d) = s.weekday
          and not exists (
            select 1
              from app.lessons lesson
              join app.schedule_series owner on owner.id = lesson.series_id
            where owner.id in (select series_id from lineage)
              and lesson.series_date = d::date
              and not (
                lesson.series_date = any($5::date[])
                and lesson.deleted_at is not null
                and lesson.lifecycle_state = 'scheduled'
                and lesson.original_scheduled_at is null
              )
          )
        on conflict (series_id, series_date) where deleted_at is null
        do nothing
        returning id
      `,
      [
        seriesId,
        ScheduleSeriesMaterializerService.OPEN_ENDED_PLAN_HORIZON_DAYS,
        ScheduleSeriesMaterializerService.GROUP_SERIES_HORIZON_DAYS,
        options.includePast ?? false,
        options.replaceableLineageDates ?? [],
      ],
    );
    const lessonIds = result.rows.map((row) => row.id);
    if (lessonIds.length === 0) return 0;
    await executor.query(
      `
        with candidate as (
          select lesson.id, lesson.scheduled_at, lesson.duration_minutes,
                 series.client_type, series.client_id, series.completion_type,
                 series.client_charge_type, series.client_charge_value,
                 series.teacher_compensation_type,
                 series.teacher_compensation_value, series.subscription_id,
                 series.trial,
                 case
                   when student.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                     then (student.custom_data->>'individualPrice')::numeric
                   when student.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                     then (student.custom_data->>'individual_price')::numeric
                   else null
                 end as personal_price,
                 row_number() over (order by lesson.scheduled_at, lesson.id) as position
            from app.lessons lesson
            join app.schedule_series series on series.id = lesson.series_id
            left join app.students student
              on series.client_type = 'student' and student.id = series.client_id
           where lesson.id = any($1::uuid[]) and series.client_type is not null
        ), capacity as (
          select subscription.id,
                 greatest(0,
                   subscription.lessons_total - subscription.lessons_used
                   - coalesce((select sum(reservation.units)
                       from app.lesson_reservations reservation
                       where reservation.subscription_id = subscription.id
                         and reservation.state = 'reserved'), 0)
                   - coalesce((select sum(fact.units)
                       from app.lesson_client_charge_facts_effective fact
                       where fact.subscription_id = subscription.id
                         and fact.charge_type = 'subscription'), 0)
                 ) as available
            from app.subscriptions subscription
           where subscription.id = (
             select subscription_id from candidate limit 1
           )
             and subscription.status = 'active'
             and subscription.commercial_snapshot is not null
        ), resolved as (
          select candidate.*,
                 case
                   when candidate.client_charge_type = 'subscription'
                     and exists (
                       select 1 from capacity
                       where capacity.available >= candidate.position
                         * candidate.client_charge_value
                     )
                     and exists (
                       select 1 from app.subscriptions subscription
                       where subscription.id = candidate.subscription_id
                         and (subscription.starts_at is null
                           or subscription.starts_at <= candidate.scheduled_at::date)
                         and (subscription.expires_at is null
                           or subscription.expires_at >= candidate.scheduled_at::date)
                     ) then 'subscription'
                   when candidate.client_charge_type = 'subscription'
                     then 'personal_account'
                   else candidate.client_charge_type
                 end as resolved_charge_type
            from candidate
        )
        insert into app.lesson_snapshots (
          lesson_id, client_type, client_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          subscription_id, trial, duration_minutes
        )
        select id, client_type, client_id, completion_type,
               resolved_charge_type,
               case when resolved_charge_type = 'personal_account'
                      and client_charge_type = 'subscription'
                    then personal_price
                    else client_charge_value end,
               teacher_compensation_type, teacher_compensation_value,
               case when resolved_charge_type = 'subscription'
                    then subscription_id else null end,
               trial, duration_minutes
          from resolved
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_snapshots (
          lesson_id, client_type, client_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          subscription_id, trial, duration_minutes
        )
        select lesson.id, 'student', plan.student_id, 'standard.success',
          'subscription',
          round(
            lesson.duration_minutes::numeric
              * (settlement.item->>'hourShareBasisPoints')::numeric / 6000
          ) / 100,
          case when rate.value > 0 then 'hourly' else 'none' end,
          rate.value, coalesce(series.subscription_id, plan.subscription_id),
          false, lesson.duration_minutes
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.schedule_plans plan on plan.id = series.plan_id
        join app.crm_configuration_revisions revision
          on revision.id = series.settlement_revision_id
        cross join lateral (
          select item
          from jsonb_array_elements(
            revision.effective_snapshot->'lessonSettlementTypes'
          ) item
          where item->>'stableKey' =
            series.planned_financial_decision->>'settlementTypeKey'
          limit 1
        ) settlement
        cross join lateral (
          select coalesce((
            select teacher_rate.rate
            from app.teacher_rates teacher_rate
            where teacher_rate.teacher_id = series.teacher_id
              and teacher_rate.deleted_at is null
              and teacher_rate.effective_from <= lesson.scheduled_at::date
            order by teacher_rate.effective_from desc, teacher_rate.created_at desc
            limit 1
          ), 0)::numeric as value
        ) rate
        where lesson.id = any($1::uuid[]) and plan.kind = 'individual'
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_snapshots (
          lesson_id, group_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          trial, duration_minutes
        )
        select lesson.id, plan.group_id, 'standard.success', 'none', 0,
          case when rate.value <= 0 then 'none'
            when lesson_group.teacher_rate is not null then 'fixed' else 'hourly' end,
          rate.value, false, lesson.duration_minutes
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.schedule_plans plan on plan.id = series.plan_id
        join app.groups lesson_group on lesson_group.id = plan.group_id
        cross join lateral (
          select coalesce(lesson_group.teacher_rate, (
            select teacher_rate.rate
            from app.teacher_rates teacher_rate
            where teacher_rate.teacher_id = series.teacher_id
              and teacher_rate.deleted_at is null
              and teacher_rate.effective_from <= lesson.scheduled_at::date
            order by teacher_rate.effective_from desc, teacher_rate.created_at desc
            limit 1
          ), 0)::numeric as value
        ) rate
        where lesson.id = any($1::uuid[]) and plan.kind = 'group'
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_snapshot_participants (
          lesson_id, student_id, charge_type, charge_value, subscription_id
        )
        select lesson.id, participant.student_id, 'subscription',
          round(
            lesson.duration_minutes::numeric
              * (settlement.item->>'hourShareBasisPoints')::numeric / 6000
          ) / 100,
          participant.subscription_id
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.crm_configuration_revisions revision
          on revision.id = series.settlement_revision_id
        cross join lateral (
          select item
          from jsonb_array_elements(
            revision.effective_snapshot->'lessonSettlementTypes'
          ) item
          where item->>'stableKey' =
            series.planned_financial_decision->>'settlementTypeKey'
          limit 1
        ) settlement
        join app.schedule_plan_participants participant
          on participant.plan_id = series.plan_id
         and participant.effective_from <= lesson.series_date
         and (participant.effective_until is null
           or participant.effective_until >= lesson.series_date)
        where lesson.id = any($1::uuid[])
        on conflict (lesson_id, student_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_settlement_plans (
          lesson_id, decision, settlement_revision_id,
          compensation_revision_id, selected_by
        )
        select lesson.id, series.planned_financial_decision,
          series.settlement_revision_id, series.compensation_revision_id,
          series.created_by
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        where lesson.id = any($1::uuid[])
          and series.planned_financial_decision is not null
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_settlement_plan_revisions (
          lesson_id, version, decision, settlement_revision_id,
          compensation_revision_id, actor_user_id
        )
        select lesson.id, 1, series.planned_financial_decision,
          series.settlement_revision_id, series.compensation_revision_id,
          series.created_by
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.lesson_settlement_plans plan on plan.lesson_id = lesson.id
        where lesson.id = any($1::uuid[])
          and series.planned_financial_decision is not null
        on conflict (lesson_id, version) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_reservations (lesson_id, subscription_id, units)
        select snapshot.lesson_id, snapshot.subscription_id,
               snapshot.client_charge_value
          from app.lesson_snapshots snapshot
          join app.lessons lesson on lesson.id = snapshot.lesson_id
          join app.schedule_series series on series.id = lesson.series_id
         where snapshot.lesson_id = any($1::uuid[])
           and snapshot.client_charge_type = 'subscription'
           and series.plan_id is null
        on conflict do nothing
      `,
      [lessonIds],
    );
    if (!options.deferPlanReservations) {
      await this.allocatePlanReservations(executor, lessonIds);
    }
    await executor.query(
      `update app.schedule_series
       set occurrence_count = coalesce(occurrence_count, 0) + $2,
           updated_at = now()
       where id = $1 and client_type is not null`,
      [seriesId, lessonIds.length],
    );
    return lessonIds.length;
  }

  async allocatePlanReservations(
    executor: ScheduleQueryExecutor,
    lessonIds: string[],
  ): Promise<void> {
    if (!lessonIds.length) return;
    const planCharges = await executor.query<{
      lesson_id: string;
      student_id: string;
      subscription_id: string;
      units: string;
    }>(
      `
        select snapshot.lesson_id, snapshot.client_id as student_id,
          lesson.scheduled_at,
          snapshot.subscription_id, snapshot.client_charge_value::text as units
        from app.lesson_snapshots snapshot
        join app.lessons lesson on lesson.id = snapshot.lesson_id
        join app.schedule_series series on series.id = lesson.series_id
        where snapshot.lesson_id = any($1::uuid[])
          and series.plan_id is not null
          and lesson.deleted_at is null and lesson.lifecycle_state = 'scheduled'
          and not exists (select 1 from app.lesson_reservations existing
            where existing.lesson_id = lesson.id and existing.subscription_id = snapshot.subscription_id
              and existing.state in ('reserved', 'consumed'))
          and not exists (
            select 1 from app.lesson_settlement_plans funding_plan,
              jsonb_array_elements(coalesce(funding_plan.decision->'clientDecisions', '[]'::jsonb)) choice
            where funding_plan.lesson_id = lesson.id and choice->>'clientId' = snapshot.client_id::text
              and (choice->>'chargeType' in ('personal_account', 'none')
                or (choice->>'subscriptionId' is not null and choice->>'subscriptionId' <> snapshot.subscription_id::text))
          )
          and snapshot.client_charge_type = 'subscription'
          and snapshot.client_charge_value > 0
        union all
        select participant.lesson_id, participant.student_id,
          lesson.scheduled_at,
          participant.subscription_id, participant.charge_value::text
        from app.lesson_snapshot_participants participant
        join app.lessons lesson on lesson.id = participant.lesson_id
        join app.schedule_series series on series.id = lesson.series_id
        where participant.lesson_id = any($1::uuid[])
          and series.plan_id is not null
          and lesson.deleted_at is null and lesson.lifecycle_state = 'scheduled'
          and not exists (select 1 from app.lesson_reservations existing
            where existing.lesson_id = lesson.id and existing.subscription_id = participant.subscription_id
              and existing.state in ('reserved', 'consumed'))
          and not exists (
            select 1 from app.lesson_settlement_plans funding_plan,
              jsonb_array_elements(coalesce(funding_plan.decision->'clientDecisions', '[]'::jsonb)) choice
            where funding_plan.lesson_id = lesson.id and choice->>'clientId' = participant.student_id::text
              and (choice->>'chargeType' in ('personal_account', 'none')
                or (choice->>'subscriptionId' is not null and choice->>'subscriptionId' <> participant.subscription_id::text))
          )
          and participant.charge_type = 'subscription'
          and participant.charge_value > 0
        order by subscription_id, scheduled_at, lesson_id
      `,
      [lessonIds],
    );
    if (planCharges.rows.length && !this.reservations) {
      throw new Error(
        "SubscriptionReservationService is required for plan generation.",
      );
    }
    for (const charge of planCharges.rows) {
      await this.reservations!.allocate(executor as PoolClient, {
        lessonId: charge.lesson_id,
        clientType: "student",
        clientId: charge.student_id,
        chargeType: "subscription",
        subscriptionId: charge.subscription_id,
        units: Number(charge.units),
        allowUncovered: true,
      });
    }
  }

  materializePlanSeries(
    client: PoolClient,
    seriesId: string,
    options: ScheduleMaterializationOptions = {},
  ): Promise<number> {
    return this.materializeSeries(seriesId, client, options);
  }

  /** Продлить все живые серии (вкл. «до бесконечности») — вызывается воркером. */
  async extendAllSeriesHorizon(): Promise<{
    series: number;
    created: number;
    failed: number;
  }> {
    const rows = await this.database.query<{ id: string }>(
      `
        select s.id
        from app.schedule_series s
        join app.branches branch on branch.id = s.branch_id
        where s.deleted_at is null
          and (
            s.valid_until is null
            or s.valid_until >= timezone(
              coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              now()
            )::date
          )
      `,
    );
    let created = 0;
    let failed = 0;
    for (const row of rows.rows) {
      // Per-series isolation: one poison series must not starve every series
      // after it in the batch until the next worker tick.
      try {
        created += await this.database.transaction((client) =>
          this.materializeSeries(
            row.id,
            client as unknown as ScheduleQueryExecutor,
          ),
        );
      } catch (error) {
        failed += 1;
        this.logger.error(
          `Failed to materialize schedule series ${row.id}: ${String(error)}`,
        );
      }
    }
    return { series: rows.rows.length, created, failed };
  }
}
