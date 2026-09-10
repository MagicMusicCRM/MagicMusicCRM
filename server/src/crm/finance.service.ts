import { Injectable } from "@nestjs/common";
import { VersionedMutationMetadata } from "../platform/versioned-mutation-metadata";
import { ActorContext } from "../common/security/actor-context";
import { CreatePaymentDto } from "./dto/create-payment.dto";
import { CreateTransferDto } from "./dto/create-transfer.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { ExpenseQuery } from "./dto/expense.query";
import { PaymentQuery } from "./dto/payment.query";
import { StudentBalanceQuery } from "./dto/student-balance.query";
import { UpdateExpenseDto } from "./dto/update-expense.dto";
import { UpsertExpenseDto } from "./dto/upsert-expense.dto";
import { ExpenseService } from "./finance/expense.service";
import { FinancePaymentService } from "./finance/finance-payment.service";
import { StudentAccountTransferService } from "./finance/student-account-transfer.service";
import { StudentFinanceQueryService } from "./finance/student-finance-query.service";

@Injectable()
export class FinanceService {
  constructor(
    private readonly payments: FinancePaymentService,
    private readonly queries: StudentFinanceQueryService,
    private readonly transfers: StudentAccountTransferService,
    private readonly expenses: ExpenseService,
  ) {}

  async listRecentPaymentsForStudents(studentIds: string[]) {
    return this.payments.listRecentPaymentsForStudents(studentIds);
  }

  async listPayments(actor: ActorContext, query: PaymentQuery) {
    return this.payments.listPayments(actor, query);
  }

  async listExpectedPayments(actor: ActorContext, query: CrmListQuery) {
    return this.queries.listExpectedPayments(actor, query);
  }

  async listStudentBalances(actor: ActorContext, query: StudentBalanceQuery) {
    return this.queries.listStudentBalances(actor, query);
  }

  async listStudentLedger(
    actor: ActorContext,
    studentId: string,
    query: { direction?: string; limit?: number },
  ) {
    return this.queries.listStudentLedger(actor, studentId, query);
  }

  async createAccountTransfer(
    actor: ActorContext,
    fromStudentId: string,
    dto: CreateTransferDto,
    metadata?: VersionedMutationMetadata,
  ) {
    return this.transfers.createAccountTransfer(
      actor,
      fromStudentId,
      dto,
      metadata,
    );
  }

  async createPayment(
    actor: ActorContext,
    dto: CreatePaymentDto,
    metadata?: VersionedMutationMetadata,
  ) {
    return this.payments.createPayment(actor, dto, metadata);
  }

  async listExpenses(actor: ActorContext, query: ExpenseQuery) {
    return this.expenses.listExpenses(actor, query);
  }

  async createExpense(
    actor: ActorContext,
    dto: UpsertExpenseDto,
    metadata?: VersionedMutationMetadata,
  ) {
    return this.expenses.createExpense(actor, dto, metadata);
  }

  async updateExpense(
    actor: ActorContext,
    expenseId: string,
    dto: UpdateExpenseDto,
    metadata?: VersionedMutationMetadata,
  ) {
    return this.expenses.updateExpense(actor, expenseId, dto, metadata);
  }

  async deleteExpense(
    actor: ActorContext,
    expenseId: string,
    expectedVersion?: number,
    metadata?: VersionedMutationMetadata,
  ) {
    return this.expenses.deleteExpense(
      actor,
      expenseId,
      expectedVersion,
      metadata,
    );
  }
}
