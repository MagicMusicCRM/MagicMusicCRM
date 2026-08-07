import { Injectable, NotFoundException } from "@nestjs/common";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { branchIdExpr } from "../branch-scope";
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
  payer_student_id: string | null;
  funding_mode: "personal_account" | "installment" | "legacy" | null;
  purchase_reason: string | null;
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

export interface PurchaseStudentRow {
  id: string;
  version: number | string;
  branch_id: string | null;
}

export interface PurchaseContext {
  students: PurchaseStudentRow[];
  package: IssuePackageRow | null;
  payerBalanceMinor: string;
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

  async readPurchasePreviewContext(
    actor: ActorContext,
    recipientStudentId: string,
    payerStudentId: string,
    packageId: string,
  ): Promise<PurchaseContext> {
    return this.database.transaction(async (client) => {
      const students = await this.lockPurchaseStudents(client, actor, [
        recipientStudentId,
        payerStudentId,
      ]);
      const packageRow = await this.findActivePackageForShare(
        client,
        packageId,
      );
      return {
        students,
        package: packageRow,
        payerBalanceMinor: packageRow
          ? await this.readAccountBalance(
              client,
              payerStudentId,
              packageRow.currency_code,
            )
          : "0",
      };
    });
  }

  async lockPurchaseStudents(
    client: PoolClient,
    actor: ActorContext,
    studentIds: readonly string[],
  ): Promise<PurchaseStudentRow[]> {
    const ids = [...new Set(studentIds)].sort();
    const unrestricted =
      actor.role === "director" || actor.role === "system_admin";
    const result = await client.query<PurchaseStudentRow>(
      `
        select
          student.id,
          student.version,
          ${branchIdExpr("student")} as branch_id
        from app.students student
        where student.id = any($1::uuid[])
          and student.deleted_at is null
          ${
            unrestricted
              ? ""
              : `and ${branchIdExpr("student")} is not null
                 and exists (
                   select 1
                   from app.staff_members staff
                   join app.profiles staff_profile
                     on staff_profile.id = staff.profile_id
                    and staff_profile.deleted_at is null
                   join app.staff_branch_assignments assignment
                     on assignment.staff_member_id = staff.id
                    and assignment.deleted_at is null
                   where staff.deleted_at is null
                     and staff_profile.user_id = $2
                     and assignment.branch_id::text =
                       ${branchIdExpr("student")}
                 )`
          }
        order by student.id
        for update of student
      `,
      unrestricted ? [ids] : [ids, actor.userId],
    );
    return result.rows;
  }

  async assertStudentsInScope(
    actor: ActorContext,
    studentIds: readonly string[],
  ): Promise<void> {
    const expected = new Set(studentIds).size;
    const actual = await this.database.transaction((client) =>
      this.lockPurchaseStudents(client, actor, studentIds),
    );
    if (actual.length !== expected) {
      throw new NotFoundException("Клиент не найден.");
    }
  }

  async readAccountBalance(
    client: PoolClient,
    studentId: string,
    currencyCode: string,
  ): Promise<string> {
    const result = await client.query<{ balance_minor: string }>(
      `
        with facts(amount_minor) as (
          select payment.amount_minor::numeric
          from app.commerce_ordinary_payments payment
          where payment.student_id = $1
            and payment.currency = $2
            and payment.deleted_at is null
            and payment.amount_minor is not null
          union all
          select case
            when obligation.direction = 'credit'
              then obligation.amount_minor::numeric
            else -obligation.amount_minor::numeric
          end
          from app.subscription_obligation_facts obligation
          where obligation.student_id = $1
            and obligation.currency_code = $2
          union all
          select -charge.amount_minor::numeric
          from app.lesson_client_charge_facts_effective charge
          where charge.client_type = 'student'
            and charge.client_id = $1
            and charge.currency_code = $2
          union all
          select adjustment.amount_minor::numeric
          from app.commerce_ordinary_account_adjustments adjustment
          where adjustment.student_id = $1
            and adjustment.currency_code = $2
            and adjustment.deleted_at is null
            and adjustment.status = 'paid'
        )
        select coalesce(sum(amount_minor), 0)::text as balance_minor
        from facts
      `,
      [studentId, currencyCode],
    );
    return result.rows[0]!.balance_minor;
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
      payerStudentId: string;
      fundingMode: "personal_account" | "installment" | "legacy";
      purchaseReason: string | null;
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
          version,
          payer_student_id,
          funding_mode,
          purchase_reason
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
          $17,
          $18,
          $19,
          $20
        )
        returning
          id,
          student_id,
          payer_student_id,
          funding_mode,
          purchase_reason,
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
        input.payerStudentId,
        input.fundingMode,
        input.purchaseReason,
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
      singlePurchaseDebit?: boolean;
    },
  ): Promise<ObligationRow[]> {
    const facts =
      input.singlePurchaseDebit || input.installments.length === 0
        ? [
            {
              factType: "issue" as const,
              amountMinor: input.finalPriceMinor,
              sourceType: input.singlePurchaseDebit
                ? "subscription.purchase"
                : "subscription.issue",
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
      reason?: string;
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
        values ($1, 'issue', null, $1, $2, $4, $3)
      `,
      [
        input.issuedSubscriptionId,
        input.actorUserId,
        input.version,
        input.reason ?? "Первичная выдача",
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
          payer_student_id,
          funding_mode,
          purchase_reason,
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
            'subscription.purchase',
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
            and not exists (
              select 1
              from app.commerce_reporting_exclusions exclusion
              where exclusion.source_kind = 'payment'
                and exclusion.source_id = app.payments.id
            )
          for share
        )
        select
          source.*,
          coalesce((
            select sum(adjustment.amount_minor)
            from app.commerce_ordinary_account_adjustments adjustment
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
