import { NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { FinanceService } from "./finance.service";

describe("FinanceService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

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
    const realtime = { emitCrmChanged: jest.fn() };
    const service = new FinanceService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
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
  });

  it("creates a refund adjustment as a negative amount and audits it", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      { rows: [{ id: "student-a", profile_user_id: "client-a" }] }, // findStudent
      { rows: [{ id: "adj-new" }] }, // insert returning
    ]);

    await expect(
      service.createAccountAdjustment(actor, "student-a", {
        kind: "refund",
        amount: 2000,
        description: "Возврат за отменённые занятия",
      }),
    ).resolves.toEqual({ id: "adj-new", amount: -2000, kind: "refund" });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    // Знак выставлен сервисом: возврат хранится отрицательным.
    expect(query.mock.calls[1][1]).toEqual([
      "student-a",
      "refund",
      -2000,
      "Возврат за отменённые занятия",
      null,
      null,
      "manager-a",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.account_adjustment_created",
        entityId: "student-a",
      }),
    );
  });

  it("keeps a positive amount for an income adjustment", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ id: "student-a" }] },
      { rows: [{ id: "adj-plus" }] },
    ]);

    await expect(
      service.createAccountAdjustment(actor, "student-a", {
        kind: "adjustment",
        amount: 300,
        direction: "income",
      }),
    ).resolves.toEqual({ id: "adj-plus", amount: 300, kind: "adjustment" });
    expect(query.mock.calls[1][1]).toContain(300);
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
      service.listPayments(actor, {
        from: "2026-06-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
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
    });

    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      null,
      "2026-06-01T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
      10,
    ]);
  });

  it("allows a client to list payments for a manually linked student", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "payment-linked",
            student_id: "student-linked",
            student_user_id: null,
            student_first_name: "Анна",
            student_last_name: "Связанная",
            amount: "9000.00",
            currency: "RUB",
            payment_date: "2026-06-22T12:00:00.000Z",
            method: "subscription",
            external_id: null,
            notes: "Покупка абонемента",
            created_by: "manager-a",
            created_at: "2026-06-22T12:00:00.000Z",
          },
        ],
      },
      { rows: [{ total_amount: "9000", total_count: "1" }] },
    ]);

    await expect(
      service.listPayments(
        { userId: "client-linked", role: "client" },
        { studentId: "student-linked", limit: 10 },
      ),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "payment-linked",
          studentId: "student-linked",
          amount: 9000,
        }),
      ],
      totalAmount: 9000,
      totalCount: 1,
    });

    for (const call of query.mock.calls.slice(0, 2)) {
      const sql = String(call[0]);
      expect(sql).toContain("app.user_crm_links");
      expect(sql).toContain("link.user_id = $2");
      expect(sql).toContain("link.entity_type = 'student'");
    }
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
      service.listStudentBalances(actor, {
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

    expect(policy.assertCanReadStudentFinance).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual(["student-a", true, 20]);
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
      service.listExpectedPayments(actor, {
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

    expect(policy.assertCanReadStudent).toHaveBeenCalledWith(actor, {
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
    const result = await service.listPayments(actor, {});
    expect(result.items).toHaveLength(2);
    // The total reflects the full filtered set (37 payments / 12345), not the
    // sum of the returned page (1200).
    expect(result.totalAmount).toBe(12345);
    expect(result.totalCount).toBe(37);
  });

  it("creates expenses through CRM write policy and audit (P5-5)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "exp-a",
        amount: "1500.00",
        category: "rent",
        description: "Аренда",
        branch_id: "branch-a",
        branch_name: null,
        created_at: "2026-06-22T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createExpense(actor, {
        amount: 1500,
        category: " rent ",
        description: " Аренда ",
        branchId: "branch-a",
      }),
    ).resolves.toEqual({
      id: "exp-a",
      amount: 1500,
      category: "rent",
      description: "Аренда",
      branchId: "branch-a",
      branchName: null,
      createdAt: "2026-06-22T00:00:00.000Z",
    });

    expect(policy.assertCanReadSchoolFinance).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([1500, "rent", "Аренда", "branch-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.expense_created",
        entityType: "expense",
        entityId: "exp-a",
      }),
    );
  });

  it("is idempotent for duplicate payment submits within the window", async () => {
    const paymentRow = {
      id: "pay-a",
      student_id: "student-a",
      student_user_id: null,
      amount: "1500.00",
      student_first_name: null,
      student_last_name: null,
      currency: "RUB",
      payment_date: "2026-06-23",
      method: "cash",
      external_id: null,
      notes: null,
      created_by: "manager-a",
      created_at: "2026-06-23T00:00:00.000Z",
    };
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // 1st: advisory lock
      { rows: [] }, // 1st: dup-check empty
      { rows: [paymentRow] }, // insert
      { rows: [] }, // affected client users for realtime fan-out
      { rows: [] }, // 2nd: advisory lock
      { rows: [paymentRow] }, // 2nd: dup-check returns existing
    ]);
    const dto = {
      studentId: "student-a",
      amount: 1500,
      paymentDate: "2026-06-23",
      method: "cash",
    } as never;

    const first = await service.createPayment(actor, dto);
    const second = await service.createPayment(actor, dto);

    expect(first.id).toBe("pay-a");
    expect(second.id).toBe("pay-a");
    // lock, dup-check, insert, realtime affected users, lock, dup-check — the
    // second submit must NOT insert again.
    expect(query).toHaveBeenCalledTimes(6);
    expect(String(query.mock.calls[0][0])).toContain("pg_advisory_xact_lock");
  });

  it("lists expenses with branch/category filters and a total (P5-5)", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "exp-a",
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
      limit: 50,
    });

    expect(policy.assertCanReadSchoolFinance).toHaveBeenCalledWith(actor);
    expect(result.total).toBe(1500);
    expect(result.items).toEqual([
      {
        id: "exp-a",
        amount: 1500,
        category: "rent",
        description: null,
        branchId: "branch-a",
        branchName: "Центр",
        createdAt: "2026-06-22T00:00:00.000Z",
      },
    ]);
    // items query: branch + category filters then the limit param last.
    expect(query.mock.calls[0][1]).toEqual(["branch-a", "rent", 50]);
    // total query reuses the filter params WITHOUT the limit.
    expect(query.mock.calls[1][1]).toEqual(["branch-a", "rent"]);
  });

  it("soft-deletes expenses and 404s when missing (P5-5)", async () => {
    const { service, query, audit } = createService([{ id: "exp-a" }]);
    await expect(service.deleteExpense(actor, "exp-a")).resolves.toEqual({
      success: true,
    });
    expect(query.mock.calls[0][0]).toContain("set deleted_at = now()");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.expense_deleted" }),
    );

    const missing = createService([]);
    await expect(
      missing.service.deleteExpense(actor, "exp-x"),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});
