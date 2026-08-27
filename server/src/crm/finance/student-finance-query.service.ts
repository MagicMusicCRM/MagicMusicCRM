import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { CrmListQuery } from "../dto/crm-list.query";
import { StudentBalanceQuery } from "../dto/student-balance.query";
import { findStudent } from "../student-read";
import {
  ExpectedPaymentRow,
  LedgerRow,
  LedgerRowWithTotals,
  StudentBalanceRow,
} from "./finance.types";

@Injectable()
export class StudentFinanceQueryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  private toExpectedPaymentDto(row: ExpectedPaymentRow) {
    return {
      id: row.id,
      studentId: row.student_id,
      studentName:
        `${row.student_first_name ?? ""} ${row.student_last_name ?? ""}`.trim() ||
        null,
      amount: Number(row.amount),
      dueDate: row.due_date,
      status: row.status,
      description: row.description,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private toStudentBalanceDto(row: StudentBalanceRow) {
    return {
      studentId: row.student_id,
      balance: Number(row.balance),
      totalPaid: Number(row.total_paid),
      totalCost: Number(row.total_cost),
      totalAdjustments: Number(row.total_adjustments ?? 0),
      updatedAt: row.updated_at,
      student: {
        firstName: row.first_name,
        lastName: row.last_name,
        phone: row.phone,
      },
    };
  }

  async listExpectedPayments(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadSchoolFinance(actor);
    if (!query.studentId) {
      throw new BadRequestException("studentId обязателен.");
    }
    const student = await findStudent(this.database, query.studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });

    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<ExpectedPaymentRow>(
      `
        select ep.id, ep.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name,
          ep.amount, ep.due_date, ep.status, ep.description,
          ep.created_at, ep.updated_at
        from app.expected_payments ep
        join app.students s on s.id = ep.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where ep.student_id = $1
        order by ep.due_date desc nulls last, ep.created_at desc, ep.id desc
        limit $2
      `,
      [query.studentId, limit],
    );

    return { items: result.rows.map((row) => this.toExpectedPaymentDto(row)) };
  }

  async listStudentBalances(actor: ActorContext, query: StudentBalanceQuery) {
    this.policy.assertCanReadSchoolFinance(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<StudentBalanceRow>(
      `
        with lesson_costs as (
          select
            -- A charged subscription can belong to a family member (or an
            -- explicitly selected third-party payer). Attribute the expense to
            -- the same personal account that received the subscription payment.
            coalesce(sub.student_id, l.student_id, lp.student_id) as student_id,
            sum(
              coalesce(
                -- The issuance payment is the immutable sale-price snapshot.
                -- Package price is a fallback for imported/voided payments.
                -- charged_hours is the exact amount reconciled against this
                -- subscription, including duration and partial attendance.
                coalesce(sub_pay.amount, pkg.price)
                  / nullif(sub.lessons_total, 0)
                  * lp.charged_hours,
                -- Legacy completed lessons may have no linked subscription.
                -- Preserve their established group/custom-price behaviour.
                coalesce(
                  g.price_per_lesson,
                  case
                    when s.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                      then (s.custom_data->>'individualPrice')::numeric
                    when s.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                      then (s.custom_data->>'individual_price')::numeric
                    else null
                  end,
                  0
                )
                * case
                    when lp.id is null then 1
                    when lp.attendance_kind in ('attended', 'paid_miss') then 1
                    when lp.attendance_kind = 'partially_paid'
                      then lp.charge_share
                    else 0
                  end
              )
            ) as total_cost,
            max(l.updated_at) as updated_at
          from app.lessons l
          left join app.lesson_participation lp on lp.lesson_id = l.id
          join app.students s on s.id = coalesce(l.student_id, lp.student_id)
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          left join app.subscriptions sub on sub.id = lp.subscription_id
          left join app.subscription_packages pkg on pkg.id = sub.package_id
          left join app.commerce_ordinary_payments sub_pay
            on sub_pay.id = sub.payment_id
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and l.is_trial = false
            and coalesce(l.student_id, lp.student_id) is not null
          group by coalesce(sub.student_id, l.student_id, lp.student_id)
        ),
        payment_totals as (
          select
            p.student_id,
            sum(p.amount) as total_paid,
            max(coalesce(p.created_at, p.payment_date)) as updated_at
          from app.commerce_ordinary_payments p
          where p.deleted_at is null
          group by p.student_id
        ),
        adjustment_totals as (
          select
            adj.student_id,
            sum(adj.amount) as total_adjustments,
            max(adj.occurred_at) as updated_at
          from app.commerce_ordinary_account_adjustments adj
          -- Отменённая (status='void') запись не деньги: без этого условия
          -- сторнирование не меняло бы баланс, и отмена ничего бы не отменяла.
          where adj.deleted_at is null and adj.status <> 'void'
          group by adj.student_id
        ),
        balances as (
          select
            s.id as student_id,
            profile.first_name,
            profile.last_name,
            profile.phone,
            coalesce(pay.total_paid, 0) as total_paid,
            coalesce(cost.total_cost, 0) as total_cost,
            coalesce(adj.total_adjustments, 0) as total_adjustments,
            coalesce(pay.total_paid, 0) - coalesce(cost.total_cost, 0)
              + coalesce(adj.total_adjustments, 0) as balance,
            greatest(
              coalesce(pay.updated_at, 'epoch'::timestamptz),
              coalesce(cost.updated_at, 'epoch'::timestamptz),
              coalesce(adj.updated_at, 'epoch'::timestamptz),
              s.updated_at
            ) as updated_at
          from app.students s
          left join app.profiles profile on profile.id = s.profile_id and profile.deleted_at is null
          left join payment_totals pay on pay.student_id = s.id
          left join lesson_costs cost on cost.student_id = s.id
          left join adjustment_totals adj on adj.student_id = s.id
          where s.deleted_at is null
            and ($1::uuid is null or s.id = $1)
        )
        select *
        from balances
        where ($2::boolean = false or balance < 0)
        order by balance asc, updated_at desc
        limit $3
      `,
      [query.studentId ?? null, query.debtOnly === true, limit],
    );
    return { items: result.rows.map((row) => this.toStudentBalanceDto(row)) };
  }

  async listStudentLedger(
    actor: ActorContext,
    studentId: string,
    query: { direction?: string; limit?: number },
  ) {
    this.policy.assertCanReadStudentFinance(actor);
    const limit = Math.min(query.limit ?? 100, 300);
    const direction =
      query.direction === "income" || query.direction === "outcome"
        ? query.direction
        : null;
    const result = await this.database.query<LedgerRow>(
      `
        with ledger as (
          select p.id, 'payment' as kind, p.amount as amount,
            p.notes as description, p.method,
            b.name as branch_name,
            author.first_name as author_first_name,
            author.last_name as author_last_name,
            coalesce(p.payment_date, p.created_at) as occurred_at,
            p.invoice_number,
            -- Платёж существует только когда он получен.
            'paid'::text as status,
            false as editable
          from app.commerce_ordinary_payments p
          left join app.students st on st.id = p.student_id
          left join app.branches b on b.id = st.branch_id
          left join app.users u on u.id = p.created_by and u.deleted_at is null
          left join app.profiles author on author.user_id = u.id and author.deleted_at is null
          where p.deleted_at is null and p.student_id = $1

          union all

          select l.id, 'lesson_charge' as kind,
            -(
              coalesce(
                coalesce(sub_pay.amount, pkg.price)
                  / nullif(sub.lessons_total, 0)
                  * lp.charged_hours,
                coalesce(
                  g.price_per_lesson,
                  case
                    when s.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                      then (s.custom_data->>'individualPrice')::numeric
                    when s.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                      then (s.custom_data->>'individual_price')::numeric
                    else null
                  end,
                  0
                )
                * case
                    when lp.id is null then 1
                    when lp.attendance_kind in ('attended', 'paid_miss') then 1
                    when lp.attendance_kind = 'partially_paid'
                      then lp.charge_share
                    else 0
                  end
              )
            ) as amount,
            trim(concat('Занятие', ' ', coalesce(g.name, 'индивидуально'))) as description,
            null as method,
            b.name as branch_name,
            null as author_first_name,
            null as author_last_name,
            l.scheduled_at as occurred_at,
            null::text as invoice_number,
            -- Списание за проведённое занятие — свершившийся факт; правят его
            -- через статус посещаемости, а не строкой личного счёта.
            'paid'::text as status,
            false as editable
          from app.lessons l
          left join app.lesson_participation lp on lp.lesson_id = l.id
          join app.students s on s.id = coalesce(l.student_id, lp.student_id)
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          left join app.subscriptions sub on sub.id = lp.subscription_id
          left join app.subscription_packages pkg on pkg.id = sub.package_id
          left join app.commerce_ordinary_payments sub_pay
            on sub_pay.id = sub.payment_id
          left join app.branches b on b.id = l.branch_id
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and l.is_trial = false
            and coalesce(sub.student_id, l.student_id, lp.student_id) = $1

          union all

          select adj.id, adj.kind,
            -- Сумма остаётся настоящей: отменённая строка должна найтись в той
            -- же вкладке «Приход»/«Расход», где её оставили, и быть видимой как
            -- зачёркнутая. Из ИТОГОВ она исключается ниже.
            adj.amount,
            adj.description, adj.method,
            b.name as branch_name,
            author.first_name as author_first_name,
            author.last_name as author_last_name,
            adj.occurred_at,
            adj.invoice_number,
            adj.status,
            true as editable
          from app.commerce_ordinary_account_adjustments adj
          left join app.branches b on b.id = adj.branch_id
          left join app.users u on u.id = adj.created_by and u.deleted_at is null
          left join app.profiles author on author.user_id = u.id and author.deleted_at is null
          where adj.deleted_at is null and adj.student_id = $1
        )
        select *,
          -- Отменённые записи в итоги не входят — иначе «Приход − Расход»
          -- перестанет сходиться с балансом, который видит клиент.
          sum(case when status <> 'void' and amount > 0 then amount else 0 end)
            over () as income_total,
          sum(case when status <> 'void' and amount < 0 then -amount else 0 end)
            over () as outcome_total
        from ledger
        where ($2::text is null
          or ($2 = 'income' and amount > 0)
          or ($2 = 'outcome' and amount < 0))
        order by occurred_at desc, id desc
        limit $3
      `,
      [studentId, direction, limit],
    );
    const first = result.rows[0] as LedgerRowWithTotals | undefined;
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        kind: row.kind,
        amount: Number(row.amount),
        description: row.description,
        method: row.method,
        branchName: row.branch_name,
        authorName:
          [row.author_first_name, row.author_last_name]
            .filter(Boolean)
            .join(" ") || null,
        occurredAt: row.occurred_at,
        invoiceNumber: row.invoice_number,
        status: row.status,
        editable: row.editable,
      })),
      incomeTotal: Number(first?.income_total ?? 0),
      outcomeTotal: Number(first?.outcome_total ?? 0),
    };
  }
}
