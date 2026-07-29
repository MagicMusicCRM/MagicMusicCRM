import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { IssuedCommercialSnapshot } from "./commerce-schema.types";

export interface ReplacementIssuedRow {
  id: string;
  student_id: string;
  package_id: string;
  lessons_total: string;
  lessons_used: string;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  status: string;
  version: number | string;
  final_price_minor: string;
  currency_code: string;
  commercial_snapshot: IssuedCommercialSnapshot;
  created_at: Date | string;
}

export interface ReplacementPackageRow {
  id: string;
  name: string;
  lessons_total: string;
  base_price_minor: string;
  currency_code: string;
  validity_days: number | null;
  is_active: boolean;
  version: number | string;
  deleted_at: Date | string | null;
}

interface ReplacementContextDatabaseRow {
  issued_id: string;
  student_id: string;
  old_package_id: string;
  old_status: string;
  old_version: number | string;
  old_final_price_minor: string;
  old_currency_code: string;
  legacy_lessons_used: string;
  new_package_id: string | null;
  new_package_name: string | null;
  new_package_units: string | null;
  new_package_price_minor: string | null;
  new_package_currency_code: string | null;
  new_package_validity_days: number | null;
  new_package_active: boolean | null;
  new_package_version: number | string | null;
  new_package_deleted_at: Date | string | null;
  used_units: string;
  actual_paid_minor: string;
  reserved_lesson_count: number | string;
  reserved_units: string;
  reserved_rows: ReplacementReservationRow[];
  future_lesson_count: number | string;
  future_units: string;
}

export interface ReplacementReservationRow {
  reservationId: string;
  lessonId: string;
  scheduledAt: string | null;
  units: string;
}

export interface ReplacementContext {
  issuedSubscriptionId: string;
  studentId: string;
  oldPackageId: string;
  oldStatus: string;
  oldVersion: number;
  oldFinalPriceMinor: string;
  oldCurrencyCode: string;
  legacyLessonsUsed: string;
  newPackage: {
    id: string;
    name: string;
    unitCount: string;
    basePriceMinor: string;
    currencyCode: string;
    validityDays: number | null;
    active: boolean;
    version: number;
    deletedAt: Date | string | null;
  } | null;
  usedUnits: string;
  actualPaidMinor: string;
  reservedLessonCount: number;
  reservedUnits: string;
  reservedRows: ReplacementReservationRow[];
  futureLessonCount: number;
  futureUnits: string;
}

export interface ReplacementObligationRow {
  id: string;
  fact_type: "replacement_debt" | "replacement_overpayment";
  direction: "debit" | "credit";
  amount_minor: string;
  currency_code: string;
}

const replacementContextSql = `
  with recursive lifecycle_chain(id) as (
    select $1::uuid
    union
    select event.before_issued_subscription_id
    from app.subscription_lifecycle_events event
    join lifecycle_chain current
      on current.id = event.after_issued_subscription_id
    where event.event_type = 'replace'
      and event.before_issued_subscription_id is not null
  ),
  current_charge as (
    select sum(fact.units)::numeric as units
    from app.lesson_client_charge_facts fact
    where fact.subscription_id = $1
      and fact.charge_type = 'subscription'
  ),
  reserved_rows as (
    select
      reservation.id as reservation_id,
      reservation.lesson_id,
      lesson.scheduled_at,
      reservation.units
    from app.lesson_reservations reservation
    left join app.lessons lesson on lesson.id = reservation.lesson_id
    where reservation.subscription_id = $1
      and reservation.state = 'reserved'
  ),
  missing_future_rows as (
    select snapshot.lesson_id, snapshot.client_charge_value as units
    from app.lesson_snapshots snapshot
    join app.lessons lesson on lesson.id = snapshot.lesson_id
    where snapshot.subscription_id = $1
      and snapshot.client_charge_type = 'subscription'
      and snapshot.validation_state = 'valid'
      and lesson.deleted_at is null
      and lesson.lifecycle_state = 'scheduled'
      and lesson.scheduled_at >= now()
      and not exists (
        select 1
        from reserved_rows reservation
        where reservation.lesson_id = snapshot.lesson_id
      )
  ),
  future_rows as (
    select lesson_id, units from reserved_rows
    union all
    select lesson_id, units from missing_future_rows
  ),
  payment_total as (
    select coalesce(sum(payment.amount_minor), 0)::bigint as amount_minor
    from app.payments payment
    where payment.deleted_at is null
      and payment.issued_subscription_id in (
        select id from lifecycle_chain
      )
  )
  select
    issued.id as issued_id,
    issued.student_id,
    issued.package_id as old_package_id,
    issued.status as old_status,
    issued.version as old_version,
    issued.final_price_minor as old_final_price_minor,
    issued.currency_code as old_currency_code,
    issued.lessons_used as legacy_lessons_used,
    package.id as new_package_id,
    package.name as new_package_name,
    package.lessons_total as new_package_units,
    package.base_price_minor as new_package_price_minor,
    package.currency_code as new_package_currency_code,
    package.validity_days as new_package_validity_days,
    package.is_active as new_package_active,
    package.version as new_package_version,
    package.deleted_at as new_package_deleted_at,
    coalesce(
      (
        issued.commercial_snapshot
          #>> '{commercialRules,carriedUsedUnits}'
      )::numeric + coalesce((select units from current_charge), 0),
      (select units from current_charge),
      issued.lessons_used,
      0
    )::numeric as used_units,
    (select amount_minor from payment_total) as actual_paid_minor,
    (select count(*) from reserved_rows) as reserved_lesson_count,
    coalesce((select sum(units) from reserved_rows), 0)::numeric
      as reserved_units,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'reservationId', reservation_id,
            'lessonId', lesson_id,
            'scheduledAt', scheduled_at,
            'units', units
          )
          order by scheduled_at nulls last, lesson_id, reservation_id
        )
        from reserved_rows
      ),
      '[]'::jsonb
    ) as reserved_rows,
    (select count(*) from future_rows) as future_lesson_count,
    coalesce((select sum(units) from future_rows), 0)::numeric
      as future_units
  from app.subscriptions issued
  left join app.subscription_packages package on package.id = $2
  where issued.id = $1
    and issued.commercial_snapshot is not null
`;

@Injectable()
export class SubscriptionLifecycleRepository {
  constructor(private readonly database: DatabaseService) {}

  async readReplacementContext(
    issuedSubscriptionId: string,
    newPackageId: string,
  ): Promise<ReplacementContext | null> {
    const result =
      await this.database.query<ReplacementContextDatabaseRow>(
        replacementContextSql,
        [issuedSubscriptionId, newPackageId],
      );
    return this.mapContext(result.rows[0]);
  }

  async lockIssuedSubscription(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<ReplacementIssuedRow | null> {
    const result = await client.query<ReplacementIssuedRow>(
      `
        select
          id,
          student_id,
          package_id,
          lessons_total,
          lessons_used,
          starts_at,
          expires_at,
          status,
          version,
          final_price_minor,
          currency_code,
          commercial_snapshot,
          created_at
        from app.subscriptions
        where id = $1
          and commercial_snapshot is not null
        for update
      `,
      [issuedSubscriptionId],
    );
    return result.rows[0] ?? null;
  }

  async lockPackage(
    client: PoolClient,
    packageId: string,
  ): Promise<ReplacementPackageRow | null> {
    const result = await client.query<ReplacementPackageRow>(
      `
        select
          id,
          name,
          lessons_total,
          base_price_minor,
          currency_code,
          validity_days,
          is_active,
          version,
          deleted_at
        from app.subscription_packages
        where id = $1
        for share
      `,
      [packageId],
    );
    return result.rows[0] ?? null;
  }

  async lockReservedRows(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<void> {
    await client.query(
      `
        select id
        from app.lesson_reservations
        where subscription_id = $1
          and state = 'reserved'
        order by id
        for update
      `,
      [issuedSubscriptionId],
    );
  }

  async readReplacementContextInTransaction(
    client: PoolClient,
    issuedSubscriptionId: string,
    newPackageId: string,
  ): Promise<ReplacementContext | null> {
    const result = await client.query<ReplacementContextDatabaseRow>(
      replacementContextSql,
      [issuedSubscriptionId, newPackageId],
    );
    return this.mapContext(result.rows[0]);
  }

  async closeReplacedSubscription(
    client: PoolClient,
    input: {
      issuedSubscriptionId: string;
      expectedVersion: number;
      nextVersion: number;
    },
  ): Promise<boolean> {
    const result = await client.query(
      `
        update app.subscriptions
        set status = 'replaced',
          version = $3,
          updated_at = now()
        where id = $1
          and status = 'active'
          and version = $2
          and commercial_snapshot is not null
      `,
      [
        input.issuedSubscriptionId,
        input.expectedVersion,
        input.nextVersion,
      ],
    );
    return result.rowCount === 1;
  }

  async createReplacementSubscription(
    client: PoolClient,
    input: {
      id: string;
      studentId: string;
      package: ReplacementPackageRow;
      usedUnits: string;
      snapshot: IssuedCommercialSnapshot;
    },
  ): Promise<ReplacementIssuedRow> {
    const result = await client.query<ReplacementIssuedRow>(
      `
        insert into app.subscriptions (
          id,
          student_id,
          lessons_total,
          lessons_used,
          starts_at,
          expires_at,
          status,
          package_id,
          payment_id,
          commercial_snapshot,
          snapshot_version,
          package_version,
          base_price_minor,
          currency_code,
          discount_type,
          discount_percent_basis_points,
          discount_fixed_minor,
          discount_reason,
          final_price_minor,
          version
        )
        values (
          $1,
          $2,
          $3::numeric,
          $4::numeric,
          current_date,
          case
            when $5::integer is null then null
            else current_date + $5::integer
          end,
          'active',
          $6,
          null,
          $7::jsonb,
          1,
          $8,
          $9::bigint,
          $10,
          null,
          null,
          null,
          null,
          $9::bigint,
          1
        )
        returning
          id,
          student_id,
          package_id,
          lessons_total,
          lessons_used,
          starts_at,
          expires_at,
          status,
          version,
          final_price_minor,
          currency_code,
          commercial_snapshot,
          created_at
      `,
      [
        input.id,
        input.studentId,
        input.package.lessons_total,
        input.usedUnits,
        input.package.validity_days,
        input.package.id,
        JSON.stringify(input.snapshot),
        input.package.version,
        input.package.base_price_minor,
        input.package.currency_code,
      ],
    );
    return result.rows[0]!;
  }

  async initializeIssuedAggregate(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<void> {
    await client.query(
      `
        insert into app.aggregate_versions (
          aggregate_type,
          aggregate_id,
          version
        )
        values ('commerce:issued-subscription', $1, 1)
        on conflict (aggregate_type, aggregate_id)
        do update set
          version = greatest(app.aggregate_versions.version, 1),
          updated_at = now()
      `,
      [issuedSubscriptionId],
    );
  }

  async applyReservationPlan(
    client: PoolClient,
    input: {
      oldIssuedSubscriptionId: string;
      newIssuedSubscriptionId: string;
      transferReservationIds: string[];
      releaseReservationIds: string[];
    },
  ): Promise<{ transferred: number; released: number; remaining: number }> {
    const transferred = await client.query(
      `
        update app.lesson_reservations
        set subscription_id = $2,
          version = version + 1,
          updated_at = now()
        where subscription_id = $1
          and state = 'reserved'
          and id = any($3::uuid[])
      `,
      [
        input.oldIssuedSubscriptionId,
        input.newIssuedSubscriptionId,
        input.transferReservationIds,
      ],
    );
    const released = await client.query(
      `
        update app.lesson_reservations
        set state = 'released',
          version = version + 1,
          updated_at = now()
        where subscription_id = $1
          and state = 'reserved'
          and id = any($2::uuid[])
      `,
      [
        input.oldIssuedSubscriptionId,
        input.releaseReservationIds,
      ],
    );
    const remaining = await client.query<{ count: string }>(
      `
        select count(*)::text as count
        from app.lesson_reservations
        where subscription_id = $1
          and state = 'reserved'
      `,
      [input.oldIssuedSubscriptionId],
    );
    return {
      transferred: transferred.rowCount ?? 0,
      released: released.rowCount ?? 0,
      remaining: Number(remaining.rows[0]?.count ?? 0),
    };
  }

  async createReplacementObligation(
    client: PoolClient,
    input: {
      studentId: string;
      issuedSubscriptionId: string;
      deltaMinor: bigint;
      currencyCode: string;
    },
  ): Promise<ReplacementObligationRow | null> {
    if (input.deltaMinor === 0n) return null;
    const debt = input.deltaMinor > 0n;
    const result = await client.query<ReplacementObligationRow>(
      `
        insert into app.subscription_obligation_facts (
          student_id,
          issued_subscription_id,
          fact_type,
          direction,
          amount_minor,
          currency_code,
          source_type,
          source_ref
        )
        values (
          $1,
          $2,
          $3,
          $4,
          $5::bigint,
          $6,
          'subscription.replace',
          $7
        )
        returning id, fact_type, direction, amount_minor, currency_code
      `,
      [
        input.studentId,
        input.issuedSubscriptionId,
        debt ? "replacement_debt" : "replacement_overpayment",
        debt ? "debit" : "credit",
        (debt ? input.deltaMinor : -input.deltaMinor).toString(),
        input.currencyCode,
        input.issuedSubscriptionId,
      ],
    );
    return result.rows[0]!;
  }

  async createReplaceLifecycle(
    client: PoolClient,
    input: {
      oldIssuedSubscriptionId: string;
      newIssuedSubscriptionId: string;
      actorUserId: string;
      reason: string;
    },
  ): Promise<void> {
    await client.query(
      `
        insert into app.subscription_lifecycle_events (
          issued_subscription_id,
          event_type,
          before_issued_subscription_id,
          after_issued_subscription_id,
          actor_user_id,
          reason,
          aggregate_version
        )
        values ($1, 'replace', $2, $1, $3, $4, 1)
      `,
      [
        input.newIssuedSubscriptionId,
        input.oldIssuedSubscriptionId,
        input.actorUserId,
        input.reason,
      ],
    );
  }

  private mapContext(
    row: ReplacementContextDatabaseRow | undefined,
  ): ReplacementContext | null {
    if (!row) return null;
    const newPackage =
      row.new_package_id &&
      row.new_package_name !== null &&
      row.new_package_units !== null &&
      row.new_package_price_minor !== null &&
      row.new_package_currency_code !== null &&
      row.new_package_active !== null &&
      row.new_package_version !== null
        ? {
            id: row.new_package_id,
            name: row.new_package_name,
            unitCount: row.new_package_units,
            basePriceMinor: row.new_package_price_minor,
            currencyCode: row.new_package_currency_code,
            validityDays: row.new_package_validity_days,
            active: row.new_package_active,
            version: Number(row.new_package_version),
            deletedAt: row.new_package_deleted_at,
          }
        : null;
    return {
      issuedSubscriptionId: row.issued_id,
      studentId: row.student_id,
      oldPackageId: row.old_package_id,
      oldStatus: row.old_status,
      oldVersion: Number(row.old_version),
      oldFinalPriceMinor: row.old_final_price_minor,
      oldCurrencyCode: row.old_currency_code,
      legacyLessonsUsed: row.legacy_lessons_used,
      newPackage,
      usedUnits: normalizeNumeric(row.used_units),
      actualPaidMinor: row.actual_paid_minor,
      reservedLessonCount: Number(row.reserved_lesson_count),
      reservedUnits: normalizeNumeric(row.reserved_units),
      reservedRows: row.reserved_rows.map((reservation) => ({
        reservationId: reservation.reservationId,
        lessonId: reservation.lessonId,
        scheduledAt:
          reservation.scheduledAt === null
            ? null
            : new Date(reservation.scheduledAt).toISOString(),
        units: normalizeNumeric(String(reservation.units)),
      })),
      futureLessonCount: Number(row.future_lesson_count),
      futureUnits: normalizeNumeric(row.future_units),
    };
  }
}

function normalizeNumeric(value: string): string {
  const normalized = value.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "");
  return normalized === "-0" ? "0" : normalized;
}
