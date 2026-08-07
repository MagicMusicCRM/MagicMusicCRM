import { ConflictException, Injectable } from "@nestjs/common";
import { createHash } from "node:crypto";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { ClientPaymentStatus } from "./commerce-schema.types";

export interface PaymentRecordRow {
  id: string;
  student_id: string;
  issued_subscription_id: string | null;
  installment_id: string | null;
  amount_minor: string;
  currency_code: string;
  status: ClientPaymentStatus;
  due_at: Date | string | null;
  method: string | null;
  external_identifier: string | null;
  verification_note: string | null;
  actual_payment_id: string | null;
  version: number | string;
  created_by: string | null;
  verified_by: string | null;
  verified_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
  created_by_name?: string | null;
  verified_by_name?: string | null;
  subscription_name?: string | null;
  recipient_student_id?: string | null;
  exclusion_id?: string | null;
}

export interface PaymentStatusEventRow {
  id: string;
  payment_record_id: string;
  before_status: ClientPaymentStatus | null;
  after_status: ClientPaymentStatus;
  reason: string;
  actor_user_id: string | null;
  aggregate_version: number | string;
  actual_payment_id: string | null;
  occurred_at: Date | string;
  actor_name?: string | null;
}

export interface PaymentTargetRow {
  issued_subscription_id: string;
  installment_id: string | null;
  amount_minor: string | null;
  currency_code: string;
  due_at: Date | string | null;
  recipient_student_id: string;
  existing_payment_record_id: string | null;
}

interface DueInstallmentRow {
  installment_id: string;
  issued_subscription_id: string;
  payer_student_id: string;
  amount_minor: string;
  currency_code: string;
  due_at: Date | string;
  recipient_student_id: string;
  attempt_number: number | string;
}

export interface MaterializedDuePayment {
  record: PaymentRecordRow;
  payerStudentId: string;
  issuedSubscriptionId: string;
  recipientStudentId: string;
}

@Injectable()
export class PaymentLifecycleRepository {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityRepository,
  ) {}

  async findRecordTarget(
    studentId: string,
    issuedSubscriptionId?: string,
    installmentId?: string,
  ): Promise<PaymentTargetRow | null> {
    const result = await this.database.query<PaymentTargetRow>(
      `
        select
          subscription.id as issued_subscription_id,
          installment.id as installment_id,
          installment.amount_minor::text,
          subscription.currency_code,
          installment.due_at,
          subscription.student_id as recipient_student_id,
          (
            select record.id
            from app.commerce_ordinary_payment_records record
            where record.installment_id = installment.id
            order by record.created_at desc, record.id desc
            limit 1
          ) as existing_payment_record_id
        from app.subscriptions subscription
        left join app.subscription_installments installment
          on installment.issued_subscription_id = subscription.id
         and installment.id = $3::uuid
        where coalesce(
            subscription.payer_student_id,
            subscription.student_id
          ) = $1
          and subscription.commercial_snapshot is not null
          and (
            ($3::uuid is not null
              and installment.id = $3
              and ($2::uuid is null or subscription.id = $2))
            or ($3::uuid is null and subscription.id = $2)
          )
      `,
      [studentId, issuedSubscriptionId ?? null, installmentId ?? null],
    );
    return result.rows[0] ?? null;
  }

  async lockSubscriptionTarget(
    client: PoolClient,
    studentId: string,
    issuedSubscriptionId: string,
  ): Promise<PaymentTargetRow | null> {
    const result = await client.query<PaymentTargetRow>(
      `
        select
          subscription.id as issued_subscription_id,
          null::uuid as installment_id,
          null::text as amount_minor,
          subscription.currency_code,
          null::timestamptz as due_at,
          subscription.student_id as recipient_student_id,
          null::uuid as existing_payment_record_id
        from app.subscriptions subscription
        where subscription.id = $1
          and coalesce(
            subscription.payer_student_id,
            subscription.student_id
          ) = $2
          and subscription.commercial_snapshot is not null
        for share
      `,
      [issuedSubscriptionId, studentId],
    );
    return result.rows[0] ?? null;
  }

  async lockInstallmentTarget(
    client: PoolClient,
    studentId: string,
    installmentId: string,
    issuedSubscriptionId?: string,
  ): Promise<PaymentTargetRow | null> {
    const result = await client.query<PaymentTargetRow>(
      `
        select
          subscription.id as issued_subscription_id,
          installment.id as installment_id,
          installment.amount_minor::text,
          installment.currency_code,
          installment.due_at,
          subscription.student_id as recipient_student_id,
          (
            select record.id
            from app.commerce_ordinary_payment_records record
            where record.installment_id = installment.id
            order by record.created_at desc, record.id desc
            limit 1
          ) as existing_payment_record_id
        from app.subscription_installments installment
        join app.subscriptions subscription
          on subscription.id = installment.issued_subscription_id
        where installment.id = $1
          and ($2::uuid is null or subscription.id = $2)
          and coalesce(
            subscription.payer_student_id,
            subscription.student_id
          ) = $3
          and installment.status <> 'void'
        for update of installment
      `,
      [installmentId, issuedSubscriptionId ?? null, studentId],
    );
    return result.rows[0] ?? null;
  }

  async createRecord(
    client: PoolClient,
    input: {
      id: string;
      studentId: string;
      issuedSubscriptionId: string | null;
      installmentId: string | null;
      amountMinor: string;
      currencyCode: string;
      status: ClientPaymentStatus;
      dueAt: Date | null;
      method: string | null;
      externalIdentifier: string | null;
      verificationNote: string | null;
      actualPaymentId: string | null;
      version: number;
      createdBy: string | null;
      verifiedBy: string | null;
      verifiedAt: Date | null;
    },
  ): Promise<PaymentRecordRow> {
    try {
      const result = await client.query<PaymentRecordRow>(
        `
          insert into app.client_payment_records (
            id, student_id, issued_subscription_id, installment_id,
            amount_minor, currency_code, status, due_at, method,
            external_identifier, verification_note, actual_payment_id,
            version, created_by, verified_by, verified_at
          ) values (
            $1, $2, $3, $4, $5::bigint, $6, $7, $8, $9,
            $10, $11, $12, $13, $14, $15, $16
          )
          returning *
        `,
        [
          input.id,
          input.studentId,
          input.issuedSubscriptionId,
          input.installmentId,
          input.amountMinor,
          input.currencyCode,
          input.status,
          input.dueAt,
          input.method,
          input.externalIdentifier,
          input.verificationNote,
          input.actualPaymentId,
          input.version,
          input.createdBy,
          input.verifiedBy,
          input.verifiedAt,
        ],
      );
      return result.rows[0]!;
    } catch (error) {
      if (
        typeof error === "object" &&
        error !== null &&
        "code" in error &&
        error.code === "23505" &&
        input.installmentId
      ) {
        throw new ConflictException({
          code: "INSTALLMENT_PAYMENT_RECORD_EXISTS",
          message: "Для этой части рассрочки оплата уже зафиксирована.",
        });
      }
      throw error;
    }
  }

  async lockRecord(
    client: PoolClient,
    studentId: string,
    paymentRecordId: string,
  ): Promise<PaymentRecordRow | null> {
    const result = await client.query<PaymentRecordRow>(
      `
        select record.*, exclusion.id as exclusion_id
        from app.client_payment_records record
        left join app.commerce_reporting_exclusions exclusion
          on (exclusion.source_kind = 'payment_record'
            and exclusion.source_id = record.id)
          or (record.actual_payment_id is not null
            and exclusion.source_kind = 'payment'
            and exclusion.source_id = record.actual_payment_id)
        where record.id = $1 and record.student_id = $2
        for update of record
      `,
      [paymentRecordId, studentId],
    );
    return result.rows[0] ?? null;
  }

  async transitionRecord(
    client: PoolClient,
    input: {
      id: string;
      expectedVersion: number;
      nextVersion: number;
      targetStatus: ClientPaymentStatus;
      method: string | null;
      externalIdentifier: string | null;
      verificationNote: string | null;
      actualPaymentId: string | null;
      verifiedBy: string | null;
      verifiedAt: Date | null;
    },
  ): Promise<PaymentRecordRow | null> {
    const result = await client.query<PaymentRecordRow>(
      `
        update app.client_payment_records
        set status = $4,
            method = coalesce($5, method),
            external_identifier = coalesce($6, external_identifier),
            verification_note = coalesce($7, verification_note),
            actual_payment_id = $8,
            verified_by = $9,
            verified_at = $10,
            version = $3,
            updated_at = now()
        where id = $1 and version = $2
        returning *
      `,
      [
        input.id,
        input.expectedVersion,
        input.nextVersion,
        input.targetStatus,
        input.method,
        input.externalIdentifier,
        input.verificationNote,
        input.actualPaymentId,
        input.verifiedBy,
        input.verifiedAt,
      ],
    );
    return result.rows[0] ?? null;
  }

  async linkActualPayment(
    client: PoolClient,
    actualPaymentId: string,
    paymentRecordId: string,
  ): Promise<void> {
    const result = await client.query(
      `
        update app.payments
        set payment_record_id = $2
        where id = $1 and payment_record_id is null
      `,
      [actualPaymentId, paymentRecordId],
    );
    if (result.rowCount !== 1) {
      throw new Error("Actual payment record link was not created.");
    }
  }

  async appendStatusEvent(
    client: PoolClient,
    input: {
      paymentRecordId: string;
      beforeStatus: ClientPaymentStatus | null;
      afterStatus: ClientPaymentStatus;
      reason: string;
      actorUserId: string | null;
      aggregateVersion: number;
      actualPaymentId: string | null;
      occurredAt?: Date;
    },
  ): Promise<PaymentStatusEventRow> {
    const result = await client.query<PaymentStatusEventRow>(
      `
        insert into app.client_payment_status_events (
          payment_record_id, before_status, after_status, reason,
          actor_user_id, aggregate_version, actual_payment_id, occurred_at
        ) values ($1, $2, $3, $4, $5, $6, $7, coalesce($8, now()))
        returning *
      `,
      [
        input.paymentRecordId,
        input.beforeStatus,
        input.afterStatus,
        input.reason,
        input.actorUserId,
        input.aggregateVersion,
        input.actualPaymentId,
        input.occurredAt ?? null,
      ],
    );
    return result.rows[0]!;
  }

  async findRecord(paymentRecordId: string): Promise<PaymentRecordRow | null> {
    const result = await this.database.query<PaymentRecordRow>(
      `
        select
          record.*,
          nullif(btrim(
            coalesce(creator_profile.first_name, '') || ' ' ||
            coalesce(creator_profile.last_name, '')
          ), '') as created_by_name,
          nullif(btrim(
            coalesce(verifier_profile.first_name, '') || ' ' ||
            coalesce(verifier_profile.last_name, '')
          ), '') as verified_by_name,
          subscription.commercial_snapshot ->> 'displayName'
            as subscription_name,
          subscription.student_id as recipient_student_id,
          exclusion.id as exclusion_id
        from app.client_payment_records record
        left join app.users creator on creator.id = record.created_by
        left join app.profiles creator_profile
          on creator_profile.user_id = creator.id
        left join app.users verifier on verifier.id = record.verified_by
        left join app.profiles verifier_profile
          on verifier_profile.user_id = verifier.id
        left join app.subscriptions subscription
          on subscription.id = record.issued_subscription_id
        left join app.commerce_reporting_exclusions exclusion
          on (exclusion.source_kind = 'payment_record'
            and exclusion.source_id = record.id)
          or (record.actual_payment_id is not null
            and exclusion.source_kind = 'payment'
            and exclusion.source_id = record.actual_payment_id)
        where record.id = $1
      `,
      [paymentRecordId],
    );
    return result.rows[0] ?? null;
  }

  async listStatusEvents(
    paymentRecordId: string,
  ): Promise<PaymentStatusEventRow[]> {
    const result = await this.database.query<PaymentStatusEventRow>(
      `
        select
          event.*,
          nullif(btrim(
            coalesce(profile.first_name, '') || ' ' ||
            coalesce(profile.last_name, '')
          ), '') as actor_name
        from app.client_payment_status_events event
        left join app.users actor on actor.id = event.actor_user_id
        left join app.profiles profile on profile.user_id = actor.id
        where event.payment_record_id = $1
        order by event.aggregate_version, event.occurred_at, event.id
      `,
      [paymentRecordId],
    );
    return result.rows;
  }

  materializeDueInstallments(
    now: Date,
    limit: number,
  ): Promise<MaterializedDuePayment[]> {
    return this.database.transaction(async (client) => {
      const candidates = await client.query<DueInstallmentRow>(
        `
          select
            installment.id as installment_id,
            subscription.id as issued_subscription_id,
            coalesce(
              subscription.payer_student_id,
              subscription.student_id
            ) as payer_student_id,
            installment.amount_minor::text,
            installment.currency_code,
            installment.due_at,
            subscription.student_id as recipient_student_id,
            (
              select count(*) + 1
              from app.client_payment_records history
              where history.installment_id = installment.id
            ) as attempt_number
          from app.subscription_installments installment
          join app.subscriptions subscription
            on subscription.id = installment.issued_subscription_id
          where installment.status = 'pending'
            and installment.due_at <= $1
            and subscription.status = 'active'
            and not exists (
              select 1
              from app.commerce_ordinary_payment_records record
              where record.installment_id = installment.id
            )
            and (
              coalesce((
                select sum(payment.amount_minor)
                from app.commerce_ordinary_payments payment
                where payment.issued_subscription_id = subscription.id
                  and payment.deleted_at is null
              ), 0)
              + coalesce((
                select sum(adjustment.amount_minor)
                from app.commerce_ordinary_account_adjustments adjustment
                join app.commerce_ordinary_payments source
                  on source.id = adjustment.source_payment_id
                where source.issued_subscription_id = subscription.id
                  and adjustment.deleted_at is null
                  and adjustment.status = 'paid'
              ), 0)
            ) < (
              select sum(previous.amount_minor)
              from app.subscription_installments previous
              where previous.issued_subscription_id = subscription.id
                and previous.status <> 'void'
                and previous.installment_number <= installment.installment_number
            )
          order by installment.due_at, installment.id
          for update of installment skip locked
          limit $2
        `,
        [now, Math.max(1, Math.min(100, Math.floor(limit)))],
      );
      const materialized: MaterializedDuePayment[] = [];
      for (const candidate of candidates.rows) {
        const id = deterministicDueId(
          candidate.installment_id,
          Number(candidate.attempt_number),
        );
        const inserted = await client.query<PaymentRecordRow>(
          `
            insert into app.client_payment_records (
              id, student_id, issued_subscription_id, installment_id,
              amount_minor, currency_code, status, due_at,
              verification_note, version
            ) values (
              $1, $2, $3, $4, $5::bigint, $6,
              'posted_pending', $7, 'Проверить оплату за рассрочку', 1
            )
            on conflict (id) do nothing
            returning *
          `,
          [
            id,
            candidate.payer_student_id,
            candidate.issued_subscription_id,
            candidate.installment_id,
            candidate.amount_minor,
            candidate.currency_code,
            candidate.due_at,
          ],
        );
        const record = inserted.rows[0];
        if (!record) continue;
        const version = await this.integrity.advanceVersion(
          client,
          "commerce:client-payment",
          record.id,
          0,
        );
        await this.appendStatusEvent(client, {
          paymentRecordId: record.id,
          beforeStatus: null,
          afterStatus: "posted_pending",
          reason: "Проверить оплату за рассрочку",
          actorUserId: null,
          aggregateVersion: version,
          actualPaymentId: null,
          occurredAt: now,
        });
        const requestId = `installment-due:${candidate.installment_id}`;
        await this.integrity.appendAudit(client, {
          action: "crm.installment_payment_due",
          entityType: "client_payment_record",
          entityId: record.id,
          reason: "installment_due",
          requestId,
          afterRef: {
            paymentRecordId: record.id,
            version,
            status: "posted_pending",
            installmentId: candidate.installment_id,
          },
        });
        await this.integrity.enqueueOutbox(client, {
          type: "commerce.payment-record.changed",
          aggregateType: "commerce:client-payment",
          aggregateId: record.id,
          aggregateVersion: version,
          requestId,
          payload: {
            entityId: record.id,
            status: "posted_pending",
            invalidates: ["student-finance"],
          },
        });
        materialized.push({
          record,
          payerStudentId: candidate.payer_student_id,
          issuedSubscriptionId: candidate.issued_subscription_id,
          recipientStudentId: candidate.recipient_student_id,
        });
      }
      return materialized;
    });
  }
}

function deterministicDueId(installmentId: string, attemptNumber = 1): string {
  const hex = createHash("sha256")
    .update(
      attemptNumber === 1
        ? `magicmusiccrm\0installment-due\0${installmentId}`
        : `magicmusiccrm\0installment-due\0${installmentId}\0${attemptNumber}`,
    )
    .digest("hex")
    .slice(0, 32)
    .split("");
  hex[12] = "4";
  hex[16] = ["8", "9", "a", "b"][parseInt(hex[16]!, 16) % 4]!;
  const value = hex.join("");
  return [
    value.slice(0, 8),
    value.slice(8, 12),
    value.slice(12, 16),
    value.slice(16, 20),
    value.slice(20),
  ].join("-");
}
