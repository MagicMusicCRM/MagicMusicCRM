import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { PoolClient } from "pg";
import {
  ClientChargeFactType,
  LessonSettlementResult,
  TeacherCompensationFactType,
} from "./lesson-settlement.port";

interface SettlementSourceRow {
  lesson_id: string;
  lifecycle_state: string;
  teacher_id: string | null;
  group_id: string | null;
  client_type: "lead" | "student" | null;
  client_id: string | null;
  client_charge_type: ClientChargeFactType | null;
  client_charge_value: string | null;
  teacher_compensation_type: TeacherCompensationFactType | null;
  teacher_compensation_value: string | null;
  subscription_id: string | null;
  reservation_subscription_id: string | null;
  reservation_state: string | null;
  duration_minutes: number | null;
  validation_state: string | null;
  participant_count: number | string;
}

@Injectable()
export class LessonSettlementRepository {
  async settle(
    client: PoolClient,
    lessonId: string,
  ): Promise<LessonSettlementResult> {
    await client.query(
      "select pg_advisory_xact_lock(hashtextextended($1, 0))",
      [`commerce:lesson-settlement:${lessonId}`],
    );

    const existing = await this.loadFacts(client, lessonId);
    if (existing) return existing;

    const sourceResult = await client.query<SettlementSourceRow>(
      `
        select
          lesson.id as lesson_id,
          lesson.lifecycle_state,
          lesson.teacher_id,
          snapshot.group_id,
          snapshot.client_type,
          snapshot.client_id,
          snapshot.client_charge_type,
          snapshot.client_charge_value,
          snapshot.teacher_compensation_type,
          snapshot.teacher_compensation_value,
          snapshot.subscription_id,
          reservation.subscription_id as reservation_subscription_id,
          reservation.state as reservation_state,
          snapshot.duration_minutes,
          snapshot.validation_state
          ,(
            select count(*)
            from app.lesson_snapshot_participants participant
            where participant.lesson_id = lesson.id
          ) as participant_count
        from app.lessons lesson
        left join app.lesson_snapshots snapshot
          on snapshot.lesson_id = lesson.id
        left join lateral (
          select subscription_id, state
          from app.lesson_reservations
          where lesson_id = lesson.id
          order by created_at desc, id desc
          limit 1
        ) reservation on true
        where lesson.id = $1
          and lesson.deleted_at is null
        for update of lesson
      `,
      [lessonId],
    );
    const source = sourceResult.rows[0];
    if (!source) throw new NotFoundException("Урок не найден.");
    this.assertSettleable(source);

    await client.query(
      `
        with charges as (
          select
            snapshot.client_type,
            snapshot.client_id,
            snapshot.client_charge_type as charge_type,
            snapshot.client_charge_value as charge_value,
            snapshot.subscription_id
          from app.lesson_snapshots snapshot
          where snapshot.lesson_id = $1 and snapshot.group_id is null
          union all
          select
            'student'::text,
            participant.student_id,
            participant.charge_type,
            participant.charge_value,
            participant.subscription_id
          from app.lesson_snapshot_participants participant
          where participant.lesson_id = $1
        ), effective as (
          select charges.*,
            case
              when charges.charge_type = 'subscription'
                and coverage.subscription_id is null then 'none'
              else charges.charge_type
            end as effective_charge_type,
            coverage.subscription_id as effective_subscription_id
          from charges
          left join lateral (
            select reservation.subscription_id
            from app.lesson_reservations reservation
            join app.subscriptions subscription
              on subscription.id = reservation.subscription_id
            where reservation.lesson_id = $1
              and reservation.state = 'reserved'
              and (
                reservation.subscription_id = charges.subscription_id
                or (
                  charges.client_type = 'student'
                  and subscription.student_id = charges.client_id
                )
              )
            order by
              (reservation.subscription_id = charges.subscription_id) desc,
              reservation.created_at,
              reservation.id
            limit 1
          ) coverage on charges.charge_type = 'subscription'
        )
        insert into app.lesson_client_charge_facts (
          lesson_id,
          client_type,
          client_id,
          charge_type,
          snapshot_value,
          subscription_id,
          amount_minor,
          units
        )
        select
          $1, client_type, client_id, effective_charge_type,
          case when effective_charge_type = 'none' then 0 else charge_value end,
          case when effective_charge_type = 'subscription'
            then effective_subscription_id else null end,
          case
            when effective_charge_type = 'personal_account'
              then round(charge_value * 100)::bigint
            else 0
          end,
          case
            when effective_charge_type = 'subscription' then charge_value
            else 0
          end
        from effective
        order by client_type, client_id
      `,
      [lessonId],
    );

    await client.query(
      `
        insert into app.lesson_teacher_compensation_facts (
          lesson_id,
          teacher_id,
          compensation_type,
          snapshot_rate,
          rate_minor,
          duration_minutes,
          amount_minor
        )
        values (
          $1, $2, $3,
          case when $3 = 'none' then 0 else $4::text::numeric end,
          case
            when $3 = 'none' then 0
            else round($4::text::numeric * 100)::bigint
          end,
          $5::integer,
          case
            when $3 = 'fixed'
              then round($4::text::numeric * 100)::bigint
            when $3 = 'hourly'
              then round(
                $4::text::numeric * 100 * $5::integer / 60
              )::bigint
            else 0
          end
        )
      `,
      [
        lessonId,
        source.teacher_id,
        source.teacher_compensation_type,
        source.teacher_compensation_value,
        source.duration_minutes,
      ],
    );

    const settled = await this.loadFacts(client, lessonId);
    if (!settled) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_INCOMPLETE",
        lessonId,
      });
    }
    return settled;
  }

  private async loadFacts(
    client: PoolClient,
    lessonId: string,
  ): Promise<LessonSettlementResult | null> {
    const clientFacts = await client.query<{
      client_fact_id: string | null;
      client_type: "lead" | "student" | null;
      client_id: string | null;
      charge_type: ClientChargeFactType | null;
      client_snapshot_value: string | null;
      subscription_id: string | null;
      client_amount_minor: string | null;
      units: string | null;
      client_currency_code: string | null;
    }>(
      `
        select
          client_fact.id as client_fact_id,
          client_fact.client_type,
          client_fact.client_id,
          client_fact.charge_type,
          client_fact.snapshot_value as client_snapshot_value,
          client_fact.subscription_id,
          client_fact.amount_minor as client_amount_minor,
          client_fact.units,
          client_fact.currency_code as client_currency_code
        from app.lesson_client_charge_facts client_fact
        where client_fact.lesson_id = $1
        order by client_fact.client_type, client_fact.client_id
      `,
      [lessonId],
    );
    const teacherFacts = await client.query<{
      teacher_fact_id: string;
      teacher_id: string;
      compensation_type: TeacherCompensationFactType;
      teacher_snapshot_rate: string;
      rate_minor: string;
      duration_minutes: number;
      teacher_amount_minor: string;
      teacher_currency_code: string;
    }>(`
      select id as teacher_fact_id, teacher_id, compensation_type,
        snapshot_rate as teacher_snapshot_rate, rate_minor, duration_minutes,
        amount_minor as teacher_amount_minor, currency_code as teacher_currency_code
      from app.lesson_teacher_compensation_facts
      where lesson_id = $1
    `, [lessonId]);
    if (clientFacts.rows.length === 0 && teacherFacts.rows.length === 0) return null;
    const invalidClient = clientFacts.rows.some((row) =>
      !row.client_fact_id || !row.client_type || !row.client_id ||
      !row.charge_type || row.client_snapshot_value === null ||
      row.client_amount_minor === null || row.units === null ||
      !row.client_currency_code,
    );
    const teacher = teacherFacts.rows[0];
    if (invalidClient || clientFacts.rows.length === 0 || !teacher) {
      throw new ConflictException({
        code: "PARTIAL_LESSON_SETTLEMENT",
        lessonId,
      });
    }
    const normalizedClientFacts = clientFacts.rows.map((row) => ({
      id: row.client_fact_id!,
      clientType: row.client_type!,
      clientId: row.client_id!,
      chargeType: row.charge_type!,
      snapshotValue: row.client_snapshot_value!,
      subscriptionId: row.subscription_id,
      amountMinor: row.client_amount_minor!,
      units: row.units!,
      currencyCode: row.client_currency_code!,
    }));
    return {
      lessonId,
      clientFacts: normalizedClientFacts,
      clientFact: normalizedClientFacts[0]!,
      teacherFact: {
        id: teacher.teacher_fact_id,
        teacherId: teacher.teacher_id,
        compensationType: teacher.compensation_type,
        snapshotRate: teacher.teacher_snapshot_rate,
        rateMinor: teacher.rate_minor,
        durationMinutes: Number(teacher.duration_minutes),
        amountMinor: teacher.teacher_amount_minor,
        currencyCode: teacher.teacher_currency_code,
      },
    };
  }

  private assertSettleable(source: SettlementSourceRow) {
    if (source.lifecycle_state !== "successfully_completed") {
      throw new ConflictException({
        code: "LESSON_NOT_SUCCESSFULLY_COMPLETED",
        lessonId: source.lesson_id,
        state: source.lifecycle_state,
      });
    }
    if (
      source.validation_state !== "valid" ||
      !source.teacher_id ||
      !source.client_charge_type ||
      source.client_charge_value === null ||
      !source.teacher_compensation_type ||
      source.teacher_compensation_value === null ||
      !source.duration_minutes ||
      (source.group_id
        ? Number(source.participant_count) === 0
        : !source.client_type || !source.client_id)
    ) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_SNAPSHOT_INCOMPLETE",
        lessonId: source.lesson_id,
      });
    }
  }
}
