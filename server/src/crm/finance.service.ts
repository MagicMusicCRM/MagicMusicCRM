import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CreateAdjustmentDto } from "./dto/create-adjustment.dto";
import { CreatePaymentDto } from "./dto/create-payment.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { ExpenseQuery } from "./dto/expense.query";
import { PaymentQuery } from "./dto/payment.query";
import { StudentBalanceQuery } from "./dto/student-balance.query";
import { UpdateExpenseDto } from "./dto/update-expense.dto";
import { UpsertExpenseDto } from "./dto/upsert-expense.dto";
import { CrmPolicy } from "./crm.policy";
import { audienceForStudent } from "./audience";
import { findStudent } from "./student-read";

// ponytail: PaymentRow/toPaymentDto are duplicated from CrmService, which still
// uses them in getMySummary's recentPayments. Fold into a shared mapper in B5.
interface PaymentRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  student_first_name: string | null;
  student_last_name: string | null;
  amount: string;
  currency: string;
  payment_date: Date | string;
  method: string | null;
  external_id: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: Date | string;
}

interface ExpenseRow {
  id: string;
  amount: string | number;
  category: string;
  description: string | null;
  branch_id: string | null;
  branch_name: string | null;
  created_at: Date | string;
}

interface ExpectedPaymentRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  student_first_name: string | null;
  student_last_name: string | null;
  amount: string;
  due_date: Date | string | null;
  status: string;
  description: string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

interface StudentBalanceRow {
  student_id: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  total_paid: string | number;
  total_cost: string | number;
  total_adjustments?: string | number;
  balance: string | number;
  updated_at: Date | string;
}

interface LedgerRow {
  id: string;
  kind: string;
  amount: string | number;
  description: string | null;
  method: string | null;
  branch_name: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
  occurred_at: Date | string;
}

/**
 * Finance domain, extracted from CrmService (SRP): payments (list + idempotent
 * create), expected payments, student balances, the personal-account ledger
 * (KVA-235), manual account adjustments, and school expenses (KVA-239 /
 * P5-5). Touches app.payments / app.expected_payments / app.account_adjustments
 * / app.expenses and the shared db/audit/policy/realtime collaborators plus the
 * shared findStudent / audienceForStudent reads. CrmService injects this back
 * for the student-card aggregate (payments/expected/balances).
 */
@Injectable()
export class FinanceService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  private toPaymentDto(row: PaymentRow) {
    return {
      id: row.id,
      studentId: row.student_id,
      studentName:
        `${row.student_first_name ?? ""} ${row.student_last_name ?? ""}`.trim() ||
        null,
      amount: Number(row.amount),
      currency: row.currency,
      paymentDate: row.payment_date,
      method: row.method,
      externalId: row.external_id,
      notes: row.notes,
      createdBy: row.created_by,
      createdAt: row.created_at,
    };
  }

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

  private toExpenseDto(row: ExpenseRow) {
    return {
      id: row.id,
      amount: Number(row.amount),
      category: row.category,
      description: row.description,
      branchId: row.branch_id,
      branchName: row.branch_name,
      createdAt: row.created_at,
    };
  }

  async listPayments(actor: ActorContext, query: PaymentQuery) {
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<PaymentRow>(
      `
        select pay.id, pay.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name, pay.amount,
          pay.currency, pay.payment_date, pay.method, pay.external_id,
          pay.notes, pay.created_by, pay.created_at
        from app.payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and ($3::uuid is null or pay.student_id = $3)
          and ($4::timestamptz is null or pay.payment_date >= $4)
          and ($5::timestamptz is null or pay.payment_date < $5)
          and (
            $1::text in ('manager', 'director', 'admin', 'system_admin')
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
        limit $6
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.from ?? null,
        query.to ?? null,
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
        from app.payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and ($3::uuid is null or pay.student_id = $3)
          and ($4::timestamptz is null or pay.payment_date >= $4)
          and ($5::timestamptz is null or pay.payment_date < $5)
          and (
            $1::text in ('manager', 'director', 'admin', 'system_admin')
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
      ],
    );
    return {
      items: result.rows.map((row) => this.toPaymentDto(row)),
      totalAmount: Number(totals.rows[0]?.total_amount ?? "0"),
      totalCount: Number(totals.rows[0]?.total_count ?? "0"),
    };
  }

  async listExpectedPayments(actor: ActorContext, query: CrmListQuery) {
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
    // Финансы ученика: Управляющий + Администратор (см. canReadStudentFinance).
    this.policy.assertCanReadStudentFinance(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<StudentBalanceRow>(
      `
        with lesson_costs as (
          select
            coalesce(l.student_id, lp.student_id) as student_id,
            sum(
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
            ) as total_cost,
            max(l.updated_at) as updated_at
          from app.lessons l
          left join app.lesson_participation lp on lp.lesson_id = l.id
          join app.students s on s.id = coalesce(l.student_id, lp.student_id)
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and coalesce(l.student_id, lp.student_id) is not null
          group by coalesce(l.student_id, lp.student_id)
        ),
        payment_totals as (
          select
            p.student_id,
            sum(p.amount) as total_paid,
            max(coalesce(p.created_at, p.payment_date)) as updated_at
          from app.payments p
          where p.deleted_at is null
          group by p.student_id
        ),
        adjustment_totals as (
          select
            adj.student_id,
            sum(adj.amount) as total_adjustments,
            max(adj.occurred_at) as updated_at
          from app.account_adjustments adj
          where adj.deleted_at is null
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

  /**
   * KVA-235: личный счёт клиента — единая лента операций (ledger-проекция).
   * Приход = app.payments, расход = проведённые занятия по их стоимости,
   * плюс ручные операции app.account_adjustments (возврат/корректировка).
   * Знак: приход > 0, расход < 0 — баланс равен сумме ленты и сходится с
   * listStudentBalances по построению.
   */
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
            coalesce(p.payment_date, p.created_at) as occurred_at
          from app.payments p
          left join app.students st on st.id = p.student_id
          left join app.branches b on b.id = st.branch_id
          left join app.users u on u.id = p.created_by and u.deleted_at is null
          left join app.profiles author on author.user_id = u.id and author.deleted_at is null
          where p.deleted_at is null and p.student_id = $1

          union all

          select l.id, 'lesson_charge' as kind,
            -coalesce(
              g.price_per_lesson,
              case
                when s.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                  then (s.custom_data->>'individualPrice')::numeric
                when s.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                  then (s.custom_data->>'individual_price')::numeric
                else null
              end,
              0
            ) as amount,
            trim(concat('Занятие', ' ', coalesce(g.name, 'индивидуально'))) as description,
            null as method,
            b.name as branch_name,
            null as author_first_name,
            null as author_last_name,
            l.scheduled_at as occurred_at
          from app.lessons l
          left join app.lesson_participation lp on lp.lesson_id = l.id and lp.student_id = $1
          join app.students s on s.id = coalesce(l.student_id, lp.student_id)
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          left join app.branches b on b.id = l.branch_id
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and coalesce(l.student_id, lp.student_id) = $1

          union all

          select adj.id, adj.kind, adj.amount, adj.description, adj.method,
            b.name as branch_name,
            author.first_name as author_first_name,
            author.last_name as author_last_name,
            adj.occurred_at
          from app.account_adjustments adj
          left join app.branches b on b.id = adj.branch_id
          left join app.users u on u.id = adj.created_by and u.deleted_at is null
          left join app.profiles author on author.user_id = u.id and author.deleted_at is null
          where adj.deleted_at is null and adj.student_id = $1
        )
        select *,
          sum(case when amount > 0 then amount else 0 end) over () as income_total,
          sum(case when amount < 0 then -amount else 0 end) over () as outcome_total
        from ledger
        where ($2::text is null
          or ($2 = 'income' and amount > 0)
          or ($2 = 'outcome' and amount < 0))
        order by occurred_at desc, id desc
        limit $3
      `,
      [studentId, direction, limit],
    );
    type LedgerRowWithTotals = LedgerRow & {
      income_total?: string | number;
      outcome_total?: string | number;
    };
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
      })),
      incomeTotal: Number(first?.income_total ?? 0),
      outcomeTotal: Number(first?.outcome_total ?? 0),
    };
  }

  /** KVA-235: ручная операция личного счёта (возврат/корректировка). */
  async createAccountAdjustment(
    actor: ActorContext,
    studentId: string,
    dto: CreateAdjustmentDto,
  ) {
    this.policy.assertManagerOnly(actor);
    const student = await findStudent(this.database, studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    // Возврат — всегда расход; корректировка — по direction (по умолч. приход).
    const outcome = dto.kind === "refund" || dto.direction === "outcome";
    const signedAmount = outcome ? -Math.abs(dto.amount) : Math.abs(dto.amount);
    const result = await this.database.query<{ id: string }>(
      `
        insert into app.account_adjustments
          (student_id, branch_id, kind, amount, description, method, occurred_at, created_by)
        values ($1, (select branch_id from app.students where id = $1), $2, $3, $4, $5,
          coalesce($6::timestamptz, now()), $7)
        returning id
      `,
      [
        studentId,
        dto.kind,
        signedAmount,
        dto.description ?? null,
        dto.method ?? null,
        dto.occurredAt ?? null,
        actor.userId,
      ],
    );
    await this.audit.record({
      actor,
      action: "crm.account_adjustment_created",
      entityType: "student",
      entityId: studentId,
      metadata: { kind: dto.kind, amount: signedAmount },
    });
    return { id: result.rows[0].id, amount: signedAmount, kind: dto.kind };
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
        const dup = await client.query<PaymentRow>(
          `
        select id, student_id, null::uuid as student_user_id, amount,
          null::text as student_first_name, null::text as student_last_name,
          currency, payment_date, method, external_id, notes, created_by, created_at
        from app.payments
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
          external_id, notes, created_by
        )
        values ($1, $2, coalesce($3, 'RUB'), $4, $5, $6, $7, $8)
        returning id, student_id, null::uuid as student_user_id, amount,
          null::text as student_first_name, null::text as student_last_name,
          currency, payment_date, method, external_id, notes, created_by, created_at
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
          ],
        );
        return { payment: result.rows[0], existing: false };
      },
    );
    if (existing) return this.toPaymentDto(payment);
    await this.audit.record({
      actor,
      action: "crm.payment_created",
      entityType: "student",
      entityId: payment.student_id,
      metadata: { paymentId: payment.id },
    });
    const affectedUserIds = await audienceForStudent(
      this.database,
      payment.student_id,
    );
    this.realtime.emitCrmChanged({
      entity: "payment",
      action: "created",
      id: payment.id,
      affectedUserIds,
    });
    return this.toPaymentDto(payment);
  }

  async listExpenses(actor: ActorContext, query: ExpenseQuery) {
    // KVA-239: расходы школы — общешкольные финансы, только director/system_admin.
    this.policy.assertCanReadSchoolFinance(actor);
    const conditions: string[] = ["e.deleted_at is null"];
    const params: unknown[] = [];
    if (query.branchId) {
      params.push(query.branchId);
      conditions.push(`e.branch_id = $${params.length}`);
    }
    if (query.category) {
      params.push(query.category);
      conditions.push(`e.category = $${params.length}`);
    }
    if (query.from) {
      params.push(query.from);
      conditions.push(`e.created_at >= $${params.length}`);
    }
    if (query.to) {
      params.push(query.to);
      conditions.push(`e.created_at <= $${params.length}`);
    }
    const where = conditions.join(" and ");
    const filterParams = [...params];
    const limit = Math.min(query.limit ?? 100, 500);
    params.push(limit);
    const result = await this.database.query<ExpenseRow>(
      `
        select e.id, e.amount, e.category, e.description, e.branch_id,
          b.name as branch_name, e.created_at
        from app.expenses e
        left join app.branches b on b.id = e.branch_id
        where ${where}
        order by e.created_at desc
        limit $${params.length}
      `,
      params,
    );
    const totalResult = await this.database.query<{
      total: string | number | null;
    }>(
      `select coalesce(sum(e.amount), 0) as total from app.expenses e where ${where}`,
      filterParams,
    );
    return {
      items: result.rows.map((row) => this.toExpenseDto(row)),
      total: Number(totalResult.rows[0]?.total ?? 0),
    };
  }

  async createExpense(actor: ActorContext, dto: UpsertExpenseDto) {
    this.policy.assertCanReadSchoolFinance(actor);
    const result = await this.database.query<ExpenseRow>(
      `
        insert into app.expenses (amount, category, description, branch_id)
        values ($1, $2, $3, $4)
        returning id, amount, category, description, branch_id,
          null::text as branch_name, created_at
      `,
      [
        dto.amount,
        dto.category.trim(),
        dto.description?.trim() || null,
        dto.branchId ?? null,
      ],
    );
    const expense = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.expense_created",
      entityType: "expense",
      entityId: expense.id,
      metadata: { amount: dto.amount, category: expense.category },
    });
    this.realtime.emitCrmChanged({
      entity: "expense",
      action: "created",
      id: expense.id,
      branchId: expense.branch_id ?? null,
    });
    return this.toExpenseDto(expense);
  }

  async updateExpense(
    actor: ActorContext,
    expenseId: string,
    dto: UpdateExpenseDto,
  ) {
    this.policy.assertCanReadSchoolFinance(actor);
    const result = await this.database.query<ExpenseRow>(
      `
        update app.expenses
        set amount = coalesce($2, amount),
            category = coalesce($3, category),
            description = coalesce($4, description),
            branch_id = coalesce($5, branch_id),
            updated_at = now()
        where id = $1 and deleted_at is null
        returning id, amount, category, description, branch_id,
          null::text as branch_name, created_at
      `,
      [
        expenseId,
        dto.amount ?? null,
        dto.category?.trim() ?? null,
        dto.description?.trim() ?? null,
        dto.branchId ?? null,
      ],
    );
    const expense = result.rows[0];
    if (!expense) throw new NotFoundException("Расход не найден.");
    await this.audit.record({
      actor,
      action: "crm.expense_updated",
      entityType: "expense",
      entityId: expense.id,
    });
    this.realtime.emitCrmChanged({
      entity: "expense",
      action: "updated",
      id: expense.id,
      branchId: expense.branch_id ?? null,
    });
    return this.toExpenseDto(expense);
  }

  async deleteExpense(actor: ActorContext, expenseId: string) {
    this.policy.assertCanReadSchoolFinance(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.expenses
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [expenseId],
    );
    const expense = result.rows[0];
    if (!expense) throw new NotFoundException("Расход не найден.");
    await this.audit.record({
      actor,
      action: "crm.expense_deleted",
      entityType: "expense",
      entityId: expense.id,
    });
    this.realtime.emitCrmChanged({
      entity: "expense",
      action: "deleted",
      id: expense.id,
    });
    return { success: true };
  }
}
