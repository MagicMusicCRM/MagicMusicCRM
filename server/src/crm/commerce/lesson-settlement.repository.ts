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

    const effectiveChargeType =
      source.client_charge_type === "subscription" &&
      source.reservation_state !== "reserved"
        ? "none"
        : source.client_charge_type;
    const effectiveChargeValue =
      effectiveChargeType === "none" ? "0" : source.client_charge_value;
    const effectiveSubscriptionId =
      effectiveChargeType === "subscription"
        ? source.reservation_subscription_id
        : null;

    await client.query(
      `
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
        values (
          $1, $2, $3, $4,
          case when $4 = 'none' then 0 else $5::text::numeric end,
          $6,
          case
            when $4 = 'personal_account'
              then round($5::text::numeric * 100)::bigint
            else 0
          end,
          case
            when $4 = 'subscription' then $5::text::numeric
            else 0
          end
        )
      `,
      [
        lessonId,
        source.client_type,
        source.client_id,
        effectiveChargeType,
        effectiveChargeValue,
        effectiveSubscriptionId,
      ],
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
    const facts = await client.query<{
      client_fact_id: string | null;
      client_type: "lead" | "student" | null;
      client_id: string | null;
      charge_type: ClientChargeFactType | null;
      client_snapshot_value: string | null;
      subscription_id: string | null;
      client_amount_minor: string | null;
      units: string | null;
      client_currency_code: string | null;
      teacher_fact_id: string | null;
      teacher_id: string | null;
      compensation_type: TeacherCompensationFactType | null;
      teacher_snapshot_rate: string | null;
      rate_minor: string | null;
      duration_minutes: number | null;
      teacher_amount_minor: string | null;
      teacher_currency_code: string | null;
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
          client_fact.currency_code as client_currency_code,
          teacher_fact.id as teacher_fact_id,
          teacher_fact.teacher_id,
          teacher_fact.compensation_type,
          teacher_fact.snapshot_rate as teacher_snapshot_rate,
          teacher_fact.rate_minor,
          teacher_fact.duration_minutes,
          teacher_fact.amount_minor as teacher_amount_minor,
          teacher_fact.currency_code as teacher_currency_code
        from app.lesson_client_charge_facts client_fact
        full join app.lesson_teacher_compensation_facts teacher_fact
          on teacher_fact.lesson_id = client_fact.lesson_id
        where coalesce(client_fact.lesson_id, teacher_fact.lesson_id) = $1
      `,
      [lessonId],
    );
    const row = facts.rows[0];
    if (!row) return null;
    if (
      !row.client_fact_id ||
      !row.client_type ||
      !row.client_id ||
      !row.charge_type ||
      row.client_snapshot_value === null ||
      row.client_amount_minor === null ||
      row.units === null ||
      !row.client_currency_code ||
      !row.teacher_fact_id ||
      !row.teacher_id ||
      !row.compensation_type ||
      row.teacher_snapshot_rate === null ||
      row.rate_minor === null ||
      row.duration_minutes === null ||
      row.teacher_amount_minor === null ||
      !row.teacher_currency_code
    ) {
      throw new ConflictException({
        code: "PARTIAL_LESSON_SETTLEMENT",
        lessonId,
      });
    }
    return {
      lessonId,
      clientFact: {
        id: row.client_fact_id,
        clientType: row.client_type,
        clientId: row.client_id,
        chargeType: row.charge_type,
        snapshotValue: row.client_snapshot_value,
        subscriptionId: row.subscription_id,
        amountMinor: row.client_amount_minor,
        units: row.units,
        currencyCode: row.client_currency_code,
      },
      teacherFact: {
        id: row.teacher_fact_id,
        teacherId: row.teacher_id,
        compensationType: row.compensation_type,
        snapshotRate: row.teacher_snapshot_rate,
        rateMinor: row.rate_minor,
        durationMinutes: Number(row.duration_minutes),
        amountMinor: row.teacher_amount_minor,
        currencyCode: row.teacher_currency_code,
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
      !source.client_type ||
      !source.client_id ||
      !source.client_charge_type ||
      source.client_charge_value === null ||
      !source.teacher_compensation_type ||
      source.teacher_compensation_value === null ||
      !source.duration_minutes
    ) {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_SNAPSHOT_INCOMPLETE",
        lessonId: source.lesson_id,
      });
    }
  }
}
