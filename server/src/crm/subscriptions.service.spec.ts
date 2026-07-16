import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { SubscriptionsService } from "./subscriptions.service";

describe("SubscriptionsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
    };
    const realtime = { emitCrmChanged: jest.fn() };

    const service = new SubscriptionsService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );

    return { service, query, audit, policy, realtime };
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
      service.listSubscriptions(
        { userId: "client-a", role: "client" },
        { studentId: "student-a", limit: 1 },
      ),
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
      "client",
      "client-a",
      "student-a",
      1,
    ]);
  });

  it("allows a client to list subscriptions for a manually linked student", async () => {
    const { service, query } = createService([
      {
        id: "sub-linked",
        student_id: "student-linked",
        student_user_id: null,
        lessons_total: 12,
        lessons_used: 0,
        starts_at: "2026-06-22",
        expires_at: "2026-08-22",
        status: "active",
        created_at: "2026-06-22T00:00:00.000Z",
        updated_at: "2026-06-22T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listSubscriptions(
        { userId: "client-linked", role: "client" },
        { studentId: "student-linked", limit: 1 },
      ),
    ).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "sub-linked",
          studentId: "student-linked",
          lessonsTotal: 12,
        }),
      ],
    });

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.user_crm_links");
    expect(sql).toContain("link.user_id = $2");
    expect(sql).toContain("link.entity_type = 'student'");
  });

  it("creates subscription packages through CRM write policy and audit (P5b)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "pkg-a",
        name: "8 уроков",
        discipline_id: null,
        branch_id: "branch-a",
        lessons_total: 8,
        price: "8000.00",
        validity_days: 60,
        is_active: true,
        sort_order: 0,
        created_at: "2026-06-22T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createSubscriptionPackage(actor, {
        name: " 8 уроков ",
        branchId: "branch-a",
        lessonsTotal: 8,
        price: 8000,
        validityDays: 60,
      }),
    ).resolves.toEqual({
      id: "pkg-a",
      name: "8 уроков",
      disciplineId: null,
      branchId: "branch-a",
      lessonsTotal: 8,
      price: 8000,
      validityDays: 60,
      isActive: true,
      sortOrder: 0,
      createdAt: "2026-06-22T00:00:00.000Z",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "8 уроков",
      null,
      "branch-a",
      8,
      8000,
      60,
      null,
      null,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_package_created",
        entityType: "subscription_package",
        entityId: "pkg-a",
      }),
    );
  });

  it("issues a subscription from a package atomically with audit (P5b)", async () => {
    const { service, query, audit, policy } = createService([
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
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("insert into app.payments");
    expect(sql).toContain("insert into app.subscriptions");
    expect(query.mock.calls[0][1]).toEqual(["student-a", "pkg-a", "manager-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.subscription_issued",
        entityType: "student",
        entityId: "student-a",
      }),
    );
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

      const result = await service.listSubscriptions(actor, { limit: 1 });

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

      await service.listSubscriptions(actor, { limit: 1 });

      const sql = String(query.mock.calls[0][0]);
      // Строки в этих тестах замоканы, SQL не исполняется — поэтому сам запрос
      // проверяем текстом: и join, и то, что сумма берётся именно из прихода.
      expect(sql).toContain("left join app.payments pay on pay.id = sub.payment_id");
      expect(sql).toContain("pay.amount as paid_amount");
      // Отменённый платёж — не оплата.
      expect(sql).toContain("pay.deleted_at is null");
    });
  });

});
