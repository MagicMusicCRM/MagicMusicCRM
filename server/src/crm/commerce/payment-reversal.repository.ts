import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { ClientPaymentStatus } from "./commerce-schema.types";

export interface PaymentReversalTargetRow {
  payment_record_id: string;
  payer_student_id: string;
  recipient_student_id: string;
  issued_subscription_id: string | null;
  installment_id: string | null;
  amount_minor: string;
  currency_code: string;
  status: ClientPaymentStatus;
  record_version: number | string;
  actual_payment_id: string | null;
  payment_student_id: string | null;
  payment_amount_minor: string | null;
  payment_currency_code: string | null;
  payment_method: string | null;
  payment_date: Date | string | null;
  payment_branch_id: string | null;
  payment_invoice_number: string | null;
  linked_adjustment_count: number | string;
  exclusion_id: string | null;
}

export interface PaymentReversalResultRow {
  exclusion_id: string;
  payment_record_id: string;
  payer_student_id: string;
  status: ClientPaymentStatus;
  source_kind: "payment" | "payment_record";
  source_id: string;
  counterpart_kind: "account_adjustment" | null;
  counterpart_id: string | null;
  amount_minor: string;
  currency_code: string;
  reason: string;
  actor_user_id: string;
  actor_name: string | null;
  audit_event_id: string | null;
  occurred_at: Date | string;
}

@Injectable()
export class PaymentReversalRepository {
  constructor(private readonly database: DatabaseService) {}

  async findTarget(recordId: string): Promise<PaymentReversalTargetRow | null> {
    const result = await this.database.query<PaymentReversalTargetRow>(
      targetSql,
      [recordId],
    );
    return result.rows[0] ?? null;
  }

  async lockTarget(
    client: PoolClient,
    recordId: string,
  ): Promise<PaymentReversalTargetRow | null> {
    const record = await client.query<PaymentReversalTargetRow>(
      `${targetSql} for update of record`,
      [recordId],
    );
    const target = record.rows[0] ?? null;
    if (target?.actual_payment_id) {
      await client.query("select id from app.payments where id = $1 for update", [
        target.actual_payment_id,
      ]);
    }
    return target;
  }

  async createExclusion(
    client: PoolClient,
    input: {
      sourceKind: "payment" | "payment_record";
      sourceId: string;
      counterpartId: string | null;
      reason: string;
      actorUserId: string;
      auditEventId: string;
    },
  ): Promise<string> {
    const result = await client.query<{ id: string }>(
      `
        insert into app.commerce_reporting_exclusions (
          source_kind, source_id, counterpart_kind, counterpart_id,
          reason, actor_user_id, audit_event_id
        ) values (
          $1, $2,
          case when $3::uuid is null then null else 'account_adjustment' end,
          $3, $4, $5, $6
        )
        returning id
      `,
      [
        input.sourceKind,
        input.sourceId,
        input.counterpartId,
        input.reason,
        input.actorUserId,
        input.auditEventId,
      ],
    );
    return result.rows[0]!.id;
  }

  async findResult(
    paymentRecordId: string,
  ): Promise<PaymentReversalResultRow | null> {
    const result = await this.database.query<PaymentReversalResultRow>(
      `
        select
          exclusion.id as exclusion_id,
          record.id as payment_record_id,
          record.student_id as payer_student_id,
          record.status,
          exclusion.source_kind,
          exclusion.source_id,
          exclusion.counterpart_kind,
          exclusion.counterpart_id,
          record.amount_minor::text,
          record.currency_code,
          exclusion.reason,
          exclusion.actor_user_id,
          nullif(btrim(
            coalesce(profile.first_name, '') || ' ' ||
            coalesce(profile.last_name, '')
          ), '') as actor_name,
          exclusion.audit_event_id,
          exclusion.occurred_at
        from app.client_payment_records record
        join app.commerce_reporting_exclusions exclusion
          on (exclusion.source_kind = 'payment_record'
            and exclusion.source_id = record.id)
          or (record.actual_payment_id is not null
            and exclusion.source_kind = 'payment'
            and exclusion.source_id = record.actual_payment_id)
        left join app.users actor on actor.id = exclusion.actor_user_id
        left join app.profiles profile on profile.user_id = actor.id
          and profile.deleted_at is null
        where record.id = $1
      `,
      [paymentRecordId],
    );
    return result.rows[0] ?? null;
  }
}

const targetSql = `
  select
    record.id as payment_record_id,
    record.student_id as payer_student_id,
    coalesce(subscription.student_id, record.student_id) as recipient_student_id,
    record.issued_subscription_id,
    record.installment_id,
    record.amount_minor::text,
    record.currency_code,
    record.status,
    record.version as record_version,
    record.actual_payment_id,
    payment.student_id as payment_student_id,
    payment.amount_minor::text as payment_amount_minor,
    payment.currency as payment_currency_code,
    payment.method as payment_method,
    payment.payment_date,
    payment.branch_id as payment_branch_id,
    payment.invoice_number as payment_invoice_number,
    (
      select count(*)
      from app.commerce_ordinary_account_adjustments adjustment
      where adjustment.source_payment_id = payment.id
        and adjustment.deleted_at is null
        and adjustment.status = 'paid'
    ) as linked_adjustment_count,
    exclusion.id as exclusion_id
  from app.client_payment_records record
  left join app.subscriptions subscription
    on subscription.id = record.issued_subscription_id
  left join app.payments payment on payment.id = record.actual_payment_id
  left join app.commerce_reporting_exclusions exclusion
    on (exclusion.source_kind = 'payment_record'
      and exclusion.source_id = record.id)
    or (record.actual_payment_id is not null
      and exclusion.source_kind = 'payment'
      and exclusion.source_id = record.actual_payment_id)
  where record.id = $1
`;
