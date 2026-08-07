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
  payer_student_id: string;
  funding_mode: "personal_account" | "installment" | "legacy";
  purchase_reason: string | null;
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
  payerStudentId: string;
  fundingMode: "personal_account" | "installment" | "legacy";
  purchaseReason: string | null;
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

export interface CancellationCreditRow {
  id: string;
  amount_minor: string;
}

interface CancellationContextDatabaseRow {
  issued_id: string;
  student_id: string;
  payer_student_id: string;
  funding_mode: "personal_account" | "installment" | "legacy";
  package_id: string;
  package_name: string;
  package_version: number | string;
  unit_count: string;
  status: string;
  version: number | string;
  currency_code: string;
  final_minor: string;
  used_units: string;
  actual_paid_minor: string;
  previous_refund_minor: string;
  writeoff_minor: string;
  net_obligation_minor: string;
  balance_minor: string;
  payment_refs: CancellationPaymentRef[];
  previous_refund_refs: CancellationRefundRef[];
  open_payment_record_refs: CancellationPaymentRecordRef[];
  writeoff_refs: CancellationWriteoffRef[];
  obligation_refs: CancellationObligationRef[];
  future_lesson_count: number | string;
  reserved_lesson_count: number | string;
  reserved_units: string;
  future_lessons: CancellationFutureLesson[];
}

export interface CancellationPaymentRef {
  id: string;
  amountMinor: string;
  occurredAt: string;
}

export interface CancellationRefundRef {
  id: string;
  amountMinor: string;
  occurredAt: string;
}

export interface CancellationPaymentRecordRef {
  id: string;
  status: "unpaid" | "posted_pending";
  version: number;
  amountMinor: string;
}

export interface CancellationWriteoffRef {
  id: string;
  lessonId: string;
  amountMinor: string;
  units: string;
  occurredAt: string;
}

export interface CancellationObligationRef {
  id: string;
  direction: "debit" | "credit";
  amountMinor: string;
  occurredAt: string;
}

export interface CancellationFutureLesson {
  lessonId: string;
  reservationId: string | null;
  scheduledAt: string;
  units: string;
  reserved: boolean;
}

export interface CancellationContext {
  issuedSubscriptionId: string;
  studentId: string;
  payerStudentId: string;
  fundingMode: "personal_account" | "installment" | "legacy";
  package: {
    id: string;
    name: string;
    version: number;
    unitCount: string;
  };
  status: string;
  version: number;
  currencyCode: string;
  finalMinor: string;
  usedUnits: string;
  actualPaidMinor: string;
  previousRefundMinor: string;
  writeoffMinor: string;
  netObligationMinor: string;
  balanceMinor: string;
  paymentRefs: CancellationPaymentRef[];
  previousRefundRefs: CancellationRefundRef[];
  openPaymentRecordRefs: CancellationPaymentRecordRef[];
  writeoffRefs: CancellationWriteoffRef[];
  obligationRefs: CancellationObligationRef[];
  futureLessonCount: number;
  reservedLessonCount: number;
  reservedUnits: string;
  futureLessons: CancellationFutureLesson[];
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
    from app.commerce_ordinary_payments payment
    where payment.deleted_at is null
      and payment.issued_subscription_id in (
        select id from lifecycle_chain
      )
  )
  select
    issued.id as issued_id,
    issued.student_id,
    coalesce(
      issued.payer_student_id,
      (
        select ancestor.payer_student_id
        from lifecycle_chain chain
        join app.subscriptions ancestor on ancestor.id = chain.id
        where ancestor.payer_student_id is not null
        order by ancestor.created_at desc, ancestor.id desc
        limit 1
      ),
      issued.student_id
    ) as payer_student_id,
    coalesce(
      issued.funding_mode,
      (
        select ancestor.funding_mode
        from lifecycle_chain chain
        join app.subscriptions ancestor on ancestor.id = chain.id
        where ancestor.funding_mode is not null
        order by ancestor.created_at desc, ancestor.id desc
        limit 1
      ),
      'legacy'
    ) as funding_mode,
    coalesce(
      issued.purchase_reason,
      (
        select ancestor.purchase_reason
        from lifecycle_chain chain
        join app.subscriptions ancestor on ancestor.id = chain.id
        where ancestor.purchase_reason is not null
        order by ancestor.created_at desc, ancestor.id desc
        limit 1
      )
    ) as purchase_reason,
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

const cancellationContextSql = `
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
  payment_rows as (
    select
      payment.id,
      payment.amount_minor,
      payment.payment_date
    from app.commerce_ordinary_payments payment
    where payment.deleted_at is null
      and payment.issued_subscription_id in (
        select id from lifecycle_chain
      )
  ),
  previous_refund_rows as (
    select
      adjustment.id,
      abs(adjustment.amount_minor)::bigint as amount_minor,
      adjustment.occurred_at
    from app.commerce_ordinary_account_adjustments adjustment
    join app.commerce_ordinary_payments source_payment
      on source_payment.id = adjustment.source_payment_id
    where adjustment.deleted_at is null
      and adjustment.status = 'paid'
      and adjustment.amount_minor < 0
      and source_payment.issued_subscription_id in (
        select id from lifecycle_chain
      )
  ),
  open_payment_record_rows as (
    select
      record.id,
      record.status,
      record.version,
      record.amount_minor
    from app.commerce_ordinary_payment_records record
    where record.issued_subscription_id in (
        select id from lifecycle_chain
      )
      and record.status in ('unpaid', 'posted_pending')
  ),
  writeoff_rows as (
    select
      fact.id,
      fact.lesson_id,
      fact.amount_minor,
      fact.units,
      fact.created_at
    from app.lesson_client_charge_facts fact
    where fact.subscription_id in (
      select id from lifecycle_chain
    )
  ),
  obligation_rows as (
    select
      fact.id,
      fact.direction,
      fact.amount_minor,
      fact.occurred_at
    from app.subscription_obligation_facts fact
    where fact.issued_subscription_id in (
      select id from lifecycle_chain
    )
  ),
  reserved_rows as (
    select
      reservation.id as reservation_id,
      reservation.lesson_id,
      lesson.scheduled_at,
      reservation.units
    from app.lesson_reservations reservation
    join app.lessons lesson on lesson.id = reservation.lesson_id
    where reservation.subscription_id = $1
      and reservation.state = 'reserved'
  ),
  missing_future_rows as (
    select
      null::uuid as reservation_id,
      snapshot.lesson_id,
      lesson.scheduled_at,
      snapshot.client_charge_value as units
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
    select
      reservation_id,
      lesson_id,
      scheduled_at,
      units,
      true as reserved
    from reserved_rows
    union all
    select
      reservation_id,
      lesson_id,
      scheduled_at,
      units,
      false as reserved
    from missing_future_rows
  ),
  totals as (
    select
      coalesce((select sum(amount_minor) from payment_rows), 0)::bigint
        as actual_paid_minor,
      coalesce((select sum(amount_minor) from previous_refund_rows), 0)::bigint
        as previous_refund_minor,
      coalesce((select sum(amount_minor) from writeoff_rows), 0)::bigint
        as writeoff_minor,
      coalesce(
        (
          select sum(
            case
              when direction = 'debit' then amount_minor
              else -amount_minor
            end
          )
          from obligation_rows
        ),
        0
      )::bigint as net_obligation_minor
  )
  select
    issued.id as issued_id,
    issued.student_id,
    coalesce(
      issued.payer_student_id,
      (
        select ancestor.payer_student_id
        from lifecycle_chain chain
        join app.subscriptions ancestor on ancestor.id = chain.id
        where ancestor.payer_student_id is not null
        order by ancestor.created_at desc, ancestor.id desc
        limit 1
      ),
      issued.student_id
    ) as payer_student_id,
    coalesce(
      issued.funding_mode,
      (
        select ancestor.funding_mode
        from lifecycle_chain chain
        join app.subscriptions ancestor on ancestor.id = chain.id
        where ancestor.funding_mode is not null
        order by ancestor.created_at desc, ancestor.id desc
        limit 1
      ),
      'legacy'
    ) as funding_mode,
    issued.package_id,
    issued.commercial_snapshot ->> 'displayName' as package_name,
    issued.package_version,
    issued.lessons_total as unit_count,
    issued.status,
    issued.version,
    issued.currency_code,
    issued.final_price_minor as final_minor,
    coalesce(
      (
        issued.commercial_snapshot
          #>> '{commercialRules,carriedUsedUnits}'
      )::numeric + coalesce((select units from current_charge), 0),
      (select units from current_charge),
      issued.lessons_used,
      0
    )::numeric as used_units,
    totals.actual_paid_minor,
    totals.previous_refund_minor,
    totals.writeoff_minor,
    totals.net_obligation_minor,
    (
      totals.actual_paid_minor - totals.net_obligation_minor
    )::bigint as balance_minor,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'amountMinor', amount_minor::text,
            'occurredAt', payment_date
          )
          order by payment_date, id
        )
        from payment_rows
      ),
      '[]'::jsonb
    ) as payment_refs,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'amountMinor', amount_minor::text,
            'occurredAt', occurred_at
          )
          order by occurred_at, id
        )
        from previous_refund_rows
      ),
      '[]'::jsonb
    ) as previous_refund_refs,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'status', status,
            'version', version,
            'amountMinor', amount_minor::text
          )
          order by id
        )
        from open_payment_record_rows
      ),
      '[]'::jsonb
    ) as open_payment_record_refs,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'lessonId', lesson_id,
            'amountMinor', amount_minor::text,
            'units', units::text,
            'occurredAt', created_at
          )
          order by created_at, id
        )
        from writeoff_rows
      ),
      '[]'::jsonb
    ) as writeoff_refs,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'direction', direction,
            'amountMinor', amount_minor::text,
            'occurredAt', occurred_at
          )
          order by occurred_at, id
        )
        from obligation_rows
      ),
      '[]'::jsonb
    ) as obligation_refs,
    (select count(*) from future_rows) as future_lesson_count,
    (select count(*) from reserved_rows) as reserved_lesson_count,
    coalesce((select sum(units) from reserved_rows), 0)::numeric
      as reserved_units,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'lessonId', lesson_id,
            'reservationId', reservation_id,
            'scheduledAt', scheduled_at,
            'units', units::text,
            'reserved', reserved
          )
          order by scheduled_at, lesson_id, reservation_id nulls last
        )
        from future_rows
      ),
      '[]'::jsonb
    ) as future_lessons
  from app.subscriptions issued
  cross join totals
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

  async readCancellationContext(
    issuedSubscriptionId: string,
  ): Promise<CancellationContext | null> {
    const result =
      await this.database.query<CancellationContextDatabaseRow>(
        cancellationContextSql,
        [issuedSubscriptionId],
      );
    return this.mapCancellationContext(result.rows[0]);
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

  async lockCancellationInstallments(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<void> {
    await client.query(
      `
        with recursive lifecycle_chain(id) as (
          select $1::uuid
          union
          select event.before_issued_subscription_id
          from app.subscription_lifecycle_events event
          join lifecycle_chain current
            on current.id = event.after_issued_subscription_id
          where event.event_type = 'replace'
            and event.before_issued_subscription_id is not null
        )
        select installment.id
        from app.subscription_installments installment
        where installment.issued_subscription_id in (
          select id from lifecycle_chain
        )
        order by installment.id
        for update of installment
      `,
      [issuedSubscriptionId],
    );
  }

  async lockCancellationPaymentRecords(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<void> {
    await client.query(
      `
        with recursive lifecycle_chain(id) as (
          select $1::uuid
          union
          select event.before_issued_subscription_id
          from app.subscription_lifecycle_events event
          join lifecycle_chain current
            on current.id = event.after_issued_subscription_id
          where event.event_type = 'replace'
            and event.before_issued_subscription_id is not null
        )
        select record.id
        from app.client_payment_records record
        where record.issued_subscription_id in (
            select id from lifecycle_chain
          )
          and record.status in ('unpaid', 'posted_pending')
          and not exists (
            select 1
            from app.commerce_reporting_exclusions exclusion
            where (exclusion.source_kind = 'payment_record'
                and exclusion.source_id = record.id)
               or (record.actual_payment_id is not null
                and exclusion.source_kind = 'payment'
                and exclusion.source_id = record.actual_payment_id)
          )
        order by record.id
        for update of record
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

  async readCancellationContextInTransaction(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<CancellationContext | null> {
    const result = await client.query<CancellationContextDatabaseRow>(
      cancellationContextSql,
      [issuedSubscriptionId],
    );
    return this.mapCancellationContext(result.rows[0]);
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

  async closeCancelledSubscription(
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
        set status = 'cancelled',
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
      payerStudentId: string;
      fundingMode: "personal_account" | "installment" | "legacy";
      purchaseReason: string | null;
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
          version,
          payer_student_id,
          funding_mode,
          purchase_reason
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
          1,
          $11,
          $12,
          $13
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
        input.payerStudentId,
        input.fundingMode,
        input.purchaseReason,
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

  async releaseCancellationReservations(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<{ count: number; units: string; remaining: number }> {
    const result = await client.query<{
      count: string;
      units: string;
    }>(
      `
        with released as (
          update app.lesson_reservations
          set state = 'released',
            version = version + 1,
            updated_at = now()
          where subscription_id = $1
            and state = 'reserved'
          returning units
        )
        select
          count(*)::text as count,
          coalesce(sum(units), 0)::text as units
        from released
      `,
      [issuedSubscriptionId],
    );
    const remaining = await client.query<{ count: string }>(
      `
        select count(*)::text as count
        from app.lesson_reservations
        where subscription_id = $1
          and state = 'reserved'
      `,
      [issuedSubscriptionId],
    );
    return {
      count: Number(result.rows[0]?.count ?? 0),
      units: normalizeNumeric(result.rows[0]?.units ?? "0"),
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

  async createCancellationCredit(
    client: PoolClient,
    input: {
      payerStudentId: string;
      issuedSubscriptionId: string;
      amountMinor: string;
      currencyCode: string;
    },
  ): Promise<CancellationCreditRow | null> {
    if (input.amountMinor === "0") return null;
    const result = await client.query<CancellationCreditRow>(
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
        values ($1, $2::uuid, 'adjustment', 'credit', $3::bigint, $4,
          'subscription.cancel', $2::uuid::text)
        returning id, amount_minor::text
      `,
      [
        input.payerStudentId,
        input.issuedSubscriptionId,
        input.amountMinor,
        input.currencyCode,
      ],
    );
    return result.rows[0]!;
  }

  async closeCancellationPaymentRecords(
    client: PoolClient,
    input: {
      issuedSubscriptionId: string;
      reason: string;
      actorUserId: string;
      auditEventId: string;
    },
  ): Promise<number> {
    const result = await client.query(
      `
        with recursive lifecycle_chain(id) as (
          select $1::uuid
          union
          select event.before_issued_subscription_id
          from app.subscription_lifecycle_events event
          join lifecycle_chain current
            on current.id = event.after_issued_subscription_id
          where event.event_type = 'replace'
            and event.before_issued_subscription_id is not null
        ), open_records as (
          select record.id
          from app.commerce_ordinary_payment_records record
          where record.issued_subscription_id in (
              select id from lifecycle_chain
            )
            and record.status in ('unpaid', 'posted_pending')
          order by record.id
        )
        insert into app.commerce_reporting_exclusions (
          source_kind,
          source_id,
          reason,
          actor_user_id,
          audit_event_id
        )
        select 'payment_record', open_record.id, $2, $3, $4
        from open_records open_record
        returning id
      `,
      [
        input.issuedSubscriptionId,
        input.reason,
        input.actorUserId,
        input.auditEventId,
      ],
    );
    return result.rowCount ?? 0;
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

  async createCancelLifecycle(
    client: PoolClient,
    input: {
      issuedSubscriptionId: string;
      actorUserId: string;
      reason: string;
      aggregateVersion: number;
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
        values ($1, 'cancel', $1, null, $2, $3, $4)
      `,
      [
        input.issuedSubscriptionId,
        input.actorUserId,
        input.reason,
        input.aggregateVersion,
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
      payerStudentId: row.payer_student_id,
      fundingMode: row.funding_mode,
      purchaseReason: row.purchase_reason,
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

  private mapCancellationContext(
    row: CancellationContextDatabaseRow | undefined,
  ): CancellationContext | null {
    if (!row) return null;
    return {
      issuedSubscriptionId: row.issued_id,
      studentId: row.student_id,
      payerStudentId: row.payer_student_id,
      fundingMode: row.funding_mode,
      package: {
        id: row.package_id,
        name: row.package_name,
        version: Number(row.package_version),
        unitCount: normalizeNumeric(row.unit_count),
      },
      status: row.status,
      version: Number(row.version),
      currencyCode: row.currency_code,
      finalMinor: row.final_minor,
      usedUnits: normalizeNumeric(row.used_units),
      actualPaidMinor: row.actual_paid_minor,
      previousRefundMinor: row.previous_refund_minor,
      writeoffMinor: row.writeoff_minor,
      netObligationMinor: row.net_obligation_minor,
      balanceMinor: row.balance_minor,
      paymentRefs: row.payment_refs.map((payment) => ({
        id: payment.id,
        amountMinor: String(payment.amountMinor),
        occurredAt: new Date(payment.occurredAt).toISOString(),
      })),
      previousRefundRefs: row.previous_refund_refs.map((refund) => ({
        id: refund.id,
        amountMinor: String(refund.amountMinor),
        occurredAt: new Date(refund.occurredAt).toISOString(),
      })),
      openPaymentRecordRefs: row.open_payment_record_refs.map((record) => ({
        id: record.id,
        status: record.status,
        version: Number(record.version),
        amountMinor: String(record.amountMinor),
      })),
      writeoffRefs: row.writeoff_refs.map((writeoff) => ({
        id: writeoff.id,
        lessonId: writeoff.lessonId,
        amountMinor: String(writeoff.amountMinor),
        units: normalizeNumeric(String(writeoff.units)),
        occurredAt: new Date(writeoff.occurredAt).toISOString(),
      })),
      obligationRefs: row.obligation_refs.map((obligation) => ({
        id: obligation.id,
        direction: obligation.direction,
        amountMinor: String(obligation.amountMinor),
        occurredAt: new Date(obligation.occurredAt).toISOString(),
      })),
      futureLessonCount: Number(row.future_lesson_count),
      reservedLessonCount: Number(row.reserved_lesson_count),
      reservedUnits: normalizeNumeric(row.reserved_units),
      futureLessons: row.future_lessons.map((lesson) => ({
        lessonId: lesson.lessonId,
        reservationId: lesson.reservationId,
        scheduledAt: new Date(lesson.scheduledAt).toISOString(),
        units: normalizeNumeric(String(lesson.units)),
        reserved: lesson.reserved,
      })),
    };
  }
}

function normalizeNumeric(value: string): string {
  const normalized = value.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "");
  return normalized === "-0" ? "0" : normalized;
}
