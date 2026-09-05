import { PaymentLifecycleService } from "./commerce/payment-lifecycle.service";
import {
  BadRequestException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { ExpenseService } from "./finance/expense.service";
import { FinancePaymentService } from "./finance/finance-payment.service";
import { StudentAccountTransferService } from "./finance/student-account-transfer.service";
import { StudentFinanceQueryService } from "./finance/student-finance-query.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { PlatformIntegrityRepository } from "../platform/platform-integrity.repository";
import { FinanceService } from "./finance.service";

describe("FinanceService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };
  const schoolActor = { userId: "director-a", role: "director" as const };

  const build = (query: jest.Mock) => {
    const database = {
      query,
      // Transactional writes share the same query mock so sequential
      // mockResolvedValueOnce chains keep working.
      transaction: (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertManagerOnly: jest.fn(),
      assertCanReadStudentFinance: jest.fn(),
      assertCanReadSchoolFinance: jest.fn(),
      assertCanReadStudent: jest.fn(),
    };
    const realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    };
    const typedDatabase = database as unknown as DatabaseService;
    const typedAudit = audit as unknown as AuditService;
    const typedPolicy = policy as unknown as CrmPolicy;
    const typedRealtime = realtime as unknown as RealtimeBus;
    const service = new FinanceService(
      new FinancePaymentService(
        typedDatabase,
        typedPolicy,
        {} as PaymentLifecycleService,
      ),
      new StudentFinanceQueryService(typedDatabase, typedPolicy),
      new StudentAccountTransferService(
        typedDatabase,
        new PlatformIntegrityService(
          typedDatabase,
          new PlatformIntegrityRepository(),
        ),
        typedPolicy,
      ),
      new ExpenseService(
        typedDatabase,
        new PlatformIntegrityService(
          typedDatabase,
          new PlatformIntegrityRepository(),
        ),
        typedPolicy,
      ),
    );
    return { service, query, audit, policy, realtime };
  };

  const createService = (rows: Record<string, unknown>[] = []) =>
    build(jest.fn().mockResolvedValue({ rows }));

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) query.mockResolvedValueOnce(result);
    return build(query);
  };

  it("lists the student ledger with signed amounts, totals and direction filter", async () => {
    const { service, query, policy } = createService([
      {
        id: "pay-1",
        kind: "payment",
        amount: "5000",
        description: "Оплата абонемента",
        method: "Безналичные",
        branch_name: "Сокол",
        author_first_name: "Мария",
        author_last_name: "Менеджер",
        occurred_at: "2026-07-01T00:00:00.000Z",
        income_total: "5000",
        outcome_total: "1500",
      },
      {
        id: "adj-1",
        kind: "refund",
        amount: "-1500",
        description: "Возврат",
        method: null,
        branch_name: "Сокол",
        author_first_name: null,
        author_last_name: null,
        occurred_at: "2026-07-02T00:00:00.000Z",
        income_total: "5000",
        outcome_total: "1500",
      },
    ]);

    await expect(
      service.listStudentLedger(actor, "student-a", {
        direction: "income",
        limit: 50,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "pay-1",
          kind: "payment",
          amount: 5000,
          description: "Оплата абонемента",
          method: "Безналичные",
          branchName: "Сокол",
          authorName: "Мария Менеджер",
          occurredAt: "2026-07-01T00:00:00.000Z",
        },
        {
          id: "adj-1",
          kind: "refund",
          amount: -1500,
          description: "Возврат",
          method: null,
          branchName: "Сокол",
          authorName: null,
          occurredAt: "2026-07-02T00:00:00.000Z",
        },
      ],
      incomeTotal: 5000,
      outcomeTotal: 1500,
    });
    expect(policy.assertCanReadStudentFinance).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["student-a", "income", 50]);
    expect(String(query.mock.calls[0][0])).toContain("l.is_trial = false");
    expect(String(query.mock.calls[0][0])).toContain(
      "lp.attendance_kind = 'partially_paid'",
    );
    expect(String(query.mock.calls[0][0])).toContain("then lp.charge_share");
  });

  it("shows a linked 24000/8 subscription charge as one 3000 ledger expense", async () => {
    const { service, query } = createService([
      {
        id: "lesson-a",
        kind: "lesson_charge",
        amount: "-3000",
        description: "Занятие индивидуально",
        method: null,
        branch_name: "Сокол",
        author_first_name: null,
        author_last_name: null,
        occurred_at: "2026-07-21T09:00:00.000Z",
        invoice_number: null,
        status: "paid",
        editable: false,
        income_total: "24000",
        outcome_total: "3000",
      },
    ]);

    await expect(
      service.listStudentLedger(actor, "student-a", { limit: 50 }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "lesson-a",
          kind: "lesson_charge",
          amount: -3000,
        }),
      ],
      incomeTotal: 24000,
      outcomeTotal: 3000,
    });

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("left join app.subscriptions sub on sub.id = lp.subscription_id");
    expect(sql).toContain("left join app.subscription_packages pkg on pkg.id = sub.package_id");
    expect(sql).toContain(
      "left join app.commerce_ordinary_payments sub_pay",
    );
    expect(sql).toContain("coalesce(sub_pay.amount, pkg.price)");
    expect(sql).toContain("/ nullif(sub.lessons_total, 0)");
    expect(sql).toContain("* lp.charged_hours");
    expect(sql).toContain(
      "coalesce(sub.student_id, l.student_id, lp.student_id) = $1",
    );
  });

  it("keeps a voided entry out of the balance", async () => {
    const { service, query } = createService([]);

    await service.listStudentBalances(schoolActor, { limit: 10 });

    // Без этого фильтра сторнирование не меняло бы баланс — то есть отмена
    // ничего бы не отменяла.
    expect(String(query.mock.calls[0][0])).toContain("adj.status <> 'void'");
    expect(String(query.mock.calls[0][0])).toContain("l.is_trial = false");
    expect(String(query.mock.calls[0][0])).toContain(
      "lp.attendance_kind in ('attended', 'paid_miss')",
    );
  });

  it("lists payments with date filters and student summary", async () => {
    const { service, query } = createService([
      {
        id: "payment-a",
        student_id: "student-a",
        student_user_id: "client-a",
        student_first_name: "Анна",
        student_last_name: "Иванова",
        amount: "5000.00",
        currency: "RUB",
        payment_date: "2026-06-12T12:00:00.000Z",
        method: "subscription",
        external_id: null,
        notes: null,
        created_by: "manager-a",
        created_at: "2026-06-12T12:00:00.000Z",
      },
    ]);

    await expect(
      service.listPayments(schoolActor, {
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
        branchId: "11111111-1111-4111-8111-111111111111",
        limit: 10,
      }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "payment-a",
          studentId: "student-a",
          studentName: "Анна Иванова",
          amount: 5000,
          method: "subscription",
        }),
      ],
      // Totals come from a separate aggregate query (mocked with the same row,
      // which has no total_* fields, so they resolve to 0 here).
      totalAmount: 0,
      totalCount: 0,
      nextCursor: null,
    });

    expect(query.mock.calls[0][1]).toEqual([
      "director",
      "director-a",
      null,
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      "11111111-1111-4111-8111-111111111111",
      11,
      null,
      null,
    ]);
    expect(String(query.mock.calls[0][0])).toContain("pay.branch_id = $6");
  });

  it("denies teacher global payments before composing finance rows", async () => {
    const { service, query, policy } = createService([]);
    policy.assertCanReadSchoolFinance.mockImplementation(() => {
      throw new ForbiddenException();
    });

    await expect(
      service.listPayments(
        { userId: "teacher-a", role: "teacher" },
        { studentId: "student-linked", limit: 10 },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(query).not.toHaveBeenCalled();
  });

  it("lists computed student balances for CRM writers", async () => {
    const { service, query, policy } = createService([
      {
        student_id: "student-a",
        first_name: "Анна",
        last_name: "Иванова",
        phone: "+79990000000",
        total_paid: "2000.00",
        total_cost: "5000.00",
        balance: "-3000.00",
        updated_at: "2026-06-12T12:00:00.000Z",
      },
    ]);

    await expect(
      service.listStudentBalances(schoolActor, {
        studentId: "student-a",
        debtOnly: true,
        limit: 20,
      }),
    ).resolves.toEqual({
      items: [
        {
          studentId: "student-a",
          balance: -3000,
          totalPaid: 2000,
          totalCost: 5000,
          totalAdjustments: 0,
          updatedAt: "2026-06-12T12:00:00.000Z",
          student: {
            firstName: "Анна",
            lastName: "Иванова",
            phone: "+79990000000",
          },
        },
      ],
    });

    expect(policy.assertCanReadSchoolFinance).toHaveBeenCalledWith(schoolActor);
    expect(query.mock.calls[0][1]).toEqual(["student-a", true, 20]);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("coalesce(sub_pay.amount, pkg.price)");
    expect(sql).toContain("/ nullif(sub.lessons_total, 0)");
    expect(sql).toContain("* lp.charged_hours");
    expect(sql).toContain(
      "group by coalesce(sub.student_id, l.student_id, lp.student_id)",
    );
    // Legacy/imported lessons without a subscription keep their established
    // group/custom-data fallback instead of silently becoming free.
    expect(sql).toContain("g.price_per_lesson");
    expect(sql).toContain("s.custom_data->>'individualPrice'");
    expect(sql).toContain("then lp.charge_share");
    expect(sql).toContain("l.is_trial = false");
  });

  it("lists expected payments after student read authorization", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "student-a",
            status: "active",
            custom_data: {},
            profile_id: "profile-a",
            profile_user_id: "client-a",
            first_name: "Анна",
            last_name: "Иванова",
            email: "anna@example.com",
            phone: null,
            created_at: "2026-06-01T00:00:00.000Z",
            teacher_user_ids: [],
          },
        ],
      },
      {
        rows: [
          {
            id: "expected-a",
            student_id: "student-a",
            student_user_id: "client-a",
            student_first_name: "Анна",
            student_last_name: "Иванова",
            amount: "5000.00",
            due_date: "2026-06-30",
            status: "pending",
            description: "Абонемент за июнь",
            created_at: "2026-06-12T00:00:00.000Z",
            updated_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.listExpectedPayments(schoolActor, {
        studentId: "student-a",
        limit: 10,
      }),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "expected-a",
          studentId: "student-a",
          studentName: "Анна Иванова",
          amount: 5000,
          dueDate: "2026-06-30",
          status: "pending",
          description: "Абонемент за июнь",
        }),
      ],
    });

    expect(policy.assertCanReadSchoolFinance).toHaveBeenCalledWith(schoolActor);
    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(schoolActor, {
      profileUserId: "client-a",
      teacherUserIds: [],
    });
    expect(query.mock.calls[1][1]).toEqual(["student-a", 10]);
  });

  it("returns payments with a correct server-side period total (not the page fold)", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          { id: "pay-1", student_id: "s1", amount: "500", currency: "RUB" },
          { id: "pay-2", student_id: "s1", amount: "700", currency: "RUB" },
        ],
      },
      { rows: [{ total_amount: "12345", total_count: "37" }] },
    ]);
    const result = await service.listPayments(schoolActor, {});
    expect(result.items).toHaveLength(2);
    // The total reflects the full filtered set (37 payments / 12345), not the
    // sum of the returned page (1200).
    expect(result.totalAmount).toBe(12345);
    expect(result.totalCount).toBe(37);
  });

  it("requires command metadata before invoking legacy payment adapter", async () => {
    const { service, query } = createService([]);
    await expect(
      service.createPayment(actor, {
        studentId: "student-a",
        amount: 100,
        paymentDate: "2026-09-05",
      }),
    ).rejects.toMatchObject({ response: { code: "IDEMPOTENCY_KEY_REQUIRED" } });
    expect(query).not.toHaveBeenCalled();
  });

  it("lists expenses with branch/category filters and a total (P5-5)", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "exp-a",
            version: 1,
            amount: "1500.00",
            category: "rent",
            description: null,
            branch_id: "branch-a",
            branch_name: "Центр",
            created_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
      { rows: [{ total: "1500.00" }] },
    ]);

    const result = await service.listExpenses(actor, {
      branchId: "branch-a",
      category: "rent",
      from: "2026-06-01T00:00:00.000Z",
      to: "2026-07-01T00:00:00.000Z",
      limit: 50,
    });

    expect(policy.assertCanReadSchoolFinance).toHaveBeenCalledWith(actor);
    expect(result.total).toBe(1500);
    expect(result.items).toEqual([
      {
        id: "exp-a",
        version: 1,
        amount: 1500,
        category: "rent",
        description: null,
        branchId: "branch-a",
        branchName: "Центр",
        createdAt: "2026-06-22T00:00:00.000Z",
        occurredAt: "2026-06-22T00:00:00.000Z",
      },
    ]);
    // items query: branch + category filters then the limit param last.
    expect(query.mock.calls[0][1]).toEqual([
      "branch-a",
      "rent",
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      51,
    ]);
    expect(String(query.mock.calls[0][0])).toContain(
      "coalesce(e.occurred_at,e.created_at) < $4",
    );
    // total query reuses the filter params WITHOUT the limit.
    expect(query.mock.calls[1][1]).toEqual([
      "branch-a",
      "rent",
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
    ]);
  });

  it("rejects transfers without a stable command identity before writing", async () => {
    const { service, query } = createService([]);
    await expect(
      service.createAccountTransfer(actor, "student-a", {
        toStudentId: "student-b",
        amount: 100,
      }),
    ).rejects.toMatchObject({ response: { code: "IDEMPOTENCY_KEY_REQUIRED" } });
    expect(query).not.toHaveBeenCalled();
  });
});
