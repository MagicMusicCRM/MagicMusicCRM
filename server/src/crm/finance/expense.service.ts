import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ExpenseQuery } from "../dto/expense.query";
import { UpdateExpenseDto } from "../dto/update-expense.dto";
import { UpsertExpenseDto } from "../dto/upsert-expense.dto";
import { ExpenseRow } from "./finance.types";

@Injectable()
export class ExpenseService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

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
      conditions.push(`e.created_at < $${params.length}`);
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
