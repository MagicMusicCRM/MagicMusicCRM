import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { NotificationsService } from "../../notifications/notifications.service";
import {
  InstallmentPaymentReminderRow,
  PaymentLifecycleRepository,
} from "./payment-lifecycle.repository";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const DEFAULT_POLL_MS = 60_000;
const DEFAULT_BATCH_SIZE = 50;

@Injectable()
export class InstallmentDueWorker implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(InstallmentDueWorker.name);
  private readonly workerId = `installment-due-${randomUUID()}`;
  private timer?: ReturnType<typeof setInterval>;
  private running = false;

  constructor(
    private readonly repository: PaymentLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
    private readonly notifications: NotificationsService,
  ) {}

  onModuleInit(): void {
    if (process.env.INSTALLMENT_DUE_WORKER_ENABLED !== "true") return;
    const pollMs = envInteger(
      "INSTALLMENT_DUE_WORKER_POLL_MS",
      DEFAULT_POLL_MS,
      1_000,
      3_600_000,
    );
    this.timer = setInterval(() => void this.tick(), pollMs);
    this.timer.unref?.();
    void this.tick();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  async runOnce(
    now = new Date(),
    limit = DEFAULT_BATCH_SIZE,
  ): Promise<number> {
    const rows = await this.repository.materializeDueInstallments(now, limit);
    await Promise.all(
      rows.map((item) =>
        this.reservations.publishPostCommit({
          studentId: item.recipientStudentId,
          payerStudentId: item.payerStudentId,
          subscriptionId: item.issuedSubscriptionId,
        }),
      ),
    );
    return rows.length;
  }

  async runReminderOnce(
    now = new Date(),
    options: {
      limit?: number;
      leaseSeconds?: number;
      maxAttempts?: number;
      backoffBaseSeconds?: number;
      backoffCapSeconds?: number;
    } = {},
  ) {
    const limit = options.limit ?? DEFAULT_BATCH_SIZE;
    const maxAttempts = options.maxAttempts ?? 5;
    const materialized =
      await this.repository.materializeInstallmentPaymentReminders(now, limit);
    const reminders =
      await this.repository.claimInstallmentPaymentReminders(this.workerId, {
        limit,
        leaseSeconds: options.leaseSeconds ?? 300,
        maxAttempts,
      });
    let delivered = 0;
    let retried = 0;
    let poison = 0;
    for (const reminder of reminders) {
      try {
        for (const userId of reminder.recipient_user_ids) {
          await this.deliverReminder(userId, reminder);
        }
        await this.repository.markInstallmentPaymentReminderDelivered(
          reminder.id,
          this.workerId,
        );
        delivered += 1;
      } catch (error) {
        await this.repository.markInstallmentPaymentReminderFailed(
          reminder,
          this.workerId,
          this.errorName(error),
          {
            maxAttempts,
            baseSeconds: options.backoffBaseSeconds ?? 30,
            capSeconds: options.backoffCapSeconds ?? 3600,
          },
        );
        if (Number(reminder.attempts) >= maxAttempts) poison += 1;
        else retried += 1;
      }
    }
    const metrics =
      (await this.repository.installmentPaymentReminderMetrics()).rows[0];
    return {
      materialized,
      claimed: reminders.length,
      delivered,
      retried,
      poison,
      metrics: {
        pending: metrics?.pending ?? 0,
        poison: metrics?.poison ?? 0,
        oldestCreatedAt: metrics?.oldest_created_at ?? null,
      },
    };
  }

  private async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      try {
        const reminder = await this.runReminderOnce();
        if (reminder.delivered > 0) {
          this.logger.log(
            `Delivered ${reminder.delivered} installment payment reminders`,
          );
        }
      } catch (error) {
        this.logger.error(
          `Installment reminder tick failed: ${this.errorName(error)}`,
        );
      }
      try {
        const count = await this.runOnce();
        if (count > 0) this.logger.log(`Created ${count} due payment records`);
      } catch (error) {
        this.logger.error(`Installment due tick failed: ${this.errorName(error)}`);
      }
    } finally {
      this.running = false;
    }
  }

  private deliverReminder(
    userId: string,
    reminder: InstallmentPaymentReminderRow,
  ) {
    const dueDate = new Intl.DateTimeFormat("ru-RU", {
      day: "2-digit",
      month: "long",
      year: "numeric",
      timeZone: "Europe/Moscow",
    }).format(new Date(reminder.due_at));
    const amount = new Intl.NumberFormat("ru-RU", {
      style: "currency",
      currency: reminder.currency_code,
      maximumFractionDigits: 2,
    }).format(Number(reminder.amount_minor) / 100);
    return this.notifications.notifyUser({
      userId,
      title: "Напоминание об оплате",
      body: `Платёж по рассрочке ${amount} ожидается ${dueDate}.`,
      data: {
        entityType: "subscription",
        entityId: reminder.issued_subscription_id,
      },
      channels: ["in_app", "push"],
      notificationId: this.notificationId(reminder.id, userId),
    });
  }

  private notificationId(reminderId: string, userId: string): string {
    const digest = createHash("sha256")
      .update(`installment-payment-reminder\0${reminderId}\0${userId}`)
      .digest("hex");
    const variant = ((Number.parseInt(digest[16]!, 16) & 0x3) | 0x8).toString(
      16,
    );
    return `${digest.slice(0, 8)}-${digest.slice(8, 12)}-5${digest.slice(13, 16)}-${variant}${digest.slice(17, 20)}-${digest.slice(20, 32)}`;
  }

  private errorName(error: unknown): string {
    return error instanceof Error && error.name
      ? error.name.slice(0, 80)
      : "InstallmentReminderDeliveryError";
  }
}

function envInteger(
  key: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const value = Number(process.env[key]);
  return Number.isFinite(value)
    ? Math.min(maximum, Math.max(minimum, Math.floor(value)))
    : fallback;
}
