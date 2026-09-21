import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { SalesClientsReadService } from "./sales-clients-read.service";

const actor: ActorContext = {
  userId: "11111111-1111-4111-8111-111111111111",
  role: "manager",
};

describe("SalesClientsReadService", () => {
  it("builds one 90-day cohort and never exposes amounts without finance access", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          {
            role: "manager",
            active: true,
            definition_active: true,
            definition_override_mode: "allow_deny",
            role_effect: "allow",
            override_effect: null,
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            role: "manager",
            active: true,
            definition_active: true,
            definition_override_mode: "locked",
            role_effect: "deny",
            override_effect: null,
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            inquiries: "4",
            trial_booked: "3",
            trial_attended: "2",
            trial_to_first_paid: "2",
            purchases: "2",
            first_paid_sales: "2",
            without_trial_sales: "1",
            stalled: "2",
            avg_days_to_trial: "4.5",
            avg_days_to_first_payment: "8.25",
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            source_id: null,
            source_label: "Источник не указан",
            inquiries: "4",
            trial_attended: "2",
            first_paid_sales: "2",
            first_payment_amount_minor: "900000",
          },
        ],
      });
    const service = new SalesClientsReadService({
      query,
    } as unknown as DatabaseService);

    const result = await service.summary(actor, {
      from: "2026-01-01T00:00:00.000Z",
      to: "2026-02-01T00:00:00.000Z",
    });

    expect(result).toMatchObject({
      observationDays: 90,
      funnel: {
        inquiries: 4,
        trialBooked: 3,
        trialAttended: 2,
        purchases: 2,
        firstPaidSales: 2,
        withoutTrialSales: 1,
        stalled: 2,
        conversionToFirstPayment: 0.5,
        trialToFirstPayment: 1,
      },
      speed: { averageDaysToTrial: 4.5, averageDaysToFirstPayment: 8.25 },
      sources: [
        expect.objectContaining({
          sourceId: null,
          inquiries: 4,
          firstPaidSales: 2,
          conversionToFirstPayment: 0.5,
        }),
      ],
    });
    expect(result.sources[0]).not.toHaveProperty("firstPaymentAmountMinor");
    const sql = query.mock.calls.map((call) => String(call[0])).join("\n");
    expect(sql).toContain("interval '90 days'");
    expect(sql).toContain("commerce_ordinary_payments");
    expect(sql).toContain("issued_subscription_id is not null");
    expect(sql).toContain("app.user_crm_links");
  });

  it("returns a fixed client drill-down with the next shared task", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          {
            role: "manager",
            active: true,
            definition_active: true,
            definition_override_mode: "allow_deny",
            role_effect: "allow",
            override_effect: null,
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            client_type: "student",
            client_id: "22222222-2222-4222-8222-222222222222",
            display_name: "Анна Иванова",
            source_label: "Сайт",
            stage_label: "Пробное посещено",
            inquiry_at: "2026-01-02T10:00:00.000Z",
            last_activity_at: "2026-01-10T10:00:00.000Z",
            trial_booked_at: "2026-01-05T10:00:00.000Z",
            trial_attended_at: "2026-01-05T10:00:00.000Z",
            purchased_at: null,
            first_paid_at: null,
            next_task_id: "33333333-3333-4333-8333-333333333333",
            next_task_title: "Связаться после пробного",
            next_task_at: "2026-01-12T10:00:00.000Z",
            total_count: "1",
          },
        ],
      });
    const service = new SalesClientsReadService({
      query,
    } as unknown as DatabaseService);

    const result = await service.list(actor, {
      from: "2026-01-01T00:00:00.000Z",
      to: "2026-02-01T00:00:00.000Z",
      segment: "stalled",
      limit: 50,
      offset: 0,
    });

    expect(result.total).toBe(1);
    expect(result.items).toEqual([
      expect.objectContaining({
        displayName: "Анна Иванова",
        entityLink: {
          entityType: "student",
          entityId: "22222222-2222-4222-8222-222222222222",
        },
        nextTask: expect.objectContaining({
          title: "Связаться после пробного",
          entityLink: {
            entityType: "task",
            entityId: "33333333-3333-4333-8333-333333333333",
          },
        }),
      }),
    ]);
    expect(String(query.mock.calls[1]![0])).toContain("first_paid_at is null");
  });
});
