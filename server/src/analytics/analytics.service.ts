import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmService } from "../crm/crm.service";
import { CrmPolicy } from "../crm/crm.policy";

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly crm: CrmService,
    private readonly policy: CrmPolicy,
  ) {}

  overview(actor: ActorContext) {
    return this.crm.getOverview(actor);
  }

  dashboard(actor: ActorContext, query: Parameters<CrmService["getManagerDashboard"]>[1]) {
    return this.crm.getManagerDashboard(actor, query);
  }

  async financeMonthly(actor: ActorContext, query: { from?: string; to?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      month_start: string;
      lessons: number;
      completed_lessons: number;
      revenue: number;
      expenses: number;
      new_students: number;
    }>(
      `select month_start, lessons, completed_lessons, revenue, expenses, new_students
         from app.mv_finance_monthly
        where ($1::date is null or month_start >= $1::date)
          and ($2::date is null or month_start < $2::date)
        order by month_start`,
      [query.from ?? null, query.to ?? null],
    );
    return {
      items: result.rows.map((r) => ({
        monthStart: r.month_start,
        lessons: Number(r.lessons),
        completedLessons: Number(r.completed_lessons),
        revenue: Number(r.revenue),
        expenses: Number(r.expenses),
        newStudents: Number(r.new_students),
      })),
    };
  }

  private rangeBounds(query: { from?: string; to?: string }): { from: string; to: string } {
    const to = query.to ?? new Date().toISOString();
    const from =
      query.from ?? new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
    return { from, to };
  }

  async funnel(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      status_id: string;
      name: string;
      sort_order: number;
      leads_entered: string;
    }>(
      `select ls.id as status_id, ls.name, ls.sort_order,
              count(distinct lsh.lead_id) as leads_entered
         from app.lead_status_history lsh
         join app.lead_statuses ls on ls.id = lsh.new_status_id
        where lsh.new_status_id is not null
          and lsh.changed_at >= $1::timestamptz
          and lsh.changed_at < $2::timestamptz
          and ($3::uuid is null or lsh.branch_id = $3::uuid)
        group by ls.id, ls.name, ls.sort_order
        order by ls.sort_order`,
      [from, to, query.branchId ?? null],
    );
    let prev: number | null = null;
    const stages = result.rows.map((r) => {
      const leadsEntered = Number(r.leads_entered);
      // Volume ratio of distinct leads that ENTERED this status vs the previous status in the window —
      // NOT a per-lead cohort conversion; can exceed 100%.
      const ratioToPrevStage =
        prev === null || prev === 0 ? (prev === null ? null : 0) : Math.round((leadsEntered / prev) * 100);
      prev = leadsEntered;
      return { statusId: r.status_id, name: r.name, sortOrder: r.sort_order, leadsEntered, ratioToPrevStage };
    });
    return { from, to, stages };
  }

  async branchComparison(actor: ActorContext, query: { from?: string; to?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const { from, to } = this.rangeBounds(query);
    // Mirror of CrmService.branchIdExpr (column preferred, custom_data fallback).
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{
      branch_id: string;
      name: string;
      revenue: string;
      active_students: string;
      new_leads: string;
      completed_lessons: string;
    }>(
      `select b.id as branch_id, b.name,
         (select coalesce(sum(p.amount), 0) from app.payments p
            join app.students s on s.id = p.student_id and s.deleted_at is null
           where p.deleted_at is null and p.payment_date >= $1::timestamptz and p.payment_date < $2::timestamptz
             and ${branchOf("s")} = b.id::text) as revenue,
         (select count(*) from app.students s
           where s.deleted_at is null and s.status = 'active' and ${branchOf("s")} = b.id::text) as active_students,
         (select count(*) from app.leads l
           where l.deleted_at is null and l.created_at >= $1::timestamptz and l.created_at < $2::timestamptz
             and ${branchOf("l")} = b.id::text) as new_leads,
         (select count(*) from app.lessons les
           where les.deleted_at is null and les.status in ('completed', 'done')
             and les.scheduled_at >= $1::timestamptz and les.scheduled_at < $2::timestamptz
             and les.branch_id = b.id) as completed_lessons
       from app.branches b
       where b.deleted_at is null
       order by b.name`,
      [from, to],
    );
    return {
      from,
      to,
      branches: result.rows.map((r) => ({
        branchId: r.branch_id,
        name: r.name,
        revenue: Number(r.revenue),
        activeStudents: Number(r.active_students),
        newLeads: Number(r.new_leads),
        completedLessons: Number(r.completed_lessons),
      })),
    };
  }

  async lossReasons(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      reason_id: string;
      name: string;
      kind: string;
      leads: string;
    }>(
      `select lr.id as reason_id, lr.name, lr.kind,
              count(distinct lsh.lead_id) as leads
         from app.lead_status_history lsh
         join app.lead_statuses ls on ls.id = lsh.new_status_id and ls.is_terminal = true
         -- Intentionally NO deleted_at/is_active filter on lead_loss_reasons: historical fidelity —
         -- count the reason as it was recorded at the time of the transition.
         join app.lead_loss_reasons lr on lr.id = lsh.reason_id
        where lsh.reason_id is not null
          and lsh.changed_at >= $1::timestamptz
          and lsh.changed_at < $2::timestamptz
          and ($3::uuid is null or lsh.branch_id = $3::uuid)
        group by lr.id, lr.name, lr.kind
        order by leads desc`,
      [from, to, query.branchId ?? null],
    );
    const unspecifiedResult = await this.database.query<{ unspecified: string }>(
      `select count(distinct lsh.lead_id) as unspecified
         from app.lead_status_history lsh
         join app.lead_statuses ls on ls.id = lsh.new_status_id and ls.is_terminal = true
        where lsh.reason_id is null
          and lsh.changed_at >= $1::timestamptz and lsh.changed_at < $2::timestamptz
          and ($3::uuid is null or lsh.branch_id = $3::uuid)`,
      [from, to, query.branchId ?? null],
    );
    return {
      from,
      to,
      reasons: result.rows.map((r) => ({
        reasonId: r.reason_id,
        name: r.name,
        kind: r.kind,
        leads: Number(r.leads),
      })),
      unspecifiedCount: Number(unspecifiedResult.rows[0]?.unspecified ?? 0),
    };
  }

  async debts(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{ bucket: string; students: string; amount: string }>(
      `select
         case
           when now()::date - ep.due_date between 0 and 7 then '0-7'
           when now()::date - ep.due_date between 8 and 14 then '8-14'
           when now()::date - ep.due_date between 15 and 30 then '15-30'
           else '30+'
         end as bucket,
         count(distinct ep.student_id) as students,
         coalesce(sum(ep.amount), 0) as amount
       from app.expected_payments ep
       join app.students s on s.id = ep.student_id and s.deleted_at is null
      where ep.status in ('pending', 'open')
        and ep.due_date is not null
        and ep.due_date <= now()::date
        and ($1::uuid is null or ${branchOf("s")} = $1::text)
      group by 1`,
      [query.branchId ?? null],
    );
    const order = ["0-7", "8-14", "15-30", "30+"];
    const byBucket = new Map(result.rows.map((r) => [r.bucket, r]));
    const buckets = order.map((bucket) => {
      const row = byBucket.get(bucket);
      return { bucket, students: Number(row?.students ?? 0), amount: Number(row?.amount ?? 0) };
    });
    return {
      buckets,
      totalStudents: buckets.reduce((n, b) => n + b.students, 0),
      totalAmount: buckets.reduce((n, b) => n + b.amount, 0),
    };
  }

  async revenueForecast(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{ next7: string; next14: string; next30: string }>(
      `select
         coalesce(sum(ep.amount) filter (where ep.due_date >= now()::date and ep.due_date <= now()::date + 7), 0) as next7,
         coalesce(sum(ep.amount) filter (where ep.due_date >= now()::date and ep.due_date <= now()::date + 14), 0) as next14,
         coalesce(sum(ep.amount) filter (where ep.due_date >= now()::date and ep.due_date <= now()::date + 30), 0) as next30
       from app.expected_payments ep
       join app.students s on s.id = ep.student_id and s.deleted_at is null
      where ep.status in ('pending', 'open')
        and ($1::uuid is null or ${branchOf("s")} = $1::text)`,
      [query.branchId ?? null],
    );
    const row = result.rows[0];
    return { next7: Number(row?.next7 ?? 0), next14: Number(row?.next14 ?? 0), next30: Number(row?.next30 ?? 0) };
  }

  async churnRisk(actor: ActorContext, query: { inactiveDays?: number | string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const inactiveDays = Number(query.inactiveDays ?? 21);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{
      student_id: string;
      name: string;
      last_completed_at: string | null;
      days_since_last: string | null;
    }>(
      `with last_lesson as (
         select coalesce(l.student_id, lp.student_id) as student_id,
                max(l.scheduled_at) as last_completed_at
           from app.lessons l
           left join app.lesson_participation lp on lp.lesson_id = l.id
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and coalesce(l.student_id, lp.student_id) is not null
          group by coalesce(l.student_id, lp.student_id)
       )
       select s.id as student_id,
              btrim(concat_ws(' ', p.first_name, p.last_name)) as name,
              ll.last_completed_at,
              case when ll.last_completed_at is null then null
                   else (now()::date - ll.last_completed_at::date) end as days_since_last
         from app.students s
         left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
         left join last_lesson ll on ll.student_id = s.id
        where s.deleted_at is null and s.status = 'active'
          and ($2::uuid is null or ${branchOf("s")} = $2::text)
          and (ll.last_completed_at is null
               or ll.last_completed_at < now() - make_interval(days => $1::int))
        order by ll.last_completed_at asc nulls first
        limit 200`,
      [inactiveDays, query.branchId ?? null],
    );
    return {
      inactiveDays,
      students: result.rows.map((r) => ({
        studentId: r.student_id,
        name: r.name,
        lastCompletedAt: r.last_completed_at,
        daysSinceLast: r.days_since_last === null ? null : Number(r.days_since_last),
      })),
    };
  }

  async financeMonthlyCsv(actor: ActorContext, query: { from?: string; to?: string }): Promise<string> {
    const { items } = await this.financeMonthly(actor, query);
    const header = "month_start,lessons,completed_lessons,revenue,expenses,new_students";
    const escape = (v: unknown) => {
      const s = String(v ?? "");
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const lines = items.map((i) =>
      [i.monthStart, i.lessons, i.completedLessons, i.revenue, i.expenses, i.newStudents].map(escape).join(","),
    );
    return [header, ...lines].join("\n") + "\n";
  }
}
