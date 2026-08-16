import { ConflictException, ForbiddenException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { SubscriptionsService } from "./subscriptions.service";

describe("SubscriptionsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };
  const schoolActor = { userId: "director-a", role: "director" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const transaction = jest.fn(
      async (work: (client: { query: typeof query }) => Promise<unknown>) =>
        work({ query }),
    );
    const database = { query, transaction };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanManageSubscriptionPackages: jest.fn(),
      assertCanReadSchoolFinance: jest.fn(),
    };
    const realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    };

    const service = new SubscriptionsService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );

    return { service, query, transaction, audit, policy, realtime };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const queued = [...results];
    const query = jest
      .fn()
      .mockImplementation(() =>
        Promise.resolve(queued.shift() ?? { rows: [] }),
      );
    const transaction = jest.fn(
      async (work: (client: { query: typeof query }) => Promise<unknown>) =>
        work({ query }),
    );
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanManageSubscriptionPackages: jest.fn(),
      assertCanReadSchoolFinance: jest.fn(),
    };
    const realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    };
    const service = new SubscriptionsService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, transaction, audit, policy, realtime };
  };

  it("lists subscriptions with actor-scoped query and safe DTO", async () => {
    const { service, query } = createService([
      {
        id: "sub-a",
        student_id: "student-a",
        student_user_id: "client-a",
        lessons_total: 8,
        lessons_used: 3,
        starts_at: "2026-06-01",
        expires_at: "2026-07-01",
        status: "active",
        created_at: "2026-06-01T00:00:00.000Z",
        updated_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listSubscriptions(schoolActor, {
        studentId: "student-a",
        limit: 1,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "sub-a",
          studentId: "student-a",
          lessonsTotal: 8,
          lessonsUsed: 3,
          startsAt: "2026-06-01",
          expiresAt: "2026-07-01",
          status: "active",
          createdAt: "2026-06-01T00:00:00.000Z",
          updatedAt: "2026-06-12T00:00:00.000Z",
          packageName: null,
          packagePrice: null,
          // Прихода нет — «Оплачено» неизвестно. Это НЕ «оплачено 0».
          paidAmount: null,
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "director",
      "director-a",
      "student-a",
      1,
    ]);
  });

  it("denies teacher global subscriptions before composing finance rows", async () => {
    const { service, query, policy } = createService([]);
    policy.assertCanReadSchoolFinance.mockImplementation(() => {
      throw new ForbiddenException();
    });

    await expect(
      service.listSubscriptions(
        { userId: "teacher-a", role: "teacher" },
        { studentId: "student-linked", limit: 1 },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);

    expect(query).not.toHaveBeenCalled();
  });

  it("issues a subscription from a package atomically with audit (P5b)", async () => {
    const { service, query, transaction, audit, policy, realtime } =
      createServiceWithQueryResults([
        { rows: [{ id: "student-a" }] },
        {
          rows: [
            {
              id: "sub-a",
              lessons_total: 8,
              lessons_used: 0,
              starts_at: "2026-06-22",
              expires_at: "2026-08-21",
              status: "active",
              package_id: "pkg-a",
              payment_id: "pay-a",
            },
          ],
        },
        { rows: [{ user_id: "client-a" }] }, // active Client finance audience
      ]);

    await expect(
      service.issueSubscription(actor, "student-a", { packageId: "pkg-a" }),
    ).resolves.toEqual({
      id: "sub-a",
      studentId: "student-a",
      lessonsTotal: 8,
      lessonsUsed: 0,
      startsAt: "2026-06-22",
      expiresAt: "2026-08-21",
      status: "active",
      packageId: "pkg-a",
      paymentId: "pay-a",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(transaction).toHaveBeenCalledTimes(1);
    const sql = String(query.mock.calls[1][0]);
    expect(sql).toContain("insert into app.payments");
    expect(sql).toContain("insert into app.subscriptions");
    expect(query.mock.calls[1][1]).toEqual(["student-a", "pkg-a", "manager-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_issued",
        entityType: "student",
        entityId: "student-a",
      }),
    );
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith(["client-a"]);
    const financeAudienceSql = String(query.mock.calls[2][0]);
    expect(financeAudienceSql).toContain("recipient.role = 'client'");
    expect(financeAudienceSql).toContain("recipient.is_app_account = true");
  });

  it("atomically converts a lead only when issuing its subscription", async () => {
    const { service, query, audit, policy, realtime } =
      createServiceWithQueryResults([
        { rows: [] }, // advisory lock
        { rows: [] }, // no previous conversion issue
        {
          rows: [
            {
              id: "lead-a",
              first_name: "Анна",
              last_name: "Иванова",
              email: "anna@example.com",
              phone: "+79990000000",
              custom_data: { discipline: "Фортепиано" },
              branch_id: "branch-a",
              source_id: "source-a",
              created_at: "2026-07-18T09:00:00.000Z",
            },
          ],
        },
        {
          rows: [
            {
              id: "pkg-a",
              name: "8 занятий",
              discipline_id: "discipline-a",
              branch_id: "branch-a",
              lessons_total: "8",
              price: "8000.00",
              base_price_minor: "800000",
              currency_code: "RUB",
              version: "1",
              validity_days: 60,
              is_active: true,
              sort_order: 0,
              created_at: "2026-07-01T00:00:00.000Z",
            },
          ],
        },
        { rows: [] }, // no existing student
        { rows: [{ profile_id: "profile-client" }] },
        { rows: [{ id: "student-a" }] },
        { rows: [] }, // conversion link
        { rows: [] }, // copy user_crm_link
        { rows: [] }, // rebind administration chat
        { rows: [] }, // copy family membership
        { rows: [] }, // retire lead family membership
        {
          rows: [
            {
              id: "trial-a",
              student_id: "student-a",
              group_id: null,
              lead_id: null,
              teacher_id: "teacher-a",
            },
          ],
        }, // rebind trial
        { rows: [{ id: "hw-trial" }] }, // rebind homework
        {
          rows: [
            {
              id: "payment-a",
              student_id: "student-a",
              amount: "8000.00",
              currency: "RUB",
              payment_date: "2026-07-18T10:00:00.000Z",
              method: null,
              notes: "Покупка абонемента",
            },
          ],
        },
        {
          rows: [
            {
              id: "subscription-a",
              student_id: "student-a",
              lessons_total: "8",
              lessons_used: "0",
              starts_at: "2026-07-18",
              expires_at: "2026-09-16",
              status: "active",
              package_id: "pkg-a",
              payment_id: "payment-a",
            },
          ],
        },
        { rows: [] }, // create canonical payment record
        { rows: [] }, // create subscription obligation debit
        { rows: [] }, // link actual payment to canonical record
        { rows: [] }, // append payment status event
        { rows: [] }, // initialize payment and subscription aggregates
        { rows: [] }, // append subscription lifecycle event
        {
          rows: [
            {
              id: "student-a",
              lead_id: "lead-a",
              status: "active",
              custom_data: {
                discipline: "Фортепиано",
                sourceLeadId: "lead-a",
              },
              profile_id: "profile-client",
              profile_user_id: "client-a",
              first_name: "Анна",
              last_name: "Иванова",
              email: "anna@example.com",
              phone: "+79990000000",
              created_at: "2026-07-18T10:00:00.000Z",
            },
          ],
        },
        { rows: [{ user_id: "client-a" }] }, // student realtime audience
        {
          rows: [{ user_id: "client-a" }, { user_id: "teacher-user" }],
        }, // converted lesson audience
        {
          rows: [{ user_id: "client-a" }, { user_id: "teacher-user" }],
        }, // converted homework audience
        {
          rows: [{ user_id: "client-a" }],
        }, // finance audience: active Client accounts only
      ]);

    await expect(
      service.issueLeadSubscription(actor, "lead-a", { packageId: "pkg-a" }),
    ).resolves.toEqual({
      student: expect.objectContaining({ id: "student-a", leadId: "lead-a" }),
      subscription: expect.objectContaining({
        id: "subscription-a",
        packageId: "pkg-a",
        paymentId: "payment-a",
      }),
      payment: expect.objectContaining({ id: "payment-a", amount: 8000 }),
      converted: true,
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(String(query.mock.calls[0][0])).toContain("pg_advisory_xact_lock");
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes(
          "set student_id = $2, lead_id = null, updated_at = now()",
        ),
      ),
    ).toBe(true);
    const chatRebind = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.chats chat"),
    );
    expect(chatRebind).toBeDefined();
    expect(chatRebind?.[1]).toEqual(["lead-a", "student-a"]);
    const chatRebindSql = String(chatRebind?.[0]);
    expect(chatRebindSql).toContain("chat.lead_id = $1");
    expect(chatRebindSql).toContain("chat.type = 'administration'");
    expect(chatRebindSql).toContain("link.user_id = chat.owner_user_id");
    expect(chatRebindSql).toContain("link.entity_type = 'lead'");
    expect(chatRebindSql).toContain("link.entity_id = $1");
    expect(chatRebindSql).toContain(
      "chat.slug is distinct from 'announcements'",
    );
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("conversion_lead_id"),
      ),
    ).toBe(true);
    const subscriptionInsert = query.mock.calls.find((call) =>
      String(call[0]).includes("insert into app.subscriptions"),
    );
    expect(String(subscriptionInsert?.[0])).toContain("payer_student_id");
    expect(String(subscriptionInsert?.[0])).toContain("funding_mode");
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.client_payment_records"),
      ),
    ).toBe(true);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes(
          "insert into app.subscription_obligation_facts",
        ),
      ),
    ).toBe(true);
    const paymentLink = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.payments"),
    );
    expect(String(paymentLink?.[0])).toContain("issued_subscription_id");
    expect(paymentLink?.[1]).toEqual(["payment-a", "subscription-a"]);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("commerce:issued-subscription"),
      ),
    ).toBe(true);
    expect(String(query.mock.calls[6][0])).toContain("updated_profile as");
    const linkedProfileParams = query.mock.calls[6][1] as unknown[];
    expect(linkedProfileParams[0]).toBe("profile-client");
    expect(linkedProfileParams[3]).toBe("+79990000000");
    expect(linkedProfileParams[4]).toBe("lead-a");
    expect(JSON.parse(String(linkedProfileParams[5]))).toMatchObject({
      sourceLeadId: "lead-a",
      sourceLeadEmail: "anna@example.com",
      appealAt: "2026-07-18T09:00:00.000Z",
    });
    expect(linkedProfileParams[6]).toBe("branch-a");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_created",
        metadata: { leadId: "lead-a", trigger: "subscription" },
      }),
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_issued",
        metadata: expect.objectContaining({ leadId: "lead-a" }),
      }),
    );
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith(
      expect.objectContaining({
        entity: "lesson",
        id: "trial-a",
        affectedUserIds: ["client-a", "teacher-user"],
      }),
    );
    expect(realtime.emitFinanceChanged).toHaveBeenCalledWith(["client-a"]);
    expect(realtime.emitFinanceChanged).not.toHaveBeenCalledWith(
      expect.arrayContaining(["teacher-user"]),
    );
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith(
      expect.objectContaining({
        entity: "homework",
        id: "hw-trial",
        affectedUserIds: ["client-a", "teacher-user"],
      }),
    );
  });

  it("keeps generic issuance available for legacy students linked to leads", async () => {
    const { service, query, transaction, audit } =
      createServiceWithQueryResults([
        {
          // Imported students commonly retain lead_id but predate the durable
          // conversion marker introduced by migration 0072.
          rows: [{ id: "student-a", lead_id: "lead-a" }],
        },
        {
          rows: [
            {
              id: "sub-a",
              lessons_total: 8,
              lessons_used: 0,
              starts_at: "2026-07-18",
              expires_at: "2026-09-16",
              status: "active",
              package_id: "pkg-a",
              payment_id: "pay-a",
            },
          ],
        },
        { rows: [] },
      ]);

    await expect(
      service.issueSubscription(actor, "student-a", { packageId: "pkg-a" }),
    ).resolves.toEqual(
      expect.objectContaining({
        id: "sub-a",
        studentId: "student-a",
        packageId: "pkg-a",
        paymentId: "pay-a",
      }),
    );
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(String(query.mock.calls[0][0])).toContain("select student.id");
    expect(String(query.mock.calls[0][0])).not.toContain("conversion_lead_id");
    expect(String(query.mock.calls[1][0])).toContain(
      "insert into app.payments",
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_issued",
        entityId: "student-a",
        metadata: expect.objectContaining({ subscriptionId: "sub-a" }),
      }),
    );
  });

  it("returns the original lead issuance on retry and rejects a different package", async () => {
    const existing = {
      id: "student-a",
      lead_id: "lead-a",
      status: "active",
      custom_data: {},
      profile_id: "profile-a",
      profile_user_id: "client-a",
      first_name: "Анна",
      last_name: "Иванова",
      email: "anna@example.com",
      phone: null,
      created_at: "2026-07-18T10:00:00.000Z",
      subscription_id: "subscription-a",
      lessons_total: "8",
      lessons_used: "0",
      starts_at: "2026-07-18",
      expires_at: null,
      subscription_status: "active",
      package_id: "pkg-a",
      payment_id: "payment-a",
      payment_amount: "8000.00",
      payment_currency: "RUB",
      payment_date: "2026-07-18T10:00:00.000Z",
      payment_method: null,
      payment_notes: "Покупка абонемента",
    };
    const retry = createServiceWithQueryResults([
      { rows: [] },
      { rows: [existing] },
    ]);

    await expect(
      retry.service.issueLeadSubscription(actor, "lead-a", {
        packageId: "pkg-a",
      }),
    ).resolves.toMatchObject({
      subscription: { id: "subscription-a" },
      payment: { id: "payment-a", amount: 8000 },
      converted: false,
    });
    expect(retry.audit.record).not.toHaveBeenCalled();
    expect(
      retry.query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.payments"),
      ),
    ).toBe(false);

    const mismatch = createServiceWithQueryResults([
      { rows: [] },
      { rows: [existing] },
    ]);
    await expect(
      mismatch.service.issueLeadSubscription(actor, "lead-a", {
        packageId: "pkg-other",
      }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("keeps lead subscription conversion behind the CRM write actor matrix", async () => {
    const { service, policy, transaction } = createServiceWithQueryResults([]);
    policy.assertCanWriteCrm.mockImplementation((candidate) => {
      if (candidate.role === "client" || candidate.role === "teacher") {
        throw new ForbiddenException();
      }
    });

    await expect(
      service.issueLeadSubscription(
        { userId: "client-a", role: "client" },
        "lead-a",
        { packageId: "pkg-a" },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.issueLeadSubscription(
        { userId: "teacher-a", role: "teacher" },
        "lead-a",
        { packageId: "pkg-a" },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(transaction).not.toHaveBeenCalled();
  });

  describe("«Оплачено» по абонементу — из личного счёта", () => {
    it("читает приход, которым закрыт абонемент", async () => {
      const { service, query } = createService([
        {
          id: "sub-a",
          student_id: "student-a",
          student_user_id: "client-a",
          lessons_total: 10,
          lessons_used: 0,
          starts_at: null,
          expires_at: null,
          status: "active",
          created_at: "2026-06-01T00:00:00.000Z",
          updated_at: "2026-06-01T00:00:00.000Z",
          package_name: "10 занятий",
          package_price: "7000",
          paid_amount: "8000",
        },
      ]);

      const result = await service.listSubscriptions(schoolActor, { limit: 1 });

      // ✔ Решение владельца: оплату по абонементу считаем по личному счёту.
      // Выдача абонемента кладёт его стоимость на счёт (issueSubscription), и
      // «Оплачено» — это тот самый приход, а не отдельная сущность.
      expect(result.items[0]).toEqual(
        expect.objectContaining({ packagePrice: 7000, paidAmount: 8000 }),
      );
      // Переплата = 8000 − 7000 считается из этих двух чисел.
    });

    it("берёт приход из личного счёта, а не из отдельной таблицы", async () => {
      const { service, query } = createService([]);

      await service.listSubscriptions(schoolActor, { limit: 1 });

      const sql = String(query.mock.calls[0][0]);
      // Строки в этих тестах замоканы, SQL не исполняется — поэтому сам запрос
      // проверяем текстом: и join, и то, что сумма берётся именно из прихода.
      expect(sql).toContain("left join app.commerce_ordinary_payments pay");
      expect(sql).toContain("pay.amount as paid_amount");
      // Отменённый платёж — не оплата.
      expect(sql).toContain("pay.deleted_at is null");
    });
  });
});
