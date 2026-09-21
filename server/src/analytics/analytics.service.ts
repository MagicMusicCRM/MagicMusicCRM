import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { DashboardService } from "../crm/dashboard.service";
import { CrmPolicy } from "../crm/crm.policy";
import {
  branchIdExpr,
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../crm/branch-scope";
import { SalesClientsReadService } from "./sales-clients-read.service";

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly dashboard_: DashboardService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
    private readonly salesClients?: SalesClientsReadService,
  ) {}

  overview(actor: ActorContext) {
    return this.dashboard_.getOverview(actor);
  }

  dashboard(actor: ActorContext, query: Parameters<DashboardService["getManagerDashboard"]>[1]) {
    return this.dashboard_.getManagerDashboard(actor, query);
  }

  async financeMonthly(actor: ActorContext, query: { from?: string; to?: string }) {
    // KVA-239: помесячные финансы школы — только director/system_admin
    // (закрывает и CSV/XLSX-экспорт через financeMonthlyRows).
    this.policy.assertCanReadSchoolFinance(actor);
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
    if (!this.salesClients) {
      throw new Error("SalesClientsReadService is required for cohort funnel analytics.");
    }
    const summary = await this.salesClients.summary(actor, {
      from,
      to,
      branchId: query.branchId,
    });
    const inquiries = summary.funnel.inquiries;
    const cohortRatio = (value: number) =>
      inquiries === 0 ? 0 : Math.round((value / inquiries) * 100);
    const stages = [
      {
        statusId: "inquiry",
        name: "Обращения",
        sortOrder: 0,
        leadsEntered: inquiries,
        ratioToPrevStage: null,
      },
      {
        statusId: "trial_booked",
        name: "Записаны на пробное",
        sortOrder: 1,
        leadsEntered: summary.funnel.trialBooked,
        ratioToPrevStage: cohortRatio(summary.funnel.trialBooked),
      },
      {
        statusId: "trial_attended",
        name: "Посетили пробное",
        sortOrder: 2,
        leadsEntered: summary.funnel.trialAttended,
        ratioToPrevStage: cohortRatio(summary.funnel.trialAttended),
      },
      {
        statusId: "first_paid",
        name: "Первая фактическая оплата",
        sortOrder: 3,
        leadsEntered: summary.funnel.firstPaidSales,
        ratioToPrevStage: cohortRatio(summary.funnel.firstPaidSales),
      },
    ];
    return {
      from,
      to,
      observationDays: summary.observationDays,
      ratioDefinition: "cohort_share",
      stages,
    };
  }

  async branchComparison(actor: ActorContext, query: { from?: string; to?: string }) {
    // KVA-239: выручка по филиалам — общешкольные финансы.
    this.policy.assertCanReadSchoolFinance(actor);
    const { from, to } = this.rangeBounds(query);
    const result = await this.database.query<{
      branch_id: string;
      name: string;
      revenue: string;
      active_students: string;
      new_leads: string;
      completed_lessons: string;
    }>(
      `select b.id as branch_id, b.name,
         (select coalesce(sum(p.amount), 0) from app.commerce_ordinary_payments p
            join app.students s on s.id = p.student_id and s.deleted_at is null
           where p.deleted_at is null and p.payment_date >= $1::timestamptz and p.payment_date < $2::timestamptz
             and ${branchIdExpr("s")} = b.id::text) as revenue,
         (select count(*) from app.students s
           where s.deleted_at is null and s.status = 'active' and ${branchIdExpr("s")} = b.id::text) as active_students,
         (select count(*) from app.leads l
           where l.deleted_at is null and l.created_at >= $1::timestamptz and l.created_at < $2::timestamptz
             and ${branchIdExpr("l")} = b.id::text) as new_leads,
         (select count(*) from app.lessons les
           where les.deleted_at is null
             and les.lifecycle_state = 'successfully_completed'
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
      `select lr.id as reason_id,
              coalesce(lsh.reason_name_snapshot, lr.name) as name,
              coalesce(lsh.reason_kind_snapshot, lr.kind) as kind,
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
        group by lr.id,
          coalesce(lsh.reason_name_snapshot, lr.name),
          coalesce(lsh.reason_kind_snapshot, lr.kind)
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
    // KVA-239: суммы долгов по школе — общешкольные финансы.
    this.policy.assertCanReadSchoolFinance(actor);
    const result = await this.database.query<{ bucket: string; students: string; amount: string }>(
      `select
         case
           when timezone('Europe/Moscow', now())::date
             - timezone('Europe/Moscow', receivable.due_at)::date between 0 and 7 then '0-7'
           when timezone('Europe/Moscow', now())::date
             - timezone('Europe/Moscow', receivable.due_at)::date between 8 and 14 then '8-14'
           when timezone('Europe/Moscow', now())::date
             - timezone('Europe/Moscow', receivable.due_at)::date between 15 and 30 then '15-30'
           else '30+'
         end as bucket,
         count(distinct receivable.student_id) as students,
         coalesce(sum(receivable.amount_minor), 0)::numeric / 100 as amount
       from app.commerce_receivable_schedule_projection receivable
       join app.students s
         on s.id = receivable.student_id and s.deleted_at is null
      where receivable.status = 'unpaid'
        and timezone('Europe/Moscow', receivable.due_at)::date
          <= timezone('Europe/Moscow', now())::date
        and ($1::uuid is null or ${branchIdExpr("s")} = $1::text)
      group by 1`,
      [query.branchId ?? null],
    );
    const distinctResult = await this.database.query<{ distinct_students: string }>(
      `select count(distinct receivable.student_id) as distinct_students
         from app.commerce_receivable_schedule_projection receivable
         join app.students s
           on s.id = receivable.student_id and s.deleted_at is null
        where receivable.status = 'unpaid'
          and timezone('Europe/Moscow', receivable.due_at)::date
            <= timezone('Europe/Moscow', now())::date
          and ($1::uuid is null or ${branchIdExpr("s")} = $1::text)`,
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
    // KVA-239: прогноз выручки — общешкольные финансы.
    this.policy.assertCanReadSchoolFinance(actor);
    const result = await this.database.query<{ next7: string; next14: string; next30: string }>(
      `select
         coalesce(sum(receivable.amount_minor) filter (
           where timezone('Europe/Moscow', receivable.due_at)::date
             between timezone('Europe/Moscow', now())::date
             and timezone('Europe/Moscow', now())::date + 7
         ), 0)::numeric / 100 as next7,
         coalesce(sum(receivable.amount_minor) filter (
           where timezone('Europe/Moscow', receivable.due_at)::date
             between timezone('Europe/Moscow', now())::date
             and timezone('Europe/Moscow', now())::date + 14
         ), 0)::numeric / 100 as next14,
         coalesce(sum(receivable.amount_minor) filter (
           where timezone('Europe/Moscow', receivable.due_at)::date
             between timezone('Europe/Moscow', now())::date
             and timezone('Europe/Moscow', now())::date + 30
         ), 0)::numeric / 100 as next30
       from app.commerce_receivable_schedule_projection receivable
       join app.students s
         on s.id = receivable.student_id and s.deleted_at is null
      where receivable.status in ('scheduled', 'unpaid', 'posted_pending')
        and ($1::uuid is null or ${branchIdExpr("s")} = $1::text)`,
      [query.branchId ?? null],
    );
    const row = result.rows[0];
    return { next7: Number(row?.next7 ?? 0), next14: Number(row?.next14 ?? 0), next30: Number(row?.next30 ?? 0) };
  }

  async churnRisk(actor: ActorContext, query: { inactiveDays?: number | string; branchId?: string }) {
    this.policy.assertManagerOnly(actor);
    const inactiveDays = Number(query.inactiveDays ?? 21);
    const actorRole = currentActorRoleSql("$3");
    const scope = managerBranchScopeSql({
      roleExpression: actorRole,
      userIdExpression: "$3",
      branchExpression: branchIdExpr("s"),
    });
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
            and l.lifecycle_state = 'successfully_completed'
            and coalesce(l.student_id, lp.student_id) is not null
            and (lp.id is null or lp.status not in ('absent', 'missed', 'no_show'))
          group by coalesce(l.student_id, lp.student_id)
       ), future_lesson as (
         select distinct coalesce(l.student_id, lp.student_id) as student_id
           from app.lessons l
           left join app.lesson_participation lp on lp.lesson_id = l.id
          where l.deleted_at is null
            and l.successor_id is null
            and l.lifecycle_state in ('scheduled', 'settlement_pending')
            and l.scheduled_at >= now()
            and coalesce(l.student_id, lp.student_id) is not null
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
         left join future_lesson fl on fl.student_id = s.id
        where s.deleted_at is null and s.status = 'active'
          and ($2::uuid is null or ${branchIdExpr("s")} = $2::text)
          and ${scope}
          and fl.student_id is null
          and (
            ll.last_completed_at < now() - make_interval(days => $1::int)
            or (
              ll.last_completed_at is null
              and s.created_at < now() - make_interval(days => $1::int)
            )
          )
        order by ll.last_completed_at asc nulls first
        limit 200`,
      [inactiveDays, query.branchId ?? null, actor.userId],
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

  async chatsSla(actor: ActorContext, query: { from?: string; to?: string; branchId?: string }) {
    this.policy.assertManagerOnly(actor);
    const { from, to } = this.rangeBounds(query);
    const actorRole = currentActorRoleSql("$4");
    const scope = managerBranchScopeSql({
      roleExpression: actorRole,
      userIdExpression: "$4",
      branchExpression: "chat_context.branch_id",
    });
    const result = await this.database.query<{
      inbound_count: string;
      responded_count: string;
      avg_minutes: string | null;
      median_minutes: string | null;
      p90_minutes: string | null;
      slow_chats: Array<{
        chatId: string;
        clientName: string;
        inboundAt: string;
        responseAt: string;
        minutes: number;
      }> | null;
    }>(
      `with chat_context as (
         select c.id, c.owner_user_id,
                coalesce(
                  c.branch_id::text,
                  ${branchIdExpr("chat_student")},
                  ${branchIdExpr("chat_lead")},
                  linked.branch_id
                ) as branch_id
           from app.chats c
           left join app.students chat_student
             on chat_student.id = c.student_id
            and chat_student.deleted_at is null
           left join app.leads chat_lead
             on chat_lead.id = c.lead_id
            and chat_lead.deleted_at is null
           left join lateral (
             select case
                      when link.entity_type = 'student'
                        then ${branchIdExpr("linked_student")}
                      when link.entity_type = 'lead'
                        then ${branchIdExpr("linked_lead")}
                      else null
                    end as branch_id
               from app.user_crm_links link
               left join app.students linked_student
                 on linked_student.id = link.entity_id
                and link.entity_type = 'student'
                and linked_student.deleted_at is null
               left join app.leads linked_lead
                 on linked_lead.id = link.entity_id
                and link.entity_type = 'lead'
                and linked_lead.deleted_at is null
              where link.user_id = c.owner_user_id
                and link.deleted_at is null
              order by (link.entity_type = 'student') desc, link.created_at desc
              limit 1
           ) linked on true
          where c.type = 'administration' and c.deleted_at is null
       ), classified as (
         select m.id, m.chat_id, m.created_at,
                case when u.role in ('admin', 'manager', 'director', 'system_admin') then 'staff' else 'client' end as cls
           from app.messages m
           join chat_context on chat_context.id = m.chat_id
           left join app.users u on u.id = m.sender_id and u.deleted_at is null
          where m.deleted_at is null
            and m.message_type <> 'system'
            and m.sender_id is not null
            and ($3::uuid is null or chat_context.branch_id = $3::text)
            and ${scope}
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
         select i.chat_id,
                i.inbound_at,
                resp.response_at,
                extract(epoch from (resp.response_at - i.inbound_at)) / 60.0 as minutes
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
         coalesce(percentile_cont(0.9) within group (order by minutes), 0) as p90_minutes,
         coalesce((
           select jsonb_agg(
             jsonb_build_object(
               'chatId', slow.chat_id,
               'clientName', slow.client_name,
               'inboundAt', slow.inbound_at,
               'responseAt', slow.response_at,
               'minutes', round(slow.minutes::numeric, 1)
             )
             order by slow.minutes desc
           )
           from (
             select gap.chat_id,
                    gap.inbound_at,
                    gap.response_at,
                    gap.minutes,
                    coalesce(
                      nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), ''),
                      account.email,
                      'Клиент'
                    ) as client_name
               from gaps gap
               join chat_context context on context.id = gap.chat_id
               left join app.users account
                 on account.id = context.owner_user_id
                and account.deleted_at is null
               left join app.profiles profile
                 on profile.user_id = context.owner_user_id
                and profile.deleted_at is null
              order by gap.minutes desc
              limit 20
           ) slow
         ), '[]'::jsonb) as slow_chats
       from gaps`,
      [from, to, query.branchId ?? null, actor.userId],
    );
    const row = result.rows[0];
    const inboundCount = Number(row?.inbound_count ?? 0);
    const respondedCount = Number(row?.responded_count ?? 0);
    const round1 = (v: string | null) => Math.round(Number(v ?? 0) * 10) / 10;
    return {
      from,
      to,
      branchId: query.branchId ?? null,
      inboundCount,
      respondedCount,
      responseRate: inboundCount === 0 ? 0 : Math.round((respondedCount / inboundCount) * 100) / 100,
      avgMinutes: round1(row?.avg_minutes ?? null),
      medianMinutes: round1(row?.median_minutes ?? null),
      p90Minutes: round1(row?.p90_minutes ?? null),
      slowChats: Array.isArray(row?.slow_chats) ? row.slow_chats : [],
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
      this.chatsSla(actor, { from, to, branchId }),
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
              count(*) filter (where ${branchIdExpr("s")} is null) as missing_branch,
              count(*) filter (
                where not exists (
                  select 1 from app.student_disciplines sd
                   where sd.student_id = s.id and sd.deleted_at is null
                )
              ) as missing_discipline
         from app.students s
        where s.deleted_at is null
          and ($1::uuid is null or ${branchIdExpr("s")} = $1::text)`,
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
