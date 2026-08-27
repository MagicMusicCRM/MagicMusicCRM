import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { clientFinanceAudienceForStudent } from "../audience";
import { PaymentRow, toPaymentDto } from "../crm-mappers";
import { CrmPolicy } from "../crm.policy";
import { CreatePaymentDto } from "../dto/create-payment.dto";
import { PaymentQuery } from "../dto/payment.query";

@Injectable()
export class FinancePaymentService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
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
    const result = await this.database.query<PaymentRow>(
      `
        select pay.id, pay.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name, pay.amount,
          pay.currency, pay.payment_date, pay.method, pay.external_id,
          pay.notes, pay.created_by, pay.created_at, pay.lesson_id
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
        limit,
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
      items: result.rows.map((row) => toPaymentDto(row)),
      totalAmount: Number(totals.rows[0]?.total_amount ?? "0"),
      totalCount: Number(totals.rows[0]?.total_count ?? "0"),
    };
  }

  async createPayment(actor: ActorContext, dto: CreatePaymentDto) {
    this.policy.assertManagerOnly(actor);
    // Idempotency guard (KVA): an identical payment by the same actor within a
    // short window (double-click / network retry) returns the existing row
    // instead of creating a duplicate that would corrupt the balance/reports.
    // Check + insert run in ONE transaction serialized by a per-(student,
    // actor) advisory lock — a bare check-then-insert let two concurrent
    // double-submits both pass the check and both insert.
    const { payment, existing } = await this.database.transaction(
      async (client) => {
        await client.query(
          `select pg_advisory_xact_lock(hashtext('payment:' || $1 || ':' || $2))`,
          [dto.studentId, actor.userId],
        );
        // Занятие обязано быть этого ученика. Молча обнулить чужую ссылку было
        // бы хуже отказа: платёж записался бы «не разнесённым», а тот, кто его
        // привязывал, ушёл бы уверенный, что привязал.
        if (dto.lessonId) {
          const lesson = await client.query<{ id: string }>(
            `select id from app.lessons
             where id = $1 and student_id = $2 and deleted_at is null`,
            [dto.lessonId, dto.studentId],
          );
          if (!lesson.rows[0]) {
            throw new NotFoundException(
              "Занятие не найдено у этого ученика — платёж к нему не привязать.",
            );
          }
        }
        const dup = await client.query<PaymentRow>(
          `
        select id, student_id, null::uuid as student_user_id, amount,
          null::text as student_first_name, null::text as student_last_name,
          currency, payment_date, method, external_id, notes, created_by, created_at,
          lesson_id
        from app.commerce_ordinary_payments
        where student_id = $1 and amount = $2 and created_by = $3
          and coalesce(method, '') = coalesce($4, '')
          and payment_date = $5 and deleted_at is null
          and created_at > now() - interval '15 seconds'
        order by created_at desc
        limit 1
      `,
          [
            dto.studentId,
            dto.amount,
            actor.userId,
            dto.method?.trim() || null,
            dto.paymentDate,
          ],
        );
        if (dup.rows[0]) return { payment: dup.rows[0], existing: true };

        const result = await client.query<PaymentRow>(
          `
        insert into app.payments (
          student_id, amount, currency, payment_date, method,
          external_id, notes, created_by, lesson_id
        )
        -- ✔ Владелец 17.07: платёж можно привязать к занятию. Что занятие
        -- принадлежит этому ученику, проверено выше — здесь ссылка уже
        -- доверенная.
        values ($1, $2, coalesce($3, 'RUB'), $4, $5, $6, $7, $8, $9::uuid)
        returning id, student_id, null::uuid as student_user_id, amount,
          null::text as student_first_name, null::text as student_last_name,
          currency, payment_date, method, external_id, notes, created_by, created_at,
          lesson_id
      `,
          [
            dto.studentId,
            dto.amount,
            dto.currency ?? null,
            dto.paymentDate,
            dto.method?.trim() || null,
            dto.externalId?.trim() || null,
            dto.notes?.trim() || null,
            actor.userId,
            dto.lessonId ?? null,
          ],
        );
        return { payment: result.rows[0], existing: false };
      },
    );
    if (existing) return toPaymentDto(payment);
    await this.audit.record({
      actor,
      action: "crm.payment_created",
      entityType: "student",
      entityId: payment.student_id,
      metadata: { paymentId: payment.id },
    });
    const affectedUserIds = await clientFinanceAudienceForStudent(
      this.database,
      payment.student_id,
    );
    this.realtime.emitFinanceChanged(affectedUserIds);
    return toPaymentDto(payment);
  }
}
