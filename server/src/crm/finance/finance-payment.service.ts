import {
  decodeFinanceCursor,
  encodeFinanceCursor,
} from "./finance-list-cursor";
import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PaymentLifecycleService } from "../commerce/payment-lifecycle.service";
import {
  VersionedMutationMetadata,
  assertVersionedMutationMetadata,
} from "../../platform/versioned-mutation-metadata";
import { ActorContext } from "../../common/security/actor-context";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { DatabaseService } from "../../db/database.service";
import { PaymentRow, toPaymentDto } from "../crm-mappers";
import { CrmPolicy } from "../crm.policy";
import { CreatePaymentDto } from "../dto/create-payment.dto";
import { PaymentQuery } from "../dto/payment.query";

@Injectable()
export class FinancePaymentService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly lifecycle: PaymentLifecycleService,
  ) {}

  async listRecentPaymentsForStudents(studentIds: string[]) {
    if (!studentIds.length) return [];
    const result = await this.database.query<PaymentRow>(
      `
        select pay.id, pay.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name,
          pay.amount, pay.currency, pay.payment_date, pay.method,
          pay.external_id, pay.notes, pay.created_by, pay.created_at,
          pay.lesson_id
        from app.commerce_ordinary_payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and pay.student_id = any($1::uuid[])
        order by pay.payment_date desc, pay.id desc
        limit 20
      `,
      [studentIds],
    );
    return (result?.rows ?? []).map((row) => toPaymentDto(row));
  }

  async listPayments(actor: ActorContext, query: PaymentQuery) {
    this.policy.assertCanReadSchoolFinance(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const cursor = decodeFinanceCursor(query.cursor);
    const result = await this.database.query<
      PaymentRow & { cursor_at: string }
    >(
      `
        select pay.id, pay.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name, pay.amount,
          pay.currency, pay.payment_date, pay.method, pay.external_id,
          pay.notes, pay.created_by, pay.created_at, pay.lesson_id,
          to_char(pay.payment_date at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as cursor_at
        from app.commerce_ordinary_payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and ($3::uuid is null or pay.student_id = $3)
          and ($4::timestamptz is null or pay.payment_date >= $4)
          and ($5::timestamptz is null or pay.payment_date < $5)
          and ($6::uuid is null or pay.branch_id = $6)
          and (
            ${managerAdminRolesSql("$1")}
            or ($1::text = 'client' and p.user_id = $2)
            or (
              $1::text = 'client'
              and exists (
                select 1
                from app.user_crm_links link
                where link.entity_type = 'student'
                  and link.entity_id = s.id
                  and link.user_id = $2
                  and link.deleted_at is null
              )
            )
          )
          and ($8::timestamptz is null or (pay.payment_date,pay.id) < ($8::timestamptz,$9::uuid))
        order by pay.payment_date desc, pay.id desc
        limit $7
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.from ?? null,
        query.to ?? null,
        query.branchId ?? null,
        limit + 1,
        cursor?.at ?? null,
        cursor?.id ?? null,
      ],
    );
    // Period totals over the FULL filtered set (not just the page), so the UI
    // can show a correct "Итого" instead of summing a truncated page.
    const totals = await this.database.query<{
      total_amount: string;
      total_count: string;
    }>(
      `
        select coalesce(sum(pay.amount), 0)::text as total_amount,
          count(*)::text as total_count
        from app.commerce_ordinary_payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and ($3::uuid is null or pay.student_id = $3)
          and ($4::timestamptz is null or pay.payment_date >= $4)
          and ($5::timestamptz is null or pay.payment_date < $5)
          and ($6::uuid is null or pay.branch_id = $6)
          and (
            ${managerAdminRolesSql("$1")}
            or ($1::text = 'client' and p.user_id = $2)
            or (
              $1::text = 'client'
              and exists (
                select 1
                from app.user_crm_links link
                where link.entity_type = 'student'
                  and link.entity_id = s.id
                  and link.user_id = $2
                  and link.deleted_at is null
              )
            )
          )
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.from ?? null,
        query.to ?? null,
        query.branchId ?? null,
      ],
    );
    return {
      items: result.rows.slice(0, limit).map((row) => toPaymentDto(row)),
      nextCursor:
        result.rows.length > limit
          ? encodeFinanceCursor(result.rows[limit - 1])
          : null,
      totalAmount: Number(totals.rows[0]?.total_amount ?? "0"),
      totalCount: Number(totals.rows[0]?.total_count ?? "0"),
    };
  }

  async createPayment(
    actor: ActorContext,
    dto: CreatePaymentDto,
    metadata?: VersionedMutationMetadata,
  ) {
    this.policy.assertManagerOnly(actor);
    const command = metadata ?? { idempotencyKey: "", requestId: "" };
    assertVersionedMutationMetadata(command);
    const minor = Math.round(dto.amount * 100);
    if (
      !Number.isSafeInteger(minor) ||
      minor <= 0 ||
      Math.abs(dto.amount * 100 - minor) > 0.0001
    )
      throw new BadRequestException(
        "Укажите положительную сумму с точностью до копейки.",
      );
    const method = dto.method?.trim().toLowerCase();
    const normalizedMethod =
      method === "cash" || method === "наличные"
        ? "cash"
        : method === "cashless" || method === "безналичные"
          ? "cashless"
          : undefined;
    const canonical = await this.lifecycle.create(
      actor,
      dto.studentId,
      {
        amountMinor: String(minor),
        currencyCode: dto.currency ?? "RUB",
        status: "paid",
        method: normalizedMethod,
        externalIdentifier: dto.externalId,
        occurredAt: dto.paymentDate,
        verificationNote: dto.notes,
        reason: dto.notes?.trim() || "Добавление оплаты",
        lessonId: dto.lessonId,
      },
      command,
    );
    const id = canonical.actualPayment?.id;
    if (!id) throw new NotFoundException("Проведённая оплата не найдена.");
    const result = await this.database.query<PaymentRow>(
      `select payment.*,coalesce(payment.external_id,payment.invoice_number) as external_id,
      null::text as student_first_name,null::text as student_last_name
      from app.payments payment where payment.id=$1`,
      [id],
    );
    if (!result.rows[0])
      throw new NotFoundException("Проведённая оплата не найдена.");
    return toPaymentDto(result.rows[0]);
  }
}
