import { BadRequestException, Injectable } from "@nestjs/common";
import { authorizeCurrentCapability } from "../access-control/capability-request-authorizer";
import { ActorContext } from "../common/security/actor-context";
import {
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../crm/branch-scope";
import { subscriptionFundingSql } from "../crm/commerce/subscription-funding.sql";
import { DatabaseService } from "../db/database.service";
import { FinanceDebtQuery, FinanceDebtSegment } from "./dto/finance-debt.query";

interface FinanceTotalsRow {
  remaining_minor: string;
  overdue_minor: string;
  forecast_minor: string;
  paid_unused_units: string;
  overdue_clients: string;
}

interface FinanceItemRow {
  subscription_id: string;
  student_id: string;
  client_id: string;
  display_name: string;
  package_name: string;
  owner_user_id: string | null;
  owner_name: string | null;
  remaining_minor: string;
  overdue_minor: string;
  forecast_minor: string;
  paid_unused_units: string;
  next_due_at: Date | string | null;
  next_due_is_forecast: boolean;
  latest_payment_id: string | null;
  next_task_id: string | null;
  next_task_title: string | null;
  next_task_at: Date | string | null;
  total_count: string;
}

interface NormalizedFinanceFilter {
  from: string;
  to: string;
  branchId: string | null;
  segment: FinanceDebtSegment;
}

@Injectable()
export class FinanceDebtReadService {
  constructor(private readonly database: DatabaseService) {}

  async summary(actor: ActorContext, query: FinanceDebtQuery) {
    await authorizeCurrentCapability(
      this.database,
      actor,
      "commerce.school_finance.read",
    );
    const filter = this.normalize(query);
    const params = [filter.from, filter.to, filter.branchId, actor.userId];
    const [receipts, totals] = await Promise.all([
      this.database.query<{ receipts_minor: string }>(
        this.receiptsSql(),
        params.slice(0, 3),
      ),
      this.database.query<FinanceTotalsRow>(
        `${this.financeCte()}
         select
           coalesce(sum(remaining_minor::numeric), 0)::text as remaining_minor,
           coalesce(sum(overdue_minor::numeric), 0)::text as overdue_minor,
           coalesce(sum(forecast_minor::numeric), 0)::text as forecast_minor,
           coalesce(sum(paid_unused_units::numeric), 0)::text as paid_unused_units,
           count(distinct student_id) filter (where overdue_minor::numeric > 0)::text
             as overdue_clients
         from finance_rows`,
        params,
      ),
    ]);
    const total = totals.rows[0] ?? {
      remaining_minor: "0",
      overdue_minor: "0",
      forecast_minor: "0",
      paid_unused_units: "0",
      overdue_clients: "0",
    };
    return {
      from: filter.from,
      to: filter.to,
      branchId: filter.branchId,
      generatedAt: new Date().toISOString(),
      currencyCode: "RUB",
      receiptsMinor: receipts.rows[0]?.receipts_minor ?? "0",
      remainingMinor: total.remaining_minor,
      overdueMinor: total.overdue_minor,
      forecastMinor: total.forecast_minor,
      paidUnusedUnits: total.paid_unused_units,
      overdueClients: Number(total.overdue_clients),
      drilldowns: {
        overdue: this.drilldown("overdue"),
        remaining: this.drilldown("remaining"),
        paidUnused: this.drilldown("paid_unused"),
        forecast: this.drilldown("forecast"),
      },
    };
  }

  async list(actor: ActorContext, query: FinanceDebtQuery) {
    await authorizeCurrentCapability(
      this.database,
      actor,
      "commerce.school_finance.read",
    );
    const filter = this.normalize(query);
    const limit = Math.min(query.limit ?? 50, 200);
    const offset = Math.max(query.offset ?? 0, 0);
    const result = await this.database.query<FinanceItemRow>(
      `${this.financeCte()}
       select
         finance_rows.*,
         count(*) over ()::text as total_count
       from finance_rows
       where ${segmentCondition(filter.segment)}
       order by
         case when $5::text = 'overdue' then overdue_minor end desc,
         next_due_at asc nulls last,
         display_name,
         subscription_id
       limit $6 offset $7`,
      [
        filter.from,
        filter.to,
        filter.branchId,
        actor.userId,
        filter.segment,
        limit,
        offset,
      ],
    );
    return {
      filter: {
        version: 1,
        from: filter.from,
        to: filter.to,
        branchId: filter.branchId,
        segment: filter.segment,
      },
      total: Number(result.rows[0]?.total_count ?? 0),
      limit,
      offset,
      items: result.rows.map((row) => this.mapItem(row)),
    };
  }

  private mapItem(row: FinanceItemRow) {
    return {
      subscriptionId: row.subscription_id,
      studentId: row.student_id,
      clientId: row.client_id,
      displayName: row.display_name,
      packageName: row.package_name,
      owner: row.owner_user_id
        ? {
            id: row.owner_user_id,
            name: row.owner_name ?? "Ответственный",
            entityLink: {
              entityType: "user",
              entityId: row.owner_user_id,
            },
          }
        : null,
      remainingMinor: row.remaining_minor,
      overdueMinor: row.overdue_minor,
      forecastMinor: row.forecast_minor,
      paidUnusedUnits: row.paid_unused_units,
      nextDueAt: optionalIso(row.next_due_at),
      nextDueIsForecast: row.next_due_is_forecast,
      clientLink: {
        entityType: "student",
        entityId: row.student_id,
      },
      subscriptionLink: {
        entityType: "subscription",
        entityId: row.subscription_id,
      },
      paymentLink: row.latest_payment_id
        ? {
            entityType: "payment",
            entityId: row.latest_payment_id,
          }
        : null,
      nextTask: row.next_task_id
        ? {
            id: row.next_task_id,
            title: row.next_task_title ?? "Следующая задача",
            dueAt: optionalIso(row.next_task_at),
            entityLink: {
              entityType: "task",
              entityId: row.next_task_id,
            },
          }
        : null,
    };
  }

  private normalize(query: FinanceDebtQuery): NormalizedFinanceFilter {
    const now = new Date();
    const to = query.to ? new Date(query.to) : now;
    const from = query.from
      ? new Date(query.from)
      : new Date(Date.UTC(to.getUTCFullYear(), to.getUTCMonth(), 1));
    if (
      Number.isNaN(from.getTime()) ||
      Number.isNaN(to.getTime()) ||
      from >= to
    ) {
      throw new BadRequestException({
        code: "INVALID_REPORT_RANGE",
        message: "Report date range is invalid.",
      });
    }
    return {
      from: from.toISOString(),
      to: to.toISOString(),
      branchId: query.branchId ?? null,
      segment: query.segment ?? "overdue",
    };
  }

  private receiptsSql(): string {
    return `
      with movements as (
        select
          payment.student_id,
          payment.branch_id,
          payment.amount_minor::numeric as amount_minor,
          payment.payment_date as occurred_at
        from app.commerce_ordinary_payments payment
        where payment.deleted_at is null
          and payment.payment_date >= $1::timestamptz
          and payment.payment_date < $2::timestamptz

        union all

        select
          adjustment.student_id,
          adjustment.branch_id,
          adjustment.amount_minor::numeric,
          adjustment.occurred_at
        from app.commerce_ordinary_account_adjustments adjustment
        where adjustment.deleted_at is null
          and adjustment.status = 'paid'
          and adjustment.kind in ('refund', 'adjustment')
          and adjustment.occurred_at >= $1::timestamptz
          and adjustment.occurred_at < $2::timestamptz
      )
      select coalesce(sum(movement.amount_minor), 0)::text as receipts_minor
      from movements movement
      join app.students student on student.id = movement.student_id
      where ($3::uuid is null or coalesce(movement.branch_id, student.branch_id) = $3::uuid)`;
  }

  private financeCte(): string {
    const role = currentActorRoleSql("$4");
    const scope = managerBranchScopeSql({
      roleExpression: role,
      userIdExpression: "$4",
      branchExpression: "client.branch_id::text",
    });
    return `
      with report_range as (
        select $1::timestamptz as from_at, $2::timestamptz as to_at
      ), issued_base as (
        select
          issued.*,
          student.client_id,
          client.branch_id,
          coalesce(branch.timezone_name, 'Europe/Moscow') as timezone_name,
          coalesce(
            nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), ''),
            nullif(btrim(concat_ws(' ', client.first_name, client.last_name)), ''),
            'Без имени'
          ) as display_name,
          client.assigned_to as owner_user_id,
          nullif(btrim(concat_ws(' ', owner_profile.first_name, owner_profile.last_name)), '')
            as owner_name,
          coalesce(
            nullif(issued.commercial_snapshot ->> 'packageName', ''),
            nullif(issued.commercial_snapshot #>> '{package,name}', ''),
            'Абонемент'
          ) as package_name
        from app.subscriptions issued
        join app.students student
          on student.id = issued.student_id and student.deleted_at is null
        join app.clients client
          on client.id = student.client_id and client.deleted_at is null
        left join app.profiles profile on profile.id = student.profile_id
        left join app.branches branch on branch.id = client.branch_id
        left join app.users owner on owner.id = client.assigned_to
        left join app.profiles owner_profile on owner_profile.user_id = owner.id
        where issued.commercial_snapshot is not null
          and ($3::uuid is null or client.branch_id = $3::uuid)
          and ${scope}
      ), funded as (
        select issued.*, funding.*
        from issued_base issued
        join lateral (${subscriptionFundingSql}) funding on true
      ), installment_position as (
        select
          installment.*,
          due_fact.due_at as factual_due_at,
          greatest(
            funded.obligation_minor
              - coalesce(sum(installment.amount_minor) filter (
                  where installment.status <> 'void'
                ) over (partition by installment.issued_subscription_id), 0),
            0
          ) as initial_required_minor,
          sum(case when installment.status = 'void' then 0 else installment.amount_minor end)
            over (
              partition by installment.issued_subscription_id
              order by installment.installment_number
            ) as cumulative_installment_minor,
          funded.actual_paid_minor,
          funded.timezone_name
        from funded
        join app.subscription_installments installment
          on installment.issued_subscription_id = funded.id
        left join app.subscription_installment_due_facts due_fact
          on due_fact.installment_id = installment.id
      ), installment_balance as (
        select
          position.*,
          greatest(
            least(
              position.amount_minor,
              position.initial_required_minor
                + position.cumulative_installment_minor
                - position.actual_paid_minor
            ),
            0
          )::numeric as outstanding_minor,
          case
            when position.due_policy = 'calendar' then position.due_at
            else position.factual_due_at
          end as effective_due_at,
          case
            when position.due_policy = 'consumption'
              and position.factual_due_at is null then true
            else false
          end as due_is_forecast
        from installment_position position
        where position.status <> 'void'
      ), installment_rollup as (
        select
          balance.issued_subscription_id,
          coalesce(sum(balance.outstanding_minor) filter (
            where balance.effective_due_at is not null
              and timezone(balance.timezone_name, balance.effective_due_at)::date
                < timezone(balance.timezone_name, now())::date
          ), 0)::numeric as overdue_minor,
          coalesce(sum(balance.outstanding_minor) filter (
            where balance.outstanding_minor > 0
              and (
                balance.effective_due_at is null
                or timezone(balance.timezone_name, balance.effective_due_at)::date
                  >= timezone(balance.timezone_name, now())::date
              )
          ), 0)::numeric as forecast_minor,
          min(coalesce(balance.effective_due_at, balance.due_at)) filter (
            where balance.outstanding_minor > 0
          ) as next_due_at,
          bool_or(balance.due_is_forecast) filter (
            where balance.outstanding_minor > 0
              and coalesce(balance.effective_due_at, balance.due_at) = (
                select min(coalesce(next_balance.effective_due_at, next_balance.due_at))
                from installment_balance next_balance
                where next_balance.issued_subscription_id = balance.issued_subscription_id
                  and next_balance.outstanding_minor > 0
              )
          ) as next_due_is_forecast
        from installment_balance balance
        group by balance.issued_subscription_id
      ), usage as (
        select
          funded.id as subscription_id,
          coalesce((
            select sum(charge.units)
            from app.lesson_client_charge_facts_effective charge
            where charge.subscription_id = funded.id
          ), 0)::numeric as used_units,
          coalesce((
            select sum(reservation.units)
            from app.lesson_reservations reservation
            where reservation.subscription_id = funded.id
              and reservation.state = 'reserved'
          ), 0)::numeric as reserved_units
        from funded
      ), finance_rows as (
        select
          funded.id as subscription_id,
          funded.student_id,
          funded.client_id,
          funded.display_name,
          funded.package_name,
          funded.owner_user_id,
          funded.owner_name,
          greatest(funded.obligation_minor - funded.actual_paid_minor, 0)::text
            as remaining_minor,
          coalesce(installments.overdue_minor, 0)::text as overdue_minor,
          coalesce(installments.forecast_minor, 0)::text as forecast_minor,
          greatest(
            funded.paid_units - usage.used_units - usage.reserved_units,
            0
          )::text as paid_unused_units,
          installments.next_due_at,
          coalesce(installments.next_due_is_forecast, false)
            as next_due_is_forecast,
          latest_payment.id as latest_payment_id,
          next_task.id as next_task_id,
          next_task.title as next_task_title,
          next_task.start_at as next_task_at
        from funded
        join usage on usage.subscription_id = funded.id
        left join installment_rollup installments
          on installments.issued_subscription_id = funded.id
        left join lateral (
          select payment.id
          from app.commerce_ordinary_payments payment
          where payment.issued_subscription_id = funded.id
            and payment.deleted_at is null
          order by payment.payment_date desc, payment.created_at desc, payment.id
          limit 1
        ) latest_payment on true
        left join lateral (
          select task.id, task.title, task.start_at
          from app.shared_tasks task
          where task.deleted_at is null
            and task.state = 'open'
            and (
              (task.linked_entity_type = 'student'
                and task.linked_entity_id = funded.student_id)
              or (task.linked_entity_type = 'client'
                and task.linked_entity_id = funded.client_id)
            )
          order by task.start_at nulls last, task.created_at, task.id
          limit 1
        ) next_task on true
      )`;
  }

  private drilldown(segment: FinanceDebtSegment) {
    return {
      entityType: "finance_debt_list",
      entityId: segment,
      optionalFocus: { filter: { version: 1, segment } },
    };
  }
}

function segmentCondition(segment: FinanceDebtSegment): string {
  switch (segment) {
    case "remaining":
      return "remaining_minor::numeric > 0";
    case "paid_unused":
      return "paid_unused_units::numeric > 0";
    case "forecast":
      return "forecast_minor::numeric > 0";
    case "overdue":
    default:
      return "overdue_minor::numeric > 0";
  }
}

function optionalIso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date
    ? value.toISOString()
    : new Date(value).toISOString();
}
