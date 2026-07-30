import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CrmPolicy } from "../crm/crm.policy";
import { DatabaseService } from "../db/database.service";
import { AnalyticsRangeQuery } from "./dto/analytics-range.query";
import { ReportingEntityLink } from "./client-status-read.service";

interface LessonSuccessRow {
  total_lessons: string;
  successful_lessons: string;
}

interface SchoolFinanceRow {
  month_start: string;
  total_lessons: string;
  successful_lessons: string;
  revenue_minor: string;
  expenses_minor: string;
}

@Injectable()
export class ReportingReadService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  async lessonSuccess(actor: ActorContext, query: AnalyticsRangeQuery) {
    this.assertCanReadStatusReport(actor);
    const range = this.normalizeRange(query);
    const result = await this.database.query<LessonSuccessRow>(
      `
        select
          count(*)::text as total_lessons,
          count(*) filter (
            where lesson.lifecycle_state = 'successfully_completed'
          )::text as successful_lessons
        from app.lessons lesson
        where lesson.deleted_at is null
          and lesson.scheduled_at >= $1::timestamptz
          and lesson.scheduled_at < $2::timestamptz
          and ($3::uuid is null or lesson.branch_id = $3)
          and (
            $4::text in ('director', 'system_admin')
            or (
              $4::text = 'manager'
              and lesson.branch_id is not null
              and exists (
                select 1
                from app.staff_members scoped_staff
                join app.profiles scoped_profile
                  on scoped_profile.id = scoped_staff.profile_id
                 and scoped_profile.deleted_at is null
                join app.staff_branch_assignments scoped_assignment
                  on scoped_assignment.staff_member_id = scoped_staff.id
                 and scoped_assignment.deleted_at is null
                where scoped_staff.deleted_at is null
                  and scoped_profile.user_id = $5
                  and scoped_assignment.branch_id = lesson.branch_id
              )
            )
          )
      `,
      [range.from, range.to, query.branchId ?? null, actor.role, actor.userId],
    );
    const totalLessons = Number(result.rows[0]?.total_lessons ?? 0);
    const successfulLessons = Number(
      result.rows[0]?.successful_lessons ?? 0,
    );
    return {
      ...range,
      branchId: query.branchId ?? null,
      totalLessons,
      successfulLessons,
      successRate:
        totalLessons === 0 ? 0 : successfulLessons / totalLessons,
      drilldown: {
        entityType: "lesson_list",
        entityId: "successfully_completed",
        optionalFocus: {
          filter: {
            version: 1,
            status: "successfully_completed",
            branchId: query.branchId,
            from: range.from,
            to: range.to,
          },
        },
      } satisfies ReportingEntityLink,
    };
  }

  async schoolFinance(actor: ActorContext, query: AnalyticsRangeQuery) {
    this.policy.assertCanReadSchoolFinance(actor);
    const range = this.normalizeRange(query);
    const result = await this.database.query<SchoolFinanceRow>(
      `
        with months as (
          select generate_series(
            date_trunc('month', $1::timestamptz),
            date_trunc('month', $2::timestamptz - interval '1 microsecond'),
            interval '1 month'
          ) as month_start
        ),
        lesson_facts as (
          select
            date_trunc('month', lesson.scheduled_at) as month_start,
            count(*)::bigint as total_lessons,
            count(*) filter (
              where lesson.lifecycle_state = 'successfully_completed'
            )::bigint as successful_lessons
          from app.lessons lesson
          where lesson.deleted_at is null
            and lesson.scheduled_at >= $1::timestamptz
            and lesson.scheduled_at < $2::timestamptz
            and ($3::uuid is null or lesson.branch_id = $3)
          group by date_trunc('month', lesson.scheduled_at)
        ),
        actual_payment_facts as (
          select
            date_trunc('month', payment.payment_date) as month_start,
            coalesce(sum(payment.amount_minor), 0)::bigint as revenue_minor
          from app.payments payment
          where payment.deleted_at is null
            and payment.payment_date >= $1::timestamptz
            and payment.payment_date < $2::timestamptz
            and ($3::uuid is null or payment.branch_id = $3)
          group by date_trunc('month', payment.payment_date)
        ),
        expense_facts as (
          select
            date_trunc('month', expense.created_at) as month_start,
            round(coalesce(sum(expense.amount), 0) * 100)::bigint
              as expenses_minor
          from app.expenses expense
          where expense.deleted_at is null
            and expense.created_at >= $1::timestamptz
            and expense.created_at < $2::timestamptz
            and ($3::uuid is null or expense.branch_id = $3)
          group by date_trunc('month', expense.created_at)
        )
        select
          to_char(months.month_start, 'YYYY-MM-DD') as month_start,
          coalesce(lesson_facts.total_lessons, 0)::text as total_lessons,
          coalesce(lesson_facts.successful_lessons, 0)::text
            as successful_lessons,
          coalesce(actual_payment_facts.revenue_minor, 0)::text
            as revenue_minor,
          coalesce(expense_facts.expenses_minor, 0)::text as expenses_minor
        from months
        left join lesson_facts using (month_start)
        left join actual_payment_facts using (month_start)
        left join expense_facts using (month_start)
        order by months.month_start
      `,
      [range.from, range.to, query.branchId ?? null],
    );
    const rows = result.rows.map((row) => ({
      monthStart: row.month_start,
      totalLessons: Number(row.total_lessons),
      successfulLessons: Number(row.successful_lessons),
      revenueMinor: row.revenue_minor,
      expensesMinor: row.expenses_minor,
      link: {
        entityType: "school_finance_month",
        entityId: row.month_start,
        optionalFocus: {
          filter: {
            version: 1,
            branchId: query.branchId,
            from: `${row.month_start}T00:00:00.000Z`,
          },
        },
      } satisfies ReportingEntityLink,
    }));
    return {
      ...range,
      branchId: query.branchId ?? null,
      currencyCode: "RUB",
      revenueMinor: rows
        .reduce((sum, row) => sum + BigInt(row.revenueMinor), 0n)
        .toString(),
      expensesMinor: rows
        .reduce((sum, row) => sum + BigInt(row.expensesMinor), 0n)
        .toString(),
      rows,
    };
  }

  private assertCanReadStatusReport(actor: ActorContext): void {
    if (
      actor.role === "manager" ||
      actor.role === "director" ||
      actor.role === "system_admin"
    ) {
      return;
    }
    throw new ForbiddenException({
      code: "REPORT_STATUS_SCOPE_DENIED",
      message: "Lesson reporting is not available for this actor.",
    });
  }

  private normalizeRange(query: AnalyticsRangeQuery) {
    const now = new Date();
    const to = query.to ? new Date(query.to) : now;
    const from = query.from
      ? new Date(query.from)
      : new Date(
          Date.UTC(
            to.getUTCFullYear(),
            to.getUTCMonth() - 5,
            1,
            0,
            0,
            0,
            0,
          ),
        );
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
    return { from: from.toISOString(), to: to.toISOString() };
  }
}

