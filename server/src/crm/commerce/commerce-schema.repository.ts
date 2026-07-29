import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import {
  ActualPaymentEntity,
  IssuedCommercialSnapshot,
  IssuedSubscriptionEntity,
  ObligationFactEntity,
  ObligationFactType,
  SubscriptionInstallmentEntity,
  SubscriptionLifecycleEventEntity,
  SubscriptionLifecycleEventType,
  SubscriptionPackageEntity,
} from "./commerce-schema.types";

interface PackageRow {
  id: string;
  name: string;
  lessons_total: string;
  validity_days: number | null;
  base_price_minor: string;
  currency_code: string;
  is_active: boolean;
  version: number | string;
}

interface IssuedRow {
  id: string;
  student_id: string;
  package_id: string;
  status: string;
  version: number | string;
  commercial_snapshot: IssuedCommercialSnapshot;
}

interface InstallmentRow {
  id: string;
  issued_subscription_id: string;
  installment_number: number;
  due_at: Date | string;
  amount_minor: string;
  currency_code: string;
  status: "pending" | "paid" | "void";
  version: number | string;
}

interface PaymentRow {
  id: string;
  student_id: string;
  issued_subscription_id: string | null;
  amount_minor: string;
  currency: string;
  method: "cash" | "cashless";
  payment_date: Date | string;
  idempotency_ref: string;
  request_fingerprint: string;
}

interface ObligationRow {
  id: string;
  student_id: string;
  issued_subscription_id: string | null;
  fact_type: ObligationFactType;
  direction: "debit" | "credit";
  amount_minor: string;
  currency_code: string;
  source_type: string;
  source_ref: string;
  occurred_at: Date | string;
}

interface LifecycleRow {
  id: string;
  issued_subscription_id: string;
  event_type: SubscriptionLifecycleEventType;
  before_issued_subscription_id: string | null;
  after_issued_subscription_id: string | null;
  actor_user_id: string | null;
  reason: string;
  aggregate_version: number | string;
  occurred_at: Date | string;
}

@Injectable()
export class CommerceSchemaRepository {
  async createPackage(
    client: PoolClient,
    input: {
      name: string;
      unitCount: string;
      validityDays?: number | null;
      basePriceMinor: string;
      currencyCode?: string;
      active?: boolean;
    },
  ): Promise<SubscriptionPackageEntity> {
    const result = await client.query<PackageRow>(
      `
        insert into app.subscription_packages (
          name,
          lessons_total,
          validity_days,
          base_price_minor,
          currency_code,
          is_active
        )
        values ($1, $2::numeric, $3, $4::bigint, $5, $6)
        returning
          id,
          name,
          lessons_total,
          validity_days,
          base_price_minor,
          currency_code,
          is_active,
          version
      `,
      [
        input.name,
        input.unitCount,
        input.validityDays ?? null,
        input.basePriceMinor,
        input.currencyCode ?? "RUB",
        input.active ?? true,
      ],
    );
    return this.toPackage(result.rows[0]!);
  }

  async updatePackage(
    client: PoolClient,
    input: {
      id: string;
      expectedVersion: number;
      name?: string;
      basePriceMinor?: string;
      active?: boolean;
    },
  ): Promise<SubscriptionPackageEntity | null> {
    const result = await client.query<PackageRow>(
      `
        update app.subscription_packages
        set name = coalesce($3, name),
            base_price_minor = coalesce($4::text::bigint, base_price_minor),
            is_active = coalesce($5, is_active),
            version = version + 1,
            updated_at = now()
        where id = $1
          and version = $2
          and deleted_at is null
        returning
          id,
          name,
          lessons_total,
          validity_days,
          base_price_minor,
          currency_code,
          is_active,
          version
      `,
      [
        input.id,
        input.expectedVersion,
        input.name ?? null,
        input.basePriceMinor ?? null,
        input.active ?? null,
      ],
    );
    const row = result.rows[0];
    return row ? this.toPackage(row) : null;
  }

  async createIssuedSubscription(
    client: PoolClient,
    input: {
      studentId: string;
      packageId: string;
      startsAt: string;
      expiresAt?: string | null;
      snapshot: IssuedCommercialSnapshot;
    },
  ): Promise<IssuedSubscriptionEntity> {
    const discount = input.snapshot.discount;
    const result = await client.query<IssuedRow>(
      `
        insert into app.subscriptions (
          student_id,
          package_id,
          lessons_total,
          lessons_used,
          starts_at,
          expires_at,
          status,
          commercial_snapshot,
          snapshot_version,
          package_version,
          base_price_minor,
          currency_code,
          discount_type,
          discount_percent_basis_points,
          discount_fixed_minor,
          discount_reason,
          final_price_minor
        )
        values (
          $1,
          $2,
          $3::numeric,
          0,
          $4::date,
          $5::date,
          'active',
          $6::jsonb,
          $7,
          $8,
          $9::bigint,
          $10,
          $11,
          $12,
          $13::text::bigint,
          $14,
          $15::bigint
        )
        returning
          id,
          student_id,
          package_id,
          status,
          version,
          commercial_snapshot
      `,
      [
        input.studentId,
        input.packageId,
        input.snapshot.unitCount,
        input.startsAt,
        input.expiresAt ?? null,
        JSON.stringify(input.snapshot),
        input.snapshot.snapshotVersion,
        input.snapshot.packageVersion,
        input.snapshot.basePriceMinor,
        input.snapshot.currencyCode,
        discount.type === "none" ? null : discount.type,
        discount.type === "percent" ? discount.percentBasisPoints : null,
        discount.type === "fixed" ? discount.fixedMinor : null,
        discount.type === "none" ? null : discount.reason,
        input.snapshot.finalPriceMinor,
      ],
    );
    return this.toIssued(result.rows[0]!);
  }

  async findIssuedSubscription(
    client: PoolClient,
    issuedSubscriptionId: string,
  ): Promise<IssuedSubscriptionEntity | null> {
    const result = await client.query<IssuedRow>(
      `
        select
          id,
          student_id,
          package_id,
          status,
          version,
          commercial_snapshot
        from app.subscriptions
        where id = $1 and commercial_snapshot is not null
      `,
      [issuedSubscriptionId],
    );
    const row = result.rows[0];
    return row ? this.toIssued(row) : null;
  }

  async appendInstallment(
    client: PoolClient,
    input: {
      issuedSubscriptionId: string;
      installmentNumber: number;
      dueAt: Date;
      amountMinor: string;
      currencyCode?: string;
    },
  ): Promise<SubscriptionInstallmentEntity> {
    const result = await client.query<InstallmentRow>(
      `
        insert into app.subscription_installments (
          issued_subscription_id,
          installment_number,
          due_at,
          amount_minor,
          currency_code
        )
        values ($1, $2, $3, $4::bigint, $5)
        returning *
      `,
      [
        input.issuedSubscriptionId,
        input.installmentNumber,
        input.dueAt,
        input.amountMinor,
        input.currencyCode ?? "RUB",
      ],
    );
    const row = result.rows[0]!;
    return {
      id: row.id,
      issuedSubscriptionId: row.issued_subscription_id,
      installmentNumber: row.installment_number,
      dueAt: new Date(row.due_at),
      amountMinor: row.amount_minor,
      currencyCode: row.currency_code,
      status: row.status,
      version: Number(row.version),
    };
  }

  async appendActualPayment(
    client: PoolClient,
    input: {
      studentId: string;
      issuedSubscriptionId?: string | null;
      amountMinor: string;
      currencyCode?: string;
      method: "cash" | "cashless";
      occurredAt: Date;
      idempotencyRef: string;
      requestFingerprint: string;
      createdBy?: string | null;
    },
  ): Promise<ActualPaymentEntity> {
    const result = await client.query<PaymentRow>(
      `
        insert into app.payments (
          student_id,
          amount_minor,
          currency,
          method,
          payment_date,
          issued_subscription_id,
          idempotency_ref,
          request_fingerprint,
          created_by
        )
        values ($1, $2::bigint, $3, $4, $5, $6, $7, $8, $9)
        returning
          id,
          student_id,
          issued_subscription_id,
          amount_minor,
          currency,
          method,
          payment_date,
          idempotency_ref,
          request_fingerprint
      `,
      [
        input.studentId,
        input.amountMinor,
        input.currencyCode ?? "RUB",
        input.method,
        input.occurredAt,
        input.issuedSubscriptionId ?? null,
        input.idempotencyRef,
        input.requestFingerprint,
        input.createdBy ?? null,
      ],
    );
    const row = result.rows[0]!;
    return {
      id: row.id,
      studentId: row.student_id,
      issuedSubscriptionId: row.issued_subscription_id,
      amountMinor: row.amount_minor,
      currencyCode: row.currency,
      method: row.method,
      occurredAt: new Date(row.payment_date),
      idempotencyRef: row.idempotency_ref,
      requestFingerprint: row.request_fingerprint,
    };
  }

  async appendObligationFact(
    client: PoolClient,
    input: {
      studentId: string;
      issuedSubscriptionId?: string | null;
      factType: ObligationFactType;
      direction: "debit" | "credit";
      amountMinor: string;
      currencyCode?: string;
      sourceType: string;
      sourceRef: string;
      occurredAt?: Date;
    },
  ): Promise<ObligationFactEntity> {
    const result = await client.query<ObligationRow>(
      `
        insert into app.subscription_obligation_facts (
          student_id,
          issued_subscription_id,
          fact_type,
          direction,
          amount_minor,
          currency_code,
          source_type,
          source_ref,
          occurred_at
        )
        values ($1, $2, $3, $4, $5::bigint, $6, $7, $8, $9)
        returning *
      `,
      [
        input.studentId,
        input.issuedSubscriptionId ?? null,
        input.factType,
        input.direction,
        input.amountMinor,
        input.currencyCode ?? "RUB",
        input.sourceType,
        input.sourceRef,
        input.occurredAt ?? new Date(),
      ],
    );
    const row = result.rows[0]!;
    return {
      id: row.id,
      studentId: row.student_id,
      issuedSubscriptionId: row.issued_subscription_id,
      factType: row.fact_type,
      direction: row.direction,
      amountMinor: row.amount_minor,
      currencyCode: row.currency_code,
      sourceType: row.source_type,
      sourceRef: row.source_ref,
      occurredAt: new Date(row.occurred_at),
    };
  }

  async appendLifecycleEvent(
    client: PoolClient,
    input: {
      issuedSubscriptionId: string;
      eventType: SubscriptionLifecycleEventType;
      beforeIssuedSubscriptionId?: string | null;
      afterIssuedSubscriptionId?: string | null;
      actorUserId?: string | null;
      reason: string;
      aggregateVersion: number;
    },
  ): Promise<SubscriptionLifecycleEventEntity> {
    const result = await client.query<LifecycleRow>(
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
        values ($1, $2, $3, $4, $5, $6, $7)
        returning *
      `,
      [
        input.issuedSubscriptionId,
        input.eventType,
        input.beforeIssuedSubscriptionId ?? null,
        input.afterIssuedSubscriptionId ?? null,
        input.actorUserId ?? null,
        input.reason,
        input.aggregateVersion,
      ],
    );
    const row = result.rows[0]!;
    return {
      id: row.id,
      issuedSubscriptionId: row.issued_subscription_id,
      eventType: row.event_type,
      beforeIssuedSubscriptionId: row.before_issued_subscription_id,
      afterIssuedSubscriptionId: row.after_issued_subscription_id,
      actorUserId: row.actor_user_id,
      reason: row.reason,
      aggregateVersion: Number(row.aggregate_version),
      occurredAt: new Date(row.occurred_at),
    };
  }

  private toPackage(row: PackageRow): SubscriptionPackageEntity {
    return {
      id: row.id,
      name: row.name,
      unitCount: row.lessons_total,
      validityDays: row.validity_days,
      basePriceMinor: row.base_price_minor,
      currencyCode: row.currency_code,
      active: row.is_active,
      version: Number(row.version),
    };
  }

  private toIssued(row: IssuedRow): IssuedSubscriptionEntity {
    return {
      id: row.id,
      studentId: row.student_id,
      packageId: row.package_id,
      status: row.status,
      version: Number(row.version),
      commercialSnapshot: row.commercial_snapshot,
    };
  }
}
