import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { IssuedCommercialSnapshot } from "./commerce-schema.types";

export interface IssuePackageRow {
  id: string;
  name: string;
  branch_id: string | null;
  lessons_total: string | number;
  base_price_minor: string;
  currency_code: string;
  validity_days: number | null;
  version: number | string;
}

export interface IssuedSubscriptionRow {
  id: string;
  student_id: string;
  package_id: string;
  lessons_total: string | number;
  lessons_used: string | number;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  status: string;
  version: number | string;
  commercial_snapshot: IssuedCommercialSnapshot;
  created_at: Date | string;
}

export interface InstallmentRow {
  id: string;
  issued_subscription_id: string;
  installment_number: number;
  due_at: Date | string;
  amount_minor: string;
  currency_code: string;
  status: "pending" | "paid" | "void";
  version: number | string;
}

export interface ObligationRow {
  id: string;
  student_id: string;
  issued_subscription_id: string;
  fact_type: "issue" | "installment";
  direction: "debit";
  amount_minor: string;
  currency_code: string;
  source_type: string;
  source_ref: string;
  occurred_at: Date | string;
}

export interface ActualPaymentRow {
  id: string;
  student_id: string;
  issued_subscription_id: string | null;
  amount_minor: string;
  currency: string;
  method: "cash" | "cashless";
  payment_date: Date | string;
  created_at: Date | string;
}

interface IssuedPaymentTargetRow {
  id: string;
  currency_code: string;
}

export interface IssueDiscountColumns {
  type: "none" | "percent" | "fixed";
  percentBasisPoints: number | null;
  fixedMinor: string | null;
  reason: string | null;
}

export interface PlannedInstallment {
  installmentNumber: number;
  dueAt: Date;
  amountMinor: string;
}

@Injectable()
export class SubscriptionIssueRepository {
  constructor(private readonly database: DatabaseService) {}

  async lockStudent(
    client: PoolClient,
    studentId: string,
  ): Promise<boolean> {
    const result = await client.query<{ id: string }>(
      `
        select id
        from app.students
        where id = $1 and deleted_at is null
        for update
      `,
      [studentId],
    );
    return result.rowCount === 1;
  }

  async findActivePackageForShare(
    client: PoolClient,
    packageId: string,
  ): Promise<IssuePackageRow | null> {
    const result = await client.query<IssuePackageRow>(
      `
        select
          id,
          name,
          branch_id,
          lessons_total,
          base_price_minor,
          currency_code,
          validity_days,
          version
        from app.subscription_packages
        where id = $1
          and deleted_at is null
          and is_active = true
        for share
      `,
      [packageId],
    );
    return result.rows[0] ?? null;
  }

  async createIssuedSubscription(
    client: PoolClient,
    input: {
      id: string;
      studentId: string;
      package: IssuePackageRow;
      snapshot: IssuedCommercialSnapshot;
      discount: IssueDiscountColumns;
      finalPriceMinor: string;
      version: number;
    },
  ): Promise<IssuedSubscriptionRow> {
    const result = await client.query<IssuedSubscriptionRow>(
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
          0,
          current_date,
          case
            when $4::integer is null then null
            else current_date + $4::integer
          end,
          'active',
          $5,
          null,
          $6::jsonb,
          1,
          $7,
          $8::bigint,
          $9,
          $10,
          $11,
          $12::text::bigint,
          $13,
          $14::bigint,
          $15
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
          commercial_snapshot,
          created_at
      `,
      [
        input.id,
        input.studentId,
        input.package.lessons_total,
        input.package.validity_days,
        input.package.id,
        JSON.stringify(input.snapshot),
        input.package.version,
        input.package.base_price_minor,
        input.package.currency_code,
        input.discount.type === "none" ? null : input.discount.type,
        input.discount.percentBasisPoints,
        input.discount.fixedMinor,
        input.discount.reason,
        input.finalPriceMinor,
        input.version,
      ],
    );
    return result.rows[0]!;
  }

  async createInstallments(
    client: PoolClient,
    input: {
      issuedSubscriptionId: string;
      currencyCode: string;
      installments: PlannedInstallment[];
    },
  ): Promise<InstallmentRow[]> {
    const rows: InstallmentRow[] = [];
    for (const installment of input.installments) {
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
          returning
            id,
            issued_subscription_id,
            installment_number,
            due_at,
            amount_minor,
            currency_code,
            status,
            version
        `,
        [
          input.issuedSubscriptionId,
          installment.installmentNumber,
          installment.dueAt,
          installment.amountMinor,
          input.currencyCode,
        ],
      );
      rows.push(result.rows[0]!);
    }
    return rows;
  }

  async createObligations(
    client: PoolClient,
    input: {
      studentId: string;
      issuedSubscriptionId: string;
      currencyCode: string;
      finalPriceMinor: string;
      installments: PlannedInstallment[];
    },
  ): Promise<ObligationRow[]> {
    const facts =
      input.installments.length === 0
        ? [
            {
              factType: "issue" as const,
              amountMinor: input.finalPriceMinor,
              sourceType: "subscription.issue",
              sourceRef: input.issuedSubscriptionId,
            },
          ]
        : input.installments.map((installment) => ({
            factType: "installment" as const,
            amountMinor: installment.amountMinor,
            sourceType: "subscription.installment",
            sourceRef:
              `${input.issuedSubscriptionId}:${installment.installmentNumber}`,
          }));
    const rows: ObligationRow[] = [];
    for (const fact of facts) {
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
            source_ref
          )
          values ($1, $2, $3, 'debit', $4::bigint, $5, $6, $7)
          returning
            id,
            student_id,
            issued_subscription_id,
            fact_type,
            direction,
            amount_minor,
            currency_code,
            source_type,
            source_ref,
            occurred_at
        `,
        [
          input.studentId,
          input.issuedSubscriptionId,
          fact.factType,
          fact.amountMinor,
          input.currencyCode,
          fact.sourceType,
          fact.sourceRef,
        ],
      );
      rows.push(result.rows[0]!);
    }
    return rows;
  }

  async createIssueLifecycle(
    client: PoolClient,
    input: {
      issuedSubscriptionId: string;
      actorUserId: string;
      version: number;
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
        values ($1, 'issue', null, $1, $2, 'Первичная выдача', $3)
      `,
      [
        input.issuedSubscriptionId,
        input.actorUserId,
        input.version,
      ],
    );
  }

  async findIssuedSubscription(
    issuedSubscriptionId: string,
  ): Promise<IssuedSubscriptionRow | null> {
    const result = await this.database.query<IssuedSubscriptionRow>(
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
          commercial_snapshot,
          created_at
        from app.subscriptions
        where id = $1 and commercial_snapshot is not null
      `,
      [issuedSubscriptionId],
    );
    return result.rows[0] ?? null;
  }

  async listInstallments(
    issuedSubscriptionId: string,
  ): Promise<InstallmentRow[]> {
    const result = await this.database.query<InstallmentRow>(
      `
        select
          id,
          issued_subscription_id,
          installment_number,
          due_at,
          amount_minor,
          currency_code,
          status,
          version
        from app.subscription_installments
        where issued_subscription_id = $1
        order by installment_number
      `,
      [issuedSubscriptionId],
    );
    return result.rows;
  }

  async listObligations(
    issuedSubscriptionId: string,
  ): Promise<ObligationRow[]> {
    const result = await this.database.query<ObligationRow>(
      `
        select
          id,
          student_id,
          issued_subscription_id,
          fact_type,
          direction,
          amount_minor,
          currency_code,
          source_type,
          source_ref,
          occurred_at
        from app.subscription_obligation_facts
        where issued_subscription_id = $1
          and source_type in (
            'subscription.issue',
            'subscription.installment'
          )
        order by occurred_at, id
      `,
      [issuedSubscriptionId],
    );
    return result.rows;
  }

  async findIssuedPaymentTargetForShare(
    client: PoolClient,
    issuedSubscriptionId: string,
    studentId: string,
  ): Promise<IssuedPaymentTargetRow | null> {
    const result = await client.query<IssuedPaymentTargetRow>(
      `
        select id, currency_code
        from app.subscriptions
        where id = $1
          and student_id = $2
          and commercial_snapshot is not null
        for share
      `,
      [issuedSubscriptionId, studentId],
    );
    return result.rows[0] ?? null;
  }

  async createActualPayment(
    client: PoolClient,
    input: {
      id: string;
      studentId: string;
      issuedSubscriptionId: string | null;
      amountMinor: string;
      currencyCode: string;
      method: "cash" | "cashless";
      occurredAt: Date;
      actorUserId: string;
      idempotencyRef: string;
      requestFingerprint: string;
    },
  ): Promise<ActualPaymentRow> {
    const result = await client.query<ActualPaymentRow>(
      `
        insert into app.payments (
          id,
          student_id,
          amount_minor,
          currency,
          payment_date,
          method,
          notes,
          created_by,
          issued_subscription_id,
          idempotency_ref,
          request_fingerprint
        )
        values (
          $1,
          $2,
          $3::bigint,
          $4,
          $5,
          $6,
          'Оплата абонемента',
          $7,
          $8,
          $9,
          $10
        )
        returning
          id,
          student_id,
          issued_subscription_id,
          amount_minor,
          currency,
          method,
          payment_date,
          created_at
      `,
      [
        input.id,
        input.studentId,
        input.amountMinor,
        input.currencyCode,
        input.occurredAt,
        input.method,
        input.actorUserId,
        input.issuedSubscriptionId,
        input.idempotencyRef,
        input.requestFingerprint,
      ],
    );
    return result.rows[0]!;
  }

  async findActualPayment(paymentId: string): Promise<ActualPaymentRow | null> {
    const result = await this.database.query<ActualPaymentRow>(
      `
        select
          id,
          student_id,
          issued_subscription_id,
          amount_minor,
          currency,
          method,
          payment_date,
          created_at
        from app.payments
        where id = $1
          and amount_minor is not null
          and idempotency_ref is not null
      `,
      [paymentId],
    );
    return result.rows[0] ?? null;
  }
}
