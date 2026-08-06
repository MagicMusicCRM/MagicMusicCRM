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
  branch_id: string | null;
  branch_name: string | null;
  notes: string | null;
  invoice_number: string | null;
  created_by: string | null;
  created_by_name: string | null;
  created_at: Date | string;
}

export interface PaymentAdjustmentRow {
  id: string;
  student_id: string;
  source_payment_id: string;
  kind: "refund" | "adjustment";
  amount_minor: string;
  currency_code: string;
  occurred_at: Date | string;
  description: string;
  branch_id: string | null;
  branch_name: string | null;
  method: string | null;
  invoice_number: string | null;
  created_by: string | null;
  created_by_name: string | null;
  created_at: Date | string;
}

export interface PaymentAdjustmentSourceRow {
  id: string;
  amount_minor: string;
  adjusted_minor: string;
  currency: string;
  method: "cash" | "cashless";
  branch_id: string | null;
  invoice_number: string | null;
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
          surcharge_minor,
          surcharge_reason,
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
          $14::text::bigint,
          $15,
          $16::bigint,
          $17
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
        input.snapshot.surcharge?.type === "fixed"
          ? input.snapshot.surcharge.amountMinor
          : null,
        input.snapshot.surcharge?.type === "fixed"
          ? input.snapshot.surcharge.reason
          : null,
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
      branchId: string | null;
      comment: string | null;
      invoiceIdentifier: string | null;
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
          branch_id,
          invoice_number,
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
          $7,
          $8,
          $9,
          $10,
          $11,
          $12,
          $13
        )
        returning
          id,
          student_id,
          issued_subscription_id,
          amount_minor,
          currency,
          method,
          payment_date,
          branch_id,
          null::text as branch_name,
          notes,
          invoice_number,
          created_by,
          null::text as created_by_name,
          created_at
      `,
      [
        input.id,
        input.studentId,
        input.amountMinor,
        input.currencyCode,
        input.occurredAt,
        input.method,
        input.comment,
        input.branchId,
        input.invoiceIdentifier,
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
          payment.id,
          payment.student_id,
          payment.issued_subscription_id,
          payment.amount_minor,
          payment.currency,
          payment.method,
          payment.payment_date,
          payment.branch_id,
          branch.name as branch_name,
          payment.notes,
          payment.invoice_number,
          payment.created_by,
          nullif(btrim(
            coalesce(author.first_name, '') || ' ' ||
            coalesce(author.last_name, '')
          ), '') as created_by_name,
          payment.created_at
        from app.payments payment
        left join app.branches branch on branch.id = payment.branch_id
        left join app.users creator on creator.id = payment.created_by
        left join app.profiles author on author.user_id = creator.id
        where payment.id = $1
          and payment.amount_minor is not null
          and payment.idempotency_ref is not null
      `,
      [paymentId],
    );
    return result.rows[0] ?? null;
  }

  async findPaymentAdjustmentSourceForShare(
    client: PoolClient,
    paymentId: string,
    studentId: string,
  ): Promise<PaymentAdjustmentSourceRow | null> {
    const result = await client.query<PaymentAdjustmentSourceRow>(
      `
        with source as (
          select id, amount_minor, currency, method, branch_id, invoice_number
          from app.payments
          where id = $1
            and student_id = $2
            and deleted_at is null
          for share
        )
        select
          source.*,
          coalesce((
            select sum(adjustment.amount_minor)
            from app.account_adjustments adjustment
            where adjustment.source_payment_id = source.id
              and adjustment.deleted_at is null
              and adjustment.status = 'paid'
          ), 0)::text as adjusted_minor
        from source
      `,
      [paymentId, studentId],
    );
    return result.rows[0] ?? null;
  }

  async createPaymentAdjustment(
    client: PoolClient,
    input: {
      id: string;
      studentId: string;
      sourcePaymentId: string;
      kind: "refund" | "adjustment";
      amountMinor: string;
      currencyCode: string;
      occurredAt: Date;
      reason: string;
      branchId: string | null;
      method: string | null;
      invoiceNumber: string | null;
      actorUserId: string;
      idempotencyRef: string;
      requestFingerprint: string;
    },
  ): Promise<PaymentAdjustmentRow> {
    const result = await client.query<PaymentAdjustmentRow>(
      `
        insert into app.account_adjustments (
          id, student_id, branch_id, kind, amount_minor, currency_code,
          description, method, occurred_at, created_by, invoice_number,
          source_payment_id, idempotency_ref, request_fingerprint
        ) values (
          $1, $2, $3, $4, $5::bigint, $6, $7, $8, $9, $10, $11, $12, $13, $14
        )
        returning
          id, student_id, source_payment_id, kind, amount_minor,
          currency_code, occurred_at, description, branch_id,
          null::text as branch_name, method, invoice_number, created_by,
          null::text as created_by_name, created_at
      `,
      [
        input.id,
        input.studentId,
        input.branchId,
        input.kind,
        input.amountMinor,
        input.currencyCode,
        input.reason,
        input.method,
        input.occurredAt,
        input.actorUserId,
        input.invoiceNumber,
        input.sourcePaymentId,
        input.idempotencyRef,
        input.requestFingerprint,
      ],
    );
    return result.rows[0]!;
  }

  async findPaymentAdjustment(
    adjustmentId: string,
  ): Promise<PaymentAdjustmentRow | null> {
    const result = await this.database.query<PaymentAdjustmentRow>(
      `
        select
          adjustment.id,
          adjustment.student_id,
          adjustment.source_payment_id,
          adjustment.kind,
          adjustment.amount_minor,
          adjustment.currency_code,
          adjustment.occurred_at,
          adjustment.description,
          adjustment.branch_id,
          branch.name as branch_name,
          adjustment.method,
          adjustment.invoice_number,
          adjustment.created_by,
          nullif(btrim(
            coalesce(author.first_name, '') || ' ' ||
            coalesce(author.last_name, '')
          ), '') as created_by_name,
          adjustment.created_at
        from app.account_adjustments adjustment
        left join app.branches branch on branch.id = adjustment.branch_id
        left join app.users creator on creator.id = adjustment.created_by
        left join app.profiles author on author.user_id = creator.id
        where adjustment.id = $1
          and adjustment.source_payment_id is not null
      `,
      [adjustmentId],
    );
    return result.rows[0] ?? null;
  }
}
