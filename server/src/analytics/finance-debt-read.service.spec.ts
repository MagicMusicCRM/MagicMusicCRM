import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { FinanceDebtReadService } from "./finance-debt-read.service";

const director: ActorContext = {
  userId: "11111111-1111-4111-8111-111111111111",
  role: "director",
};

describe("FinanceDebtReadService", () => {
  it("separates actual receipts, real overdue and consumption forecast", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          {
            role: "director",
            active: true,
            definition_active: true,
            definition_override_mode: "locked",
            role_effect: "allow",
            override_effect: null,
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [{ receipts_minor: "720000" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            remaining_minor: "720000",
            overdue_minor: "0",
            forecast_minor: "720000",
            paid_unused_units: "6",
            overdue_clients: "0",
          },
        ],
      });
    const service = new FinanceDebtReadService({
      query,
    } as unknown as DatabaseService);

    const result = await service.summary(director, {
      from: "2026-09-01T00:00:00.000Z",
      to: "2026-10-01T00:00:00.000Z",
    });

    expect(result).toMatchObject({
      receiptsMinor: "720000",
      remainingMinor: "720000",
      overdueMinor: "0",
      forecastMinor: "720000",
      paidUnusedUnits: "6",
      overdueClients: 0,
      currencyCode: "RUB",
    });
    const sql = query.mock.calls.map((call) => String(call[0])).join("\n");
    expect(sql).toContain("commerce_ordinary_payments");
    expect(sql).toContain("commerce_ordinary_account_adjustments");
    expect(sql).toContain("subscription_installment_due_facts");
    expect(sql).toContain("position.due_policy = 'calendar'");
    expect(sql).toContain("due_fact.due_at");
    expect(sql).toContain("lesson_client_charge_facts_effective");
    expect(sql).toContain("reservation.state = 'reserved'");
  });

  it("returns linked subscriptions, clients, payments, tasks and owners", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          {
            role: "director",
            active: true,
            definition_active: true,
            definition_override_mode: "locked",
            role_effect: "allow",
            override_effect: null,
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            subscription_id: "22222222-2222-4222-8222-222222222222",
            student_id: "33333333-3333-4333-8333-333333333333",
            client_id: "44444444-4444-4444-8444-444444444444",
            display_name: "Анна Иванова",
            package_name: "Вокал 8",
            owner_user_id: "55555555-5555-4555-8555-555555555555",
            owner_name: "Ольга Смирнова",
            remaining_minor: "720000",
            overdue_minor: "720000",
            forecast_minor: "0",
            paid_unused_units: "0",
            next_due_at: "2026-09-10T00:00:00.000Z",
            next_due_is_forecast: false,
            latest_payment_id: "66666666-6666-4666-8666-666666666666",
            next_task_id: "77777777-7777-4777-8777-777777777777",
            next_task_title: "Связаться по оплате",
            next_task_at: "2026-09-22T09:00:00.000Z",
            total_count: "1",
          },
        ],
      });
    const service = new FinanceDebtReadService({
      query,
    } as unknown as DatabaseService);

    const result = await service.list(director, {
      segment: "overdue",
      limit: 50,
      offset: 0,
    });

    expect(result.items[0]).toMatchObject({
      displayName: "Анна Иванова",
      clientLink: {
        entityType: "student",
        entityId: "33333333-3333-4333-8333-333333333333",
      },
      subscriptionLink: {
        entityType: "subscription",
        entityId: "22222222-2222-4222-8222-222222222222",
      },
      paymentLink: {
        entityType: "payment",
        entityId: "66666666-6666-4666-8666-666666666666",
      },
      nextTask: {
        id: "77777777-7777-4777-8777-777777777777",
        title: "Связаться по оплате",
        entityLink: {
          entityType: "task",
          entityId: "77777777-7777-4777-8777-777777777777",
        },
      },
    });
  });
});
