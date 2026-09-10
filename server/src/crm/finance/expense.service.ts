import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ForbiddenException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  VersionedMutationMetadata,
  assertVersionedMutationMetadata,
} from "../../platform/versioned-mutation-metadata";
import { currentActorRoleSql } from "../branch-scope";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { ExpenseQuery } from "../dto/expense.query";
import { UpdateExpenseDto } from "../dto/update-expense.dto";
import { UpsertExpenseDto } from "../dto/upsert-expense.dto";
import {
  decodeFinanceCursor,
  encodeFinanceCursor,
} from "./finance-list-cursor";
import { ExpenseRow } from "./finance.types";

@Injectable()
export class ExpenseService {
  constructor(
    private readonly database: DatabaseService,
    private readonly integrity: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
  ) {}

  private toExpenseDto(row: ExpenseRow) {
    return {
      id: row.id,
      version: Number(row.version),
      occurredAt: row.occurred_at ?? row.created_at,
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
      conditions.push(
        `coalesce(e.occurred_at,e.created_at) >= $${params.length}`,
      );
    }
    if (query.to) {
      params.push(query.to);
      conditions.push(
        `coalesce(e.occurred_at,e.created_at) < $${params.length}`,
      );
    }
    const where = conditions.join(" and ");
    const filterParams = [...params];
    const limit = Math.min(query.limit ?? 100, 500);
    const cursor = decodeFinanceCursor(query.cursor);
    if (cursor) {
      params.push(cursor.at, cursor.id);
      conditions.push(
        `(coalesce(e.occurred_at,e.created_at),e.id) < ($${params.length - 1}::timestamptz,$${params.length}::uuid)`,
      );
    }
    const pageWhere = conditions.join(" and ");
    params.push(limit + 1);
    const result = await this.database.query<
      ExpenseRow & { cursor_at: string }
    >(
      `
        select e.id, e.amount, e.category, e.description, e.branch_id,
          b.name as branch_name, e.created_at, e.occurred_at, e.version,
          to_char(coalesce(e.occurred_at,e.created_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as cursor_at
        from app.expenses e
        left join app.branches b on b.id = e.branch_id
        where ${pageWhere}
        order by coalesce(e.occurred_at,e.created_at) desc, e.id desc
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
      items: result.rows.slice(0, limit).map((row) => this.toExpenseDto(row)),
      nextCursor:
        result.rows.length > limit
          ? encodeFinanceCursor(result.rows[limit - 1])
          : null,
      total: Number(totalResult.rows[0]?.total ?? 0),
    };
  }

  async createExpense(
    actor: ActorContext,
    dto: UpsertExpenseDto,
    metadata?: VersionedMutationMetadata,
  ) {
    this.policy.assertCanReadSchoolFinance(actor);
    const command = metadata ?? { idempotencyKey: "", requestId: "" };
    assertVersionedMutationMetadata(command);
    const h = createHash("sha256")
      .update([actor.userId, "expense", command.idempotencyKey].join(":"))
      .digest("hex");
    const id = [
      h.slice(0, 8),
      h.slice(8, 12),
      "4" + h.slice(13, 16),
      "a" + h.slice(17, 20),
      h.slice(20, 32),
    ].join("-");
    return this.mutateExpense(actor, id, "created", dto, 0, command);
  }

  async updateExpense(
    actor: ActorContext,
    id: string,
    dto: UpdateExpenseDto,
    metadata?: VersionedMutationMetadata,
  ) {
    this.policy.assertCanReadSchoolFinance(actor);
    return this.mutateExpense(
      actor,
      id,
      "updated",
      dto,
      dto.expectedVersion,
      metadata,
    );
  }

  async deleteExpense(
    actor: ActorContext,
    id: string,
    expectedVersion?: number,
    metadata?: VersionedMutationMetadata,
  ) {
    this.policy.assertCanReadSchoolFinance(actor);
    await this.mutateExpense(
      actor,
      id,
      "deleted",
      {},
      expectedVersion,
      metadata,
    );
    return { success: true };
  }

  private async mutateExpense(
    actor: ActorContext,
    id: string,
    action: "created" | "updated" | "deleted",
    dto: Partial<UpsertExpenseDto>,
    expectedVersion: number | undefined,
    metadata?: VersionedMutationMetadata,
  ) {
    const command = metadata ?? { idempotencyKey: "", requestId: "" };
    assertVersionedMutationMetadata(command);
    if (
      !Number.isSafeInteger(expectedVersion) ||
      expectedVersion! < (action === "created" ? 0 : 1)
    ) {
      throw new BadRequestException("Передайте актуальную версию расхода.");
    }
    if (
      (action === "created" || dto.amount !== undefined) &&
      (typeof dto.amount !== "number" ||
        !Number.isFinite(dto.amount) ||
        dto.amount <= 0 ||
        dto.amount >= 1e10 ||
        Math.abs(dto.amount * 100 - Math.round(dto.amount * 100)) > 0.0001)
    ) {
      throw new BadRequestException(
        "Укажите положительную сумму с точностью до копейки.",
      );
    }
    if (
      (action === "created" || dto.category !== undefined) &&
      (typeof dto.category !== "string" || !dto.category.trim())
    )
      throw new BadRequestException("Укажите категорию расхода.");
    if (
      dto.occurredAt !== undefined &&
      !Number.isFinite(Date.parse(dto.occurredAt))
    )
      throw new BadRequestException("Некорректная дата расхода.");
    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: { actor, capabilityKey: "commerce.school_finance.read" },
      operation: "crm.expense." + action,
      idempotencyKey: command.idempotencyKey,
      requestId: command.requestId,
      aggregateType: "commerce:expense",
      aggregateId: id,
      expectedVersion: expectedVersion!,
      payload: { action, ...dto },
      audit: {
        action:
          action === "created"
            ? "crm.expense_created"
            : action === "updated"
              ? "crm.expense_updated"
              : "crm.expense_deleted",
        entityType: "expense",
        entityId: id,
        reason: "expense_" + action,
        beforeRef:
          action === "created"
            ? undefined
            : { entityId: id, version: expectedVersion },
        afterRef: { entityId: id, version: expectedVersion! + 1 },
      },
      outbox: {
        type: "commerce.expense.changed",
        payload: { entityId: id, action, invalidates: ["school-finance"] },
      },
      beforeVersionAdvance: async (client) => {
        const role = await client.query<{ allowed: boolean }>(
          `select ${currentActorRoleSql("$1")} = any(array['director','system_admin']) as allowed`,
          [actor.userId],
        );
        if (!role.rows[0]?.allowed)
          throw new ForbiddenException("Недостаточно прав для расходов школы.");
        if (action !== "created") {
          const row = await client.query(
            "select id from app.expenses where id=$1 and deleted_at is null for update",
            [id],
          );
          if (!row.rows[0]) throw new NotFoundException("Расход не найден.");
        }
      },
      mutate: async (client, version) => {
        if (action === "created") {
          await client.query(
            `insert into app.expenses(id,amount,category,description,branch_id,occurred_at,version)
            values($1,$2,$3,$4,$5,coalesce($6::timestamptz,now()),$7)`,
            [
              id,
              dto.amount,
              dto.category!.trim(),
              dto.description?.trim() || null,
              dto.branchId ?? null,
              dto.occurredAt ?? null,
              version,
            ],
          );
        } else if (action === "updated") {
          await client.query(
            `update app.expenses set amount=coalesce($2,amount),category=coalesce($3,category),
            description=case when $4 then $5 else description end,branch_id=case when $6 then $7::uuid else branch_id end,
            occurred_at=coalesce($8::timestamptz,occurred_at),version=$9,updated_at=now() where id=$1`,
            [
              id,
              dto.amount ?? null,
              dto.category?.trim() ?? null,
              Object.hasOwn(dto, "description"),
              dto.description?.trim() || null,
              Object.hasOwn(dto, "branchId"),
              dto.branchId ?? null,
              dto.occurredAt ?? null,
              version,
            ],
          );
        } else {
          await client.query(
            "update app.expenses set deleted_at = now(), updated_at=now(),version=$2 where id=$1",
            [id, version],
          );
        }
        await client.query(
          `insert into app.expense_revisions(expense_id,version,amount,category,description,branch_id,occurred_at,expense_created_at,deleted_at)
          select id,version,amount,category,description,branch_id,occurred_at,created_at,deleted_at from app.expenses where id=$1`,
          [id],
        );
        return { entityId: id, version };
      },
    });
    const snapshot = await this.database.query<ExpenseRow>(
      `select revision.expense_id as id,revision.version,revision.amount,revision.category,
      revision.description,revision.branch_id,branch.name as branch_name,revision.occurred_at,revision.expense_created_at as created_at
      from app.expense_revisions revision left join app.branches branch on branch.id=revision.branch_id
      where revision.expense_id=$1 and revision.version=$2`,
      [result.resultRef.entityId, result.version],
    );
    if (!snapshot.rows[0])
      throw new NotFoundException("Версия расхода не найдена.");
    return this.toExpenseDto(snapshot.rows[0]);
  }
}
