import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { branchIdExpr } from "../branch-scope";
import {
  CommerceAccountDto,
  CommerceMovementDto,
  CommerceProjectionScope,
  CommerceProjectionSource,
  CommerceSubscriptionDto,
} from "./commerce-projection.types";

interface ScopeRow {
  student_id: string;
  branch_id: string | null;
  access_version: number | string;
}

interface ProjectionRow {
  student_id: string;
  accounts: CommerceAccountDto[];
  subscriptions: CommerceSubscriptionDto[];
  movements: CommerceMovementDto[];
}

@Injectable()
export class CommerceProjectionRepository {
  constructor(private readonly database: DatabaseService) {}

  async resolveSelfScopes(
    actor: ActorContext,
  ): Promise<CommerceProjectionScope[]> {
    this.assertClient(actor);
    const result = await this.database.query<ScopeRow>(
      `
        select distinct
          student.id as student_id,
          ${branchIdExpr("student")} as branch_id,
          coalesce(access_version.version, 1) as access_version,
          student.created_at
        from app.students student
        left join app.profiles student_profile
          on student_profile.id = student.profile_id
         and student_profile.deleted_at is null
        left join app.user_access_versions access_version
          on access_version.user_id = $1
        where student.deleted_at is null
          and (
            student_profile.user_id = $1
            or exists (
              select 1
              from app.user_crm_links client_link
              where client_link.user_id = $1
                and client_link.entity_type = 'student'
                and client_link.entity_id = student.id
                and client_link.deleted_at is null
            )
            or exists (
              select 1
              from app.family_members student_member
              join app.families family
                on family.id = student_member.family_id
               and family.deleted_at is null
              join app.family_members account_member
                on account_member.family_id = family.id
               and account_member.entity_type = 'profile'
               and account_member.role in ('parent', 'payer')
               and account_member.deleted_at is null
              join app.profiles account_profile
                on account_profile.id = account_member.entity_id
               and account_profile.deleted_at is null
              where student_member.entity_type = 'student'
                and student_member.entity_id = student.id
                and student_member.deleted_at is null
                and account_profile.user_id = $1
            )
          )
        order by student.created_at desc, student_id
      `,
      [actor.userId],
    );
    return result.rows.map((row) => this.toScope(row, "self"));
  }

  async resolveStudentScope(
    actor: ActorContext,
    studentId: string,
  ): Promise<CommerceProjectionScope> {
    this.assertNotTeacher(actor);
    if (actor.role === "client") {
      const result = await this.database.query<ScopeRow>(
        `
          select
            student.id as student_id,
            ${branchIdExpr("student")} as branch_id,
            coalesce(access_version.version, 1) as access_version
          from app.students student
          left join app.profiles student_profile
            on student_profile.id = student.profile_id
           and student_profile.deleted_at is null
          left join app.user_access_versions access_version
            on access_version.user_id = $1
          where student.id = $2
            and student.deleted_at is null
            and (
              student_profile.user_id = $1
              or exists (
                select 1
                from app.user_crm_links client_link
                where client_link.user_id = $1
                  and client_link.entity_type = 'student'
                  and client_link.entity_id = student.id
                  and client_link.deleted_at is null
              )
              or exists (
                select 1
                from app.family_members student_member
                join app.families family
                  on family.id = student_member.family_id
                 and family.deleted_at is null
                join app.family_members account_member
                  on account_member.family_id = family.id
                 and account_member.entity_type = 'profile'
                 and account_member.role in ('parent', 'payer')
                 and account_member.deleted_at is null
                join app.profiles account_profile
                  on account_profile.id = account_member.entity_id
                 and account_profile.deleted_at is null
                where student_member.entity_type = 'student'
                  and student_member.entity_id = student.id
                  and student_member.deleted_at is null
                  and account_profile.user_id = $1
              )
            )
        `,
        [actor.userId, studentId],
      );
      const row = result.rows[0];
      if (!row) this.throwClientNotFound();
      return this.toScope(row, "self");
    }

    if (actor.role === "director" || actor.role === "system_admin") {
      const result = await this.database.query<ScopeRow>(
        `
          select
            student.id as student_id,
            ${branchIdExpr("student")} as branch_id,
            coalesce(access_version.version, 1) as access_version
          from app.students student
          left join app.user_access_versions access_version
            on access_version.user_id = $1
          where student.id = $2
            and student.deleted_at is null
        `,
        [actor.userId, studentId],
      );
      const row = result.rows[0];
      if (!row) this.throwClientNotFound();
      return this.toScope(
        row,
        actor.role === "director" ? "business" : "emergency",
      );
    }

    const result = await this.database.query<ScopeRow>(
      `
        select
          student.id as student_id,
          ${branchIdExpr("student")} as branch_id,
          coalesce(access_version.version, 1) as access_version
        from app.students student
        left join app.user_access_versions access_version
          on access_version.user_id = $1
        where student.id = $2
          and student.deleted_at is null
          and ${branchIdExpr("student")} is not null
          and exists (
            select 1
            from app.staff_members staff
            join app.profiles staff_profile
              on staff_profile.id = staff.profile_id
             and staff_profile.deleted_at is null
            join app.staff_branch_assignments branch_assignment
              on branch_assignment.staff_member_id = staff.id
             and branch_assignment.deleted_at is null
            where staff.deleted_at is null
              and staff_profile.user_id = $1
              and branch_assignment.branch_id::text =
                ${branchIdExpr("student")}
          )
      `,
      [actor.userId, studentId],
    );
    const row = result.rows[0];
    if (!row) {
      throw new ForbiddenException({
        code: "COMMERCE_BRANCH_SCOPE_DENIED",
        message: "Student commerce is outside the actor branch scope.",
      });
    }
    return this.toScope(row, "branch");
  }

  async loadProjection(
    actor: ActorContext,
    scopes: readonly CommerceProjectionScope[],
  ): Promise<CommerceProjectionSource[]> {
    this.assertNotTeacher(actor);
    if (scopes.length === 0) return [];
    const scopeByStudent = new Map(
      scopes.map((scope) => [scope.studentId, scope]),
    );
    const result = await this.database.query<ProjectionRow>(
      `
        select
          selected.student_id,
          coalesce(account_projection.items, '[]'::jsonb) as accounts,
          coalesce(subscription_projection.items, '[]'::jsonb)
            as subscriptions,
          coalesce(movement_projection.items, '[]'::jsonb) as movements
        from unnest($1::uuid[]) with ordinality
          as selected(student_id, position)
        left join lateral (
          with monetary_facts as (
            select
              payment.currency as currency_code,
              payment.amount_minor::numeric as actual_payment_minor,
              0::numeric as adjustment_minor,
              0::numeric as obligation_debit_minor,
              0::numeric as obligation_credit_minor,
              0::numeric as write_off_minor
            from app.payments payment
            where payment.student_id = selected.student_id
              and payment.deleted_at is null
              and payment.amount_minor is not null
            union all
            select
              obligation.currency_code,
              0::numeric,
              0::numeric,
              case
                when obligation.direction = 'debit'
                  then obligation.amount_minor::numeric
                else 0::numeric
              end,
              case
                when obligation.direction = 'credit'
                  then obligation.amount_minor::numeric
                else 0::numeric
              end,
              0::numeric
            from app.subscription_obligation_facts obligation
            where obligation.student_id = selected.student_id
            union all
            select
              lesson_charge.currency_code,
              0::numeric,
              0::numeric,
              0::numeric,
              0::numeric,
              lesson_charge.amount_minor::numeric
            from app.lesson_client_charge_facts lesson_charge
            where lesson_charge.client_type = 'student'
              and lesson_charge.client_id = selected.student_id
            union all
            select
              adjustment.currency_code,
              0::numeric,
              adjustment.amount_minor::numeric,
              0::numeric,
              0::numeric,
              0::numeric
            from app.account_adjustments adjustment
            where adjustment.student_id = selected.student_id
              and adjustment.deleted_at is null
              and adjustment.status = 'paid'
          ),
          totals as (
            select
              currency_code,
              sum(actual_payment_minor) as actual_payments_minor,
              sum(adjustment_minor) as adjustments_minor,
              sum(obligation_debit_minor) as obligation_debits_minor,
              sum(obligation_credit_minor) as obligation_credits_minor,
              sum(write_off_minor) as write_offs_minor
            from monetary_facts
            group by currency_code
          )
          select jsonb_agg(
            jsonb_build_object(
              'currencyCode', totals.currency_code,
              'actualPaymentsMinor', totals.actual_payments_minor::text,
              'adjustmentsMinor', totals.adjustments_minor::text,
              'obligationDebitsMinor', totals.obligation_debits_minor::text,
              'obligationCreditsMinor', totals.obligation_credits_minor::text,
              'writeOffsMinor', totals.write_offs_minor::text,
              'balanceMinor', (
                totals.actual_payments_minor
                + totals.adjustments_minor
                + totals.obligation_credits_minor
                - totals.obligation_debits_minor
                - totals.write_offs_minor
              )::text,
              'debtMinor', greatest(
                -(
                  totals.actual_payments_minor
                  + totals.adjustments_minor
                  + totals.obligation_credits_minor
                  - totals.obligation_debits_minor
                  - totals.write_offs_minor
                ),
                0
              )::text
            )
            order by totals.currency_code
          ) as items
          from totals
        ) account_projection on true
        left join lateral (
          select jsonb_agg(
            jsonb_build_object(
              'id', issued.id,
              'status', issued.status,
              'startsAt', issued.starts_at,
              'expiresAt', issued.expires_at,
              'units', jsonb_build_object(
                'total', issued.commercial_snapshot ->> 'unitCount',
                'used', usage.used_units::text,
                'reserved', reservation.reserved_units::text,
                'paid', financial.paid_units::text,
                'available', greatest(
                  financial.paid_units
                    - usage.used_units
                    - reservation.reserved_units,
                  0
                )::text,
                'remaining', greatest(
                  (issued.commercial_snapshot ->> 'unitCount')::numeric
                    - usage.used_units,
                  0
                )::text
              ),
              'financial', jsonb_build_object(
                'actualPaidMinor', financial.actual_paid_minor::text,
                'obligationMinor', financial.obligation_minor::text,
                'debtMinor', greatest(
                  financial.obligation_minor - financial.actual_paid_minor,
                  0
                )::text,
                'overpaymentMinor', greatest(
                  financial.actual_paid_minor - financial.obligation_minor,
                  0
                )::text,
                'nextPaymentAt', financial.next_payment_at
              ),
              'terms', jsonb_build_object(
                'displayName',
                  issued.commercial_snapshot ->> 'displayName',
                'validityDays',
                  issued.commercial_snapshot -> 'validityDays',
                'basePriceMinor',
                  issued.commercial_snapshot ->> 'basePriceMinor',
                'finalPriceMinor',
                  issued.commercial_snapshot ->> 'finalPriceMinor',
                'currencyCode',
                  issued.commercial_snapshot ->> 'currencyCode',
                'discount',
                  issued.commercial_snapshot -> 'discount',
                'surcharge',
                  coalesce(
                    issued.commercial_snapshot -> 'surcharge',
                    '{"type":"none"}'::jsonb
                  )
              ),
              'installments', coalesce(
                installment_projection.items,
                '[]'::jsonb
              )
            )
            order by issued.created_at desc, issued.id
          ) as items
          from app.subscriptions issued
          left join lateral (
            select
              coalesce(
                nullif(
                  issued.commercial_snapshot
                    #>> '{commercialRules,carriedUsedUnits}',
                  ''
                )::numeric,
                0
              ) + coalesce(sum(charge.units), 0)::numeric as used_units
            from app.lesson_client_charge_facts charge
            where charge.subscription_id = issued.id
              and charge.client_type = 'student'
              and charge.client_id = selected.student_id
              and charge.charge_type = 'subscription'
          ) usage on true
          left join lateral (
            select coalesce(sum(reservation.units), 0)::numeric
              as reserved_units
            from app.lesson_reservations reservation
            where reservation.subscription_id = issued.id
              and reservation.state = 'reserved'
          ) reservation on true
          left join lateral (
            with recursive lifecycle_chain(id) as (
              select issued.id
              union
              select event.before_issued_subscription_id
              from app.subscription_lifecycle_events event
              join lifecycle_chain current
                on current.id = event.after_issued_subscription_id
              where event.event_type = 'replace'
            ), totals as (
              select
                coalesce((
                  select sum(payment.amount_minor)
                  from app.payments payment
                  where payment.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                    and payment.deleted_at is null
                ), 0)::numeric
                + coalesce((
                  select sum(adjustment.amount_minor)
                  from app.account_adjustments adjustment
                  join app.payments source_payment
                    on source_payment.id = adjustment.source_payment_id
                  where source_payment.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                    and adjustment.deleted_at is null
                    and adjustment.status = 'paid'
                ), 0)::numeric as actual_paid_minor,
                coalesce((
                  select sum(
                    case
                      when obligation.direction = 'debit'
                        then obligation.amount_minor
                      else -obligation.amount_minor
                    end
                  )
                  from app.subscription_obligation_facts obligation
                  where obligation.issued_subscription_id in (
                    select id from lifecycle_chain
                  )
                ), 0)::numeric as obligation_minor
            )
            select
              totals.actual_paid_minor,
              totals.obligation_minor,
              case
                when totals.obligation_minor <= 0 then
                  (issued.commercial_snapshot ->> 'unitCount')::numeric
                else least(
                  (issued.commercial_snapshot ->> 'unitCount')::numeric,
                  greatest(totals.actual_paid_minor, 0)
                    * (issued.commercial_snapshot ->> 'unitCount')::numeric
                    / totals.obligation_minor
                )
              end as paid_units,
              (
                select min(pending.due_at)
                from (
                  select
                    installment.due_at,
                    sum(
                      case
                        when installment.status = 'void' then 0
                        else installment.amount_minor
                      end
                    ) over (order by installment.installment_number)
                      as cumulative_minor
                  from app.subscription_installments installment
                  where installment.issued_subscription_id = issued.id
                ) pending
                where pending.cumulative_minor > totals.actual_paid_minor
              ) as next_payment_at
            from totals
          ) financial on true
          left join lateral (
            select jsonb_agg(
              jsonb_build_object(
                'installmentNumber', installment.installment_number,
                'dueAt', installment.due_at,
                'amountMinor', installment.amount_minor::text,
                'currencyCode', installment.currency_code,
                'status', case
                  when installment.status = 'void' then 'void'
                  when financial.actual_paid_minor >= installment.cumulative_minor
                    then 'paid'
                  else 'pending'
                end
              )
              order by installment.installment_number
            ) as items
            from (
              select
                item.*,
                sum(
                  case when item.status = 'void' then 0 else item.amount_minor end
                ) over (
                  order by item.installment_number
                ) as cumulative_minor
              from app.subscription_installments item
              where item.issued_subscription_id = issued.id
            ) installment
          ) installment_projection on true
          where issued.student_id = selected.student_id
            and issued.commercial_snapshot is not null
        ) subscription_projection on true
        left join lateral (
          select jsonb_agg(
            jsonb_build_object(
              'id', movement.id,
              'kind', movement.kind,
              'direction', movement.direction,
              'amountMinor', movement.amount_minor,
              'currencyCode', movement.currency_code,
              'occurredAt', movement.occurred_at,
              'method', movement.method,
              'factType', movement.fact_type,
              'chargeType', movement.charge_type,
              'branchId', movement.branch_id,
              'branchName', movement.branch_name,
              'comment', movement.comment,
              'invoiceIdentifier', movement.invoice_identifier,
              'status', movement.status,
              'acceptedByName', movement.accepted_by_name,
              'issuedSubscriptionId', movement.issued_subscription_id,
              'subscriptionName', movement.subscription_name,
              'sourcePaymentId', movement.source_payment_id
            )
            order by movement.occurred_at desc, movement.id desc
          ) as items
          from (
            select *
            from (
              select
                payment.id,
                'payment'::text as kind,
                'credit'::text as direction,
                payment.amount_minor::text as amount_minor,
                payment.currency as currency_code,
                payment.payment_date as occurred_at,
                payment.method::text as method,
                null::text as fact_type,
                null::text as charge_type,
                payment.branch_id,
                branch.name as branch_name,
                payment.notes as comment,
                payment.invoice_number as invoice_identifier,
                'paid'::text as status,
                nullif(btrim(
                  coalesce(author.first_name, '') || ' ' ||
                  coalesce(author.last_name, '')
                ), '') as accepted_by_name,
                payment.issued_subscription_id,
                subscription.commercial_snapshot ->> 'displayName'
                  as subscription_name,
                null::uuid as source_payment_id
              from app.payments payment
              left join app.branches branch on branch.id = payment.branch_id
              left join app.subscriptions subscription
                on subscription.id = payment.issued_subscription_id
              left join app.users creator on creator.id = payment.created_by
              left join app.profiles author on author.user_id = creator.id
              where payment.student_id = selected.student_id
                and payment.deleted_at is null
                and payment.amount_minor is not null
              union all
              select
                obligation.id,
                'obligation'::text,
                obligation.direction::text,
                obligation.amount_minor::text,
                obligation.currency_code,
                obligation.occurred_at,
                null::text,
                obligation.fact_type,
                null::text,
                null::uuid,
                null::text,
                null::text,
                null::text,
                null::text,
                null::text,
                obligation.issued_subscription_id,
                subscription.commercial_snapshot ->> 'displayName',
                null::uuid
              from app.subscription_obligation_facts obligation
              left join app.subscriptions subscription
                on subscription.id = obligation.issued_subscription_id
              where obligation.student_id = selected.student_id
              union all
              select
                charge.id,
                'lesson_charge'::text,
                'debit'::text,
                charge.amount_minor::text,
                charge.currency_code,
                charge.created_at,
                null::text,
                null::text,
                charge.charge_type,
                null::uuid,
                null::text,
                null::text,
                null::text,
                null::text,
                null::text,
                charge.subscription_id,
                subscription.commercial_snapshot ->> 'displayName',
                null::uuid
              from app.lesson_client_charge_facts charge
              left join app.subscriptions subscription
                on subscription.id = charge.subscription_id
              where charge.client_type = 'student'
                and charge.client_id = selected.student_id
              union all
              select
                adjustment.id,
                case when adjustment.kind = 'refund'
                  then 'refund'::text else 'adjustment'::text end,
                case when adjustment.amount_minor > 0
                  then 'credit'::text else 'debit'::text end,
                abs(adjustment.amount_minor)::text,
                adjustment.currency_code,
                adjustment.occurred_at,
                adjustment.method,
                null::text,
                null::text,
                adjustment.branch_id,
                branch.name,
                adjustment.description,
                adjustment.invoice_number,
                adjustment.status,
                nullif(btrim(
                  coalesce(author.first_name, '') || ' ' ||
                  coalesce(author.last_name, '')
                ), ''),
                source_payment.issued_subscription_id,
                subscription.commercial_snapshot ->> 'displayName',
                adjustment.source_payment_id
              from app.account_adjustments adjustment
              left join app.payments source_payment
                on source_payment.id = adjustment.source_payment_id
              left join app.subscriptions subscription
                on subscription.id = source_payment.issued_subscription_id
              left join app.branches branch on branch.id = adjustment.branch_id
              left join app.users creator on creator.id = adjustment.created_by
              left join app.profiles author on author.user_id = creator.id
              where adjustment.student_id = selected.student_id
                and adjustment.deleted_at is null
            ) all_movements
            order by occurred_at desc, id desc
            limit 200
          ) movement
        ) movement_projection on true
        order by selected.position
      `,
      [scopes.map((scope) => scope.studentId)],
    );

    return result.rows.flatMap((row) => {
      const scope = scopeByStudent.get(row.student_id);
      return scope
        ? [
            {
              studentId: row.student_id,
              accounts: row.accounts,
              subscriptions: row.subscriptions,
              movements: row.movements,
              scope,
            },
          ]
        : [];
    });
  }

  private toScope(
    row: ScopeRow,
    scopeType: "self" | "branch" | "business" | "emergency",
  ): CommerceProjectionScope {
    const branchPart = row.branch_id ?? "none";
    const scopeKey =
      scopeType === "self"
        ? `self:student:${row.student_id}`
        : scopeType === "emergency"
          ? `emergency:student:${row.student_id}`
          : scopeType === "business"
            ? `business:student:${row.student_id}`
          : `branch:${branchPart}:student:${row.student_id}`;
    return {
      studentId: row.student_id,
      branchId: row.branch_id,
      accessVersion: Number(row.access_version),
      scopeKey,
    };
  }

  private assertClient(actor: ActorContext): void {
    this.assertNotTeacher(actor);
    if (actor.role !== "client") {
      throw new ForbiddenException({
        code: "COMMERCE_SELF_CLIENT_ONLY",
        message: "The self commerce projection is client-only.",
      });
    }
  }

  private assertNotTeacher(actor: ActorContext): void {
    if (actor.role === "teacher") {
      throw new ForbiddenException({
        code: "COMMERCE_PROJECTION_TEACHER_DENIED",
        message: "Teacher commerce projections are not available.",
      });
    }
  }

  private throwClientNotFound(): never {
    throw new NotFoundException({
      code: "COMMERCE_CLIENT_NOT_FOUND",
      message: "Student commerce was not found.",
    });
  }
}
