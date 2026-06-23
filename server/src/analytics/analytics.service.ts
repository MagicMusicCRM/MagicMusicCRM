import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmService } from "../crm/crm.service";
import { CrmPolicy } from "../crm/crm.policy";

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly crm: CrmService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
  ) {}

  overview(actor: ActorContext) {
    return this.crm.getOverview(actor);
  }

  dashboard(actor: ActorContext, query: Parameters<CrmService["getManagerDashboard"]>[1]) {
    return this.crm.getManagerDashboard(actor, query);
  }

  async financeMonthly(actor: ActorContext, query: { from?: string; to?: string }) {
    this.policy.assertManagerOnly(actor);
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
    this.policy.assertManagerOnly(actor);
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
    this.policy.assertManagerOnly(actor);
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
    this.policy.assertManagerOnly(actor);
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
    this.policy.assertManagerOnly(actor);
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
    const distinctResult = await this.database.query<{ distinct_students: string }>(
      `select count(distinct ep.student_id) as distinct_students
         from app.expected_payments ep
         join app.students s on s.id = ep.student_id and s.deleted_at is null
        where ep.status in ('pending', 'open')
          and ep.due_date is not null
          and ep.due_date <= now()::date
          and ($1::uuid is null or ${branchOf("s")} = $1::text)`,
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
      bucketStudentSum: buckets.reduce((n, b) => n + b.students, 0),
      distinctStudents: Number(distinctResult.rows[0]?.distinct_students ?? 0),
      totalAmount: buckets.reduce((n, b) => n + b.amount, 0),
    };
  }

  async revenueForecast(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertManagerOnly(actor);
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
    this.policy.assertManagerOnly(actor);
    const inactiveDays = Number(query.inactiveDays ?? 21);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;
    const result = await this.database.query<{
      student_id: string;
      name: string;
      last_completed_at: string | null;
      days_since_last: string | null;
      total_at_risk: string;
    }>(
      `with last_lesson as (
         select coalesce(l.student_id, lp.student_id) as student_id,
                max(l.scheduled_at) as last_completed_at
           from app.lessons l
           left join app.lesson_participation lp on lp.lesson_id = l.id
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and coalesce(l.student_id, lp.student_id) is not null
            and (lp.id is null or lp.status not in ('absent', 'missed', 'no_show'))
          group by coalesce(l.student_id, lp.student_id)
       )
       select s.id as student_id,
              btrim(concat_ws(' ', p.first_name, p.last_name)) as name,
              ll.last_completed_at,
              case when ll.last_completed_at is null then null
                   else (now()::date - ll.last_completed_at::date) end as days_since_last,
              count(*) over () as total_at_risk
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
      totalAtRisk: Number(result.rows[0]?.total_at_risk ?? 0),
      students: result.rows.map((r) => ({
        studentId: r.student_id,
        name: r.name,
        lastCompletedAt: r.last_completed_at,
        daysSinceLast: r.days_since_last === null ? null : Number(r.days_since_last),
      })),
    };
  }

  // Org-wide only — chats.branch_id is not populated, so chat SLA is not branch-scoped (branch attribution for chats is a follow-up).
  async chatsSla(actor: ActorContext, query: { from?: string; to?: string }) {
    this.policy.assertManagerOnly(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      inbound_count: string;
      responded_count: string;
      avg_minutes: string | null;
      median_minutes: string | null;
      p90_minutes: string | null;
    }>(
      `with classified as (
         select m.id, m.chat_id, m.created_at,
                case when u.role in ('admin', 'manager', 'system_admin') then 'staff' else 'client' end as cls
           from app.messages m
           join app.chats c on c.id = m.chat_id and c.type = 'administration' and c.deleted_at is null
           left join app.users u on u.id = m.sender_id and u.deleted_at is null
          where m.deleted_at is null
            and m.message_type <> 'system'
            and m.sender_id is not null
       ),
       seq as (
         select chat_id, created_at, cls,
                lag(cls) over (partition by chat_id order by created_at, id) as prev_cls
           from classified
       ),
       inbound as (
         select chat_id, created_at as inbound_at
           from seq
          where cls = 'client'
            and (prev_cls is null or prev_cls = 'staff')
            and created_at >= $1::timestamptz and created_at < $2::timestamptz
       ),
       gaps as (
         select extract(epoch from (resp.response_at - i.inbound_at)) / 60.0 as minutes
           from inbound i
           cross join lateral (
             select min(s.created_at) as response_at
               from classified s
              where s.chat_id = i.chat_id and s.cls = 'staff' and s.created_at > i.inbound_at
           ) resp
          where resp.response_at is not null
       )
       select
         (select count(*) from inbound) as inbound_count,
         (select count(*) from gaps) as responded_count,
         coalesce(avg(minutes), 0) as avg_minutes,
         coalesce(percentile_cont(0.5) within group (order by minutes), 0) as median_minutes,
         coalesce(percentile_cont(0.9) within group (order by minutes), 0) as p90_minutes
       from gaps`,
      [from, to],
    );
    const row = result.rows[0];
    const inboundCount = Number(row?.inbound_count ?? 0);
    const respondedCount = Number(row?.responded_count ?? 0);
    const round1 = (v: string | null) => Math.round(Number(v ?? 0) * 10) / 10;
    return {
      from,
      to,
      inboundCount,
      respondedCount,
      responseRate: inboundCount === 0 ? 0 : Math.round((respondedCount / inboundCount) * 100) / 100,
      avgMinutes: round1(row?.avg_minutes ?? null),
      medianMinutes: round1(row?.median_minutes ?? null),
      p90Minutes: round1(row?.p90_minutes ?? null),
    };
  }

  async weeklyReport(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertManagerOnly(actor);
    const to = new Date().toISOString();
    const from = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const branchId = query.branchId;
    const dated = { from, to, branchId };

    const settle = <T>(r: PromiseSettledResult<T>): T | { error: string } =>
      r.status === "fulfilled"
        ? r.value
        : { error: r.reason instanceof Error ? r.reason.message : String(r.reason) };

    const [funnelR, debtsR, forecastR, churnR, branchesR, lossR, slaR] = await Promise.allSettled([
      this.funnel(actor, dated),
      this.debts(actor, { branchId }),
      this.revenueForecast(actor, { branchId }),
      this.churnRisk(actor, { branchId }),
      this.branchComparison(actor, { from, to }),
      this.lossReasons(actor, dated),
      this.chatsSla(actor, { from, to }),
    ]);

    const churn =
      churnR.status === "fulfilled"
        ? { inactiveDays: churnR.value.inactiveDays, totalAtRisk: churnR.value.totalAtRisk }
        : { error: churnR.reason instanceof Error ? churnR.reason.message : String(churnR.reason) };

    return {
      window: { from, to },
      funnel: settle(funnelR),
      debts: settle(debtsR),
      forecast: settle(forecastR),
      churn,
      branches: settle(branchesR),
      lossReasons: settle(lossR),
      chatSla: settle(slaR),
    };
  }

  async dataQuality(actor: ActorContext, query: { branchId?: string }) {
    this.policy.assertManagerOnly(actor);
    const branchOf = (a: string) =>
      `coalesce(${a}.branch_id::text, ${a}.custom_data->>'branchId', ${a}.custom_data->>'branch_id')`;

    const leadsResult = await this.database.query<{
      total: string;
      missing_phone: string;
      missing_branch: string;
    }>(
      `select count(*) as total,
              count(*) filter (where l.phone_normalized is null or btrim(l.phone_normalized) = '') as missing_phone,
              count(*) filter (where l.branch_id is null) as missing_branch
         from app.leads l
        where l.deleted_at is null
          and ($1::uuid is null or l.branch_id = $1::uuid)`,
      [query.branchId ?? null],
    );

    const studentsResult = await this.database.query<{
      total: string;
      missing_branch: string;
      missing_discipline: string;
    }>(
      `select count(*) as total,
              count(*) filter (where ${branchOf("s")} is null) as missing_branch,
              count(*) filter (
                where not exists (
                  select 1 from app.student_disciplines sd
                   where sd.student_id = s.id and sd.deleted_at is null
                )
              ) as missing_discipline
         from app.students s
        where s.deleted_at is null
          and ($1::uuid is null or ${branchOf("s")} = $1::text)`,
      [query.branchId ?? null],
    );

    const l = leadsResult.rows[0];
    const st = studentsResult.rows[0];
    return {
      leads: {
        total: Number(l?.total ?? 0),
        missingPhone: Number(l?.missing_phone ?? 0),
        missingBranch: Number(l?.missing_branch ?? 0),
      },
      students: {
        total: Number(st?.total ?? 0),
        missingBranch: Number(st?.missing_branch ?? 0),
        missingDiscipline: Number(st?.missing_discipline ?? 0),
      },
    };
  }

  async responsibleDistribution(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertManagerOnly(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      user_id: string;
      name: string | null;
      leads: string;
    }>(
      `select l.assigned_to as user_id,
              u.full_name as name,
              count(*) as leads
         from app.leads l
         left join app.users u on u.id = l.assigned_to and u.deleted_at is null
        where l.deleted_at is null
          and l.assigned_to is not null
          and l.created_at >= $1::timestamptz
          and l.created_at < $2::timestamptz
          and ($3::uuid is null or l.branch_id = $3::uuid)
        group by l.assigned_to, u.full_name
        order by leads desc, u.full_name`,
      [from, to, query.branchId ?? null],
    );
    const unassignedResult = await this.database.query<{ unassigned: string }>(
      `select count(*) as unassigned
         from app.leads l
        where l.deleted_at is null
          and l.assigned_to is null
          and l.created_at >= $1::timestamptz
          and l.created_at < $2::timestamptz
          and ($3::uuid is null or l.branch_id = $3::uuid)`,
      [from, to, query.branchId ?? null],
    );
    return {
      from,
      to,
      responsibles: result.rows.map((r) => ({
        userId: r.user_id,
        name: r.name ?? "—",
        leads: Number(r.leads),
      })),
      unassignedLeads: Number(unassignedResult.rows[0]?.unassigned ?? 0),
    };
  }

  async sourceAnalytics(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertManagerOnly(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      source: string | null;
      display_name: string | null;
      leads: string;
    }>(
      `select l.source,
              max(ls.display_name) as display_name,
              count(*) as leads
         from app.leads l
         left join app.lead_sources ls
           on ls.deleted_at is null
          and (lower(ls.canonical_name) = lower(l.source) or lower(ls.display_name) = lower(l.source))
        where l.deleted_at is null
          and l.created_at >= $1::timestamptz
          and l.created_at < $2::timestamptz
          and ($3::uuid is null or l.branch_id = $3::uuid)
        group by l.source
        order by leads desc, l.source nulls last`,
      [from, to, query.branchId ?? null],
    );
    const total = result.rows.reduce((n, r) => n + Number(r.leads), 0);
    return {
      from,
      to,
      total,
      sources: result.rows.map((r) => {
        const leads = Number(r.leads);
        return {
          source: r.source,
          displayName: r.display_name ?? (r.source || "(не указан)"),
          leads,
          share: total === 0 ? 0 : Math.round((leads / total) * 100),
        };
      }),
    };
  }

  // Shared header + row data for the finance-monthly exports (CSV and XLSX),
  // so both formats serialize the exact same columns from the same query.
  private static readonly FINANCE_MONTHLY_HEADER = [
    "month_start",
    "lessons",
    "completed_lessons",
    "revenue",
    "expenses",
    "new_students",
  ];

  private async financeMonthlyRows(
    actor: ActorContext,
    query: { from?: string; to?: string },
  ): Promise<(string | number)[][]> {
    const { items } = await this.financeMonthly(actor, query);
    return items.map((i) => [
      i.monthStart,
      i.lessons,
      i.completedLessons,
      i.revenue,
      i.expenses,
      i.newStudents,
    ]);
  }

  async financeMonthlyCsv(actor: ActorContext, query: { from?: string; to?: string }): Promise<string> {
    const rows = await this.financeMonthlyRows(actor, query);
    await this.audit.record({
      actor,
      action: "analytics.finance_exported",
      entityType: "report",
      metadata: { format: "csv", from: query.from ?? null, to: query.to ?? null },
    });
    const header = AnalyticsService.FINANCE_MONTHLY_HEADER.join(",");
    const escape = (v: unknown) => {
      const s = String(v ?? "");
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const lines = rows.map((cells) => cells.map(escape).join(","));
    return [header, ...lines].join("\n") + "\n";
  }

  // Dependency-free SpreadsheetML 2003 (XML) workbook. Excel opens this natively
  // when served as application/vnd.ms-excel with an .xls filename — no exceljs needed.
  async financeMonthlyXlsx(actor: ActorContext, query: { from?: string; to?: string }): Promise<string> {
    const rows = await this.financeMonthlyRows(actor, query);
    await this.audit.record({
      actor,
      action: "analytics.finance_exported",
      entityType: "report",
      metadata: { format: "xlsx", from: query.from ?? null, to: query.to ?? null },
    });
    const escapeXml = (v: unknown) =>
      String(v ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&apos;");
    const cell = (v: string | number) => {
      const type = typeof v === "number" ? "Number" : "String";
      return `<Cell><Data ss:Type="${type}">${escapeXml(v)}</Data></Cell>`;
    };
    const rowXml = (cells: (string | number)[]) => `<Row>${cells.map(cell).join("")}</Row>`;
    const headerRow = rowXml(AnalyticsService.FINANCE_MONTHLY_HEADER);
    const dataRows = rows.map(rowXml).join("");
    return (
      `<?xml version="1.0" encoding="UTF-8"?>` +
      `<?mso-application progid="Excel.Sheet"?>` +
      `<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"` +
      ` xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">` +
      `<Worksheet ss:Name="Finance Monthly"><Table>${headerRow}${dataRows}</Table></Worksheet>` +
      `</Workbook>`
    );
  }
}
