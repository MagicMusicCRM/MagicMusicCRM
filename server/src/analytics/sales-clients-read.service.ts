import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { authorizeCurrentCapability } from "../access-control/capability-request-authorizer";
import { ActorContext } from "../common/security/actor-context";
import {
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../crm/branch-scope";
import { DatabaseService } from "../db/database.service";
import {
  SalesClientSegment,
  SalesClientsQuery,
} from "./dto/sales-clients.query";

const OBSERVATION_DAYS = 90;

interface SalesCohortTotalsRow {
  inquiries: string;
  trial_booked: string;
  trial_attended: string;
  trial_to_first_paid: string;
  purchases: string;
  first_paid_sales: string;
  without_trial_sales: string;
  stalled: string;
  avg_days_to_trial: string | null;
  avg_days_to_first_payment: string | null;
}

interface SalesSourceRow {
  source_id: string | null;
  source_label: string;
  inquiries: string;
  trial_attended: string;
  first_paid_sales: string;
  first_payment_amount_minor: string;
}

interface SalesClientItemRow {
  client_type: "lead" | "student";
  client_id: string;
  display_name: string;
  source_label: string;
  stage_label: string;
  inquiry_at: Date | string;
  last_activity_at: Date | string;
  trial_booked_at: Date | string | null;
  trial_attended_at: Date | string | null;
  purchased_at: Date | string | null;
  first_paid_at: Date | string | null;
  next_task_id: string | null;
  next_task_title: string | null;
  next_task_at: Date | string | null;
  total_count: string;
}

interface NormalizedSalesFilter {
  from: string;
  to: string;
  branchId: string | null;
  segment: SalesClientSegment;
  sourceId: string | null;
}

@Injectable()
export class SalesClientsReadService {
  constructor(private readonly database: DatabaseService) {}

  async summary(actor: ActorContext, query: SalesClientsQuery) {
    await authorizeCurrentCapability(
      this.database,
      actor,
      "report.status.read",
    );
    const includeAmounts = await this.canReadSchoolFinance(actor);
    const filter = this.normalizeFilter(query);
    const params = [filter.from, filter.to, filter.branchId, actor.userId];
    const cte = this.journeyCte();
    const [totalsResult, sourcesResult] = await Promise.all([
      this.database.query<SalesCohortTotalsRow>(
        `${cte}
         select
           count(*)::text as inquiries,
           count(*) filter (where trial_booked_at is not null)::text
             as trial_booked,
           count(*) filter (where trial_attended_at is not null)::text
             as trial_attended,
           count(*) filter (
             where trial_attended_at is not null
               and first_paid_at is not null
               and first_paid_at >= trial_attended_at
           )::text as trial_to_first_paid,
           count(*) filter (where purchased_at is not null)::text as purchases,
           count(*) filter (where first_paid_at is not null)::text
             as first_paid_sales,
           count(*) filter (
             where first_paid_at is not null
               and (
                 trial_attended_at is null
                 or first_paid_at < trial_attended_at
               )
           )::text as without_trial_sales,
           count(*) filter (where first_paid_at is null)::text as stalled,
           avg(
             extract(epoch from (trial_attended_at - inquiry_at)) / 86400
           ) filter (where trial_attended_at is not null)::text
             as avg_days_to_trial,
           avg(
             extract(epoch from (first_paid_at - inquiry_at)) / 86400
           ) filter (where first_paid_at is not null)::text
             as avg_days_to_first_payment
         from journey`,
        params,
      ),
      this.database.query<SalesSourceRow>(
        `${cte}
         select
           source_id,
           source_label,
           count(*)::text as inquiries,
           count(*) filter (where trial_attended_at is not null)::text
             as trial_attended,
           count(*) filter (where first_paid_at is not null)::text
             as first_paid_sales,
           coalesce(sum(first_payment_amount_minor), 0)::text
             as first_payment_amount_minor
         from journey
         group by source_id, source_label
         order by count(*) desc, source_label`,
        params,
      ),
    ]);
    const row = totalsResult.rows[0] ?? this.emptyTotals();
    const inquiries = Number(row.inquiries);
    const trialAttended = Number(row.trial_attended);
    const trialToFirstPaid = Number(row.trial_to_first_paid ?? 0);
    const firstPaidSales = Number(row.first_paid_sales);
    return {
      from: filter.from,
      to: filter.to,
      branchId: filter.branchId,
      observationDays: OBSERVATION_DAYS,
      generatedAt: new Date().toISOString(),
      funnel: {
        inquiries,
        trialBooked: Number(row.trial_booked),
        trialAttended,
        purchases: Number(row.purchases),
        firstPaidSales,
        withoutTrialSales: Number(row.without_trial_sales),
        stalled: Number(row.stalled),
        conversionToTrial: inquiries === 0 ? 0 : trialAttended / inquiries,
        conversionToFirstPayment:
          inquiries === 0 ? 0 : firstPaidSales / inquiries,
        trialToFirstPayment:
          trialAttended === 0 ? 0 : trialToFirstPaid / trialAttended,
      },
      speed: {
        averageDaysToTrial: nullableNumber(row.avg_days_to_trial),
        averageDaysToFirstPayment: nullableNumber(
          row.avg_days_to_first_payment,
        ),
      },
      sources: sourcesResult.rows.map((source) => {
        const sourceInquiries = Number(source.inquiries);
        const sourcePaid = Number(source.first_paid_sales);
        return {
          sourceId: source.source_id,
          label: source.source_label,
          inquiries: sourceInquiries,
          trialAttended: Number(source.trial_attended),
          firstPaidSales: sourcePaid,
          conversionToFirstPayment:
            sourceInquiries === 0 ? 0 : sourcePaid / sourceInquiries,
          ...(includeAmounts
            ? {
                firstPaymentAmountMinor: source.first_payment_amount_minor,
                currencyCode: "RUB",
              }
            : {}),
          drilldown: this.drilldownLink("inquiries", source.source_id),
        };
      }),
      drilldowns: {
        inquiries: this.drilldownLink("inquiries"),
        trialBooked: this.drilldownLink("trial_booked"),
        trialAttended: this.drilldownLink("trial_attended"),
        purchases: this.drilldownLink("purchases"),
        firstPaidSales: this.drilldownLink("first_paid"),
        withoutTrialSales: this.drilldownLink("without_trial"),
        stalled: this.drilldownLink("stalled"),
      },
    };
  }

  async list(actor: ActorContext, query: SalesClientsQuery) {
    await authorizeCurrentCapability(
      this.database,
      actor,
      "report.status.read",
    );
    const filter = this.normalizeFilter(query);
    const limit = Math.min(query.limit ?? 50, 200);
    const offset = Math.max(query.offset ?? 0, 0);
    const condition = segmentCondition(filter.segment);
    const result = await this.database.query<SalesClientItemRow>(
      `${this.journeyCte()}
       select
         client_type,
         client_id,
         display_name,
         source_label,
         stage_label,
         inquiry_at,
         last_activity_at,
         trial_booked_at,
         trial_attended_at,
         purchased_at,
         first_paid_at,
         next_task_id,
         next_task_title,
         next_task_at,
         count(*) over ()::text as total_count
       from journey
       where ${condition}
         and (
           $5::text is null
           or ($5::text = 'none' and source_id is null)
           or source_id::text = $5::text
         )
       order by
         case when $8::text = 'stalled' then last_activity_at end asc nulls first,
         inquiry_at desc,
         client_id
       limit $6 offset $7`,
      [
        filter.from,
        filter.to,
        filter.branchId,
        actor.userId,
        filter.sourceId,
        limit,
        offset,
        filter.segment,
      ],
    );
    return {
      filter: {
        version: 1,
        from: filter.from,
        to: filter.to,
        branchId: filter.branchId,
        segment: filter.segment,
        sourceId: filter.sourceId,
        observationDays: OBSERVATION_DAYS,
      },
      total: Number(result.rows[0]?.total_count ?? 0),
      limit,
      offset,
      items: result.rows.map((row) => ({
        type: row.client_type,
        id: row.client_id,
        displayName: row.display_name,
        sourceLabel: row.source_label,
        stageLabel: row.stage_label,
        inquiryAt: iso(row.inquiry_at),
        lastActivityAt: iso(row.last_activity_at),
        waitingDays: wholeDaysSince(row.last_activity_at),
        trialBookedAt: optionalIso(row.trial_booked_at),
        trialAttendedAt: optionalIso(row.trial_attended_at),
        purchasedAt: optionalIso(row.purchased_at),
        firstPaidAt: optionalIso(row.first_paid_at),
        entityLink: {
          entityType: row.client_type,
          entityId: row.client_id,
        },
        ...(row.next_task_id
          ? {
              nextTask: {
                id: row.next_task_id,
                title: row.next_task_title ?? "Следующая задача",
                dueAt: optionalIso(row.next_task_at),
                entityLink: {
                  entityType: "task",
                  entityId: row.next_task_id,
                },
              },
            }
          : { nextTask: null }),
      })),
    };
  }

  private normalizeFilter(query: SalesClientsQuery): NormalizedSalesFilter {
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
      segment: query.segment ?? "inquiries",
      sourceId: query.sourceId ?? null,
    };
  }

  private async canReadSchoolFinance(actor: ActorContext): Promise<boolean> {
    try {
      await authorizeCurrentCapability(
        this.database,
        actor,
        "commerce.school_finance.read",
      );
      return true;
    } catch (error) {
      if (error instanceof ForbiddenException) return false;
      throw error;
    }
  }

  private drilldownLink(segment: SalesClientSegment, sourceId?: string | null) {
    return {
      entityType: "sales_client_list",
      entityId: `${segment}:${sourceId ?? "all"}`,
      optionalFocus: {
        filter: {
          version: 1,
          segment,
          ...(sourceId !== undefined ? { sourceId: sourceId ?? "none" } : {}),
        },
      },
    };
  }

  private emptyTotals(): SalesCohortTotalsRow {
    return {
      inquiries: "0",
      trial_booked: "0",
      trial_attended: "0",
      trial_to_first_paid: "0",
      purchases: "0",
      first_paid_sales: "0",
      without_trial_sales: "0",
      stalled: "0",
      avg_days_to_trial: null,
      avg_days_to_first_payment: null,
    };
  }

  private journeyCte(): string {
    const role = currentActorRoleSql("$4");
    const branchScope = managerBranchScopeSql({
      roleExpression: role,
      userIdExpression: "$4",
      branchExpression: "client.branch_id::text",
    });
    return `
      with cohort as (
        select
          client.id as canonical_client_id,
          case when student.id is not null then 'student' else 'lead' end
            as client_type,
          coalesce(student.id, lead.id) as client_id,
          coalesce(
            nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), ''),
            nullif(btrim(concat_ws(' ', lead.first_name, lead.last_name)), ''),
            nullif(btrim(concat_ws(' ', client.first_name, client.last_name)), ''),
            'Без имени'
          ) as display_name,
          client.branch_id,
          client.created_at as inquiry_at,
          lead.id as lead_id,
          student.id as student_id,
          coalesce(snapshot_catalog.id, client.source_id) as source_id,
          coalesce(
            nullif(source_history.source_snapshot, ''),
            source.display_name,
            nullif(lead.source, ''),
            'Источник не указан'
          ) as source_label,
          coalesce(lead_status.name, nullif(student.status, ''), 'Новый клиент')
            as current_stage_label,
          client.updated_at as client_updated_at
        from app.clients client
        left join lateral (
          select candidate.*
          from app.students candidate
          where candidate.client_id = client.id
          order by (candidate.deleted_at is null) desc,
            candidate.created_at desc, candidate.id
          limit 1
        ) student on true
        left join app.profiles profile on profile.id = student.profile_id
        left join lateral (
          select candidate.*
          from app.leads candidate
          where candidate.client_id = client.id
          order by (candidate.deleted_at is null) desc,
            candidate.created_at, candidate.id
          limit 1
        ) lead on true
        left join app.lead_statuses lead_status on lead_status.id = lead.status_id
        left join lateral (
          select history.source_snapshot
          from app.lead_status_history history
          where history.lead_id = lead.id
            and nullif(btrim(history.source_snapshot), '') is not null
          order by history.changed_at, history.id
          limit 1
        ) source_history on true
        left join lateral (
          select candidate.id
          from app.lead_sources candidate
          where lower(btrim(candidate.display_name)) =
              lower(btrim(source_history.source_snapshot))
             or lower(btrim(candidate.canonical_name)) =
              lower(btrim(source_history.source_snapshot))
          order by (candidate.deleted_at is null) desc, candidate.created_at,
            candidate.id
          limit 1
        ) snapshot_catalog on true
        left join app.lead_sources source on source.id = client.source_id
        where client.created_at >= $1::timestamptz
          and client.created_at < $2::timestamptz
          and ($3::uuid is null or client.branch_id = $3::uuid)
          and ${branchScope}
      ),
      journey as (
        select
          cohort.*,
          trial.trial_booked_at,
          trial.trial_attended_at,
          purchase.purchased_at,
          payment.first_paid_at,
          payment.first_payment_amount_minor,
          next_task.next_task_id,
          next_task.next_task_title,
          next_task.next_task_at,
          greatest(
            cohort.inquiry_at,
            cohort.client_updated_at,
            status_activity.changed_at,
            trial.last_trial_activity_at,
            purchase.purchased_at,
            payment.first_paid_at,
            next_task.next_task_updated_at
          ) as last_activity_at,
          case
            when payment.first_paid_at is not null then 'Первая оплата'
            when purchase.purchased_at is not null then 'Абонемент без оплаты'
            when trial.trial_attended_at is not null then 'Пробное посещено'
            when trial.trial_booked_at is not null then 'Пробное назначено'
            else cohort.current_stage_label
          end as stage_label
        from cohort
        left join lateral (
          select
            min(lesson.scheduled_at) as trial_booked_at,
            min(lesson.scheduled_at) filter (
              where lesson.lifecycle_state = 'successfully_completed'
                and (
                  lesson.lead_id = cohort.lead_id
                  or not exists (
                    select 1 from app.lesson_participation participation
                    where participation.lesson_id = lesson.id
                  )
                  or exists (
                    select 1 from app.lesson_participation participation
                    where participation.lesson_id = lesson.id
                      and participation.student_id = cohort.student_id
                      and participation.attendance_kind in (
                        'attended', 'free_lesson', 'partially_paid'
                      )
                  )
                )
            ) as trial_attended_at,
            max(lesson.updated_at) as last_trial_activity_at
          from app.lessons lesson
          where lesson.deleted_at is null
            and lesson.is_trial = true
            and lesson.scheduled_at >= cohort.inquiry_at
            and lesson.scheduled_at < least(
              cohort.inquiry_at + interval '${OBSERVATION_DAYS} days', now()
            )
            and (
              lesson.lead_id = cohort.lead_id
              or lesson.student_id = cohort.student_id
              or exists (
                select 1 from app.lesson_participation participant
                where participant.lesson_id = lesson.id
                  and participant.student_id = cohort.student_id
              )
            )
        ) trial on true
        left join lateral (
          select min(subscription.created_at) as purchased_at
          from app.subscriptions subscription
          where subscription.student_id = cohort.student_id
            and subscription.created_at >= cohort.inquiry_at
            and subscription.created_at < least(
              cohort.inquiry_at + interval '${OBSERVATION_DAYS} days', now()
            )
        ) purchase on true
        left join lateral (
          select
            first_payment.payment_date as first_paid_at,
            first_payment.amount_minor as first_payment_amount_minor
          from app.commerce_ordinary_payments first_payment
          join app.subscriptions paid_subscription
            on paid_subscription.id = first_payment.issued_subscription_id
          where paid_subscription.student_id = cohort.student_id
            and first_payment.issued_subscription_id is not null
            and first_payment.deleted_at is null
            and first_payment.amount_minor > 0
            and first_payment.payment_date >= cohort.inquiry_at
            and first_payment.payment_date < least(
              cohort.inquiry_at + interval '${OBSERVATION_DAYS} days', now()
            )
          order by first_payment.payment_date, first_payment.created_at,
            first_payment.id
          limit 1
        ) payment on true
        left join lateral (
          select max(activity.changed_at) as changed_at
          from (
            select history.changed_at
            from app.lead_status_history history
            where history.lead_id = cohort.lead_id
            union all
            select history.changed_at
            from app.student_status_history history
            where history.student_id = cohort.student_id
          ) activity
        ) status_activity on true
        left join lateral (
          select
            task.id as next_task_id,
            task.title as next_task_title,
            task.start_at as next_task_at,
            task.updated_at as next_task_updated_at
          from app.shared_tasks task
          where task.deleted_at is null
            and task.state = 'open'
            and (
              (task.linked_entity_type = 'client'
                and task.linked_entity_id = cohort.canonical_client_id)
              or (task.linked_entity_type = 'lead'
                and task.linked_entity_id = cohort.lead_id)
              or (task.linked_entity_type = 'student'
                and task.linked_entity_id = cohort.student_id)
            )
          order by task.start_at nulls last, task.created_at, task.id
          limit 1
        ) next_task on true
      )`;
  }
}

function segmentCondition(segment: SalesClientSegment): string {
  return switchSegment(segment);
}

function switchSegment(segment: SalesClientSegment): string {
  switch (segment) {
    case "trial_booked":
      return "trial_booked_at is not null";
    case "trial_attended":
      return "trial_attended_at is not null";
    case "purchases":
      return "purchased_at is not null";
    case "first_paid":
      return "first_paid_at is not null";
    case "without_trial":
      return `(first_paid_at is not null and
        (trial_attended_at is null or first_paid_at < trial_attended_at))`;
    case "stalled":
      return "first_paid_at is null";
    case "inquiries":
      return "true";
  }
}

function nullableNumber(value: string | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function iso(value: Date | string): string {
  return new Date(value).toISOString();
}

function optionalIso(value: Date | string | null): string | null {
  return value === null ? null : iso(value);
}

function wholeDaysSince(value: Date | string): number {
  const elapsed = Date.now() - new Date(value).getTime();
  return Math.max(0, Math.floor(elapsed / 86_400_000));
}
