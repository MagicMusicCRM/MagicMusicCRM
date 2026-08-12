import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { NotificationsService } from "../../notifications/notifications.service";
import { NotificationChannel } from "../../notifications/notifications.types";
import { SharedTaskRepository } from "./shared-task.repository";
import { SharedTaskReminderRow } from "./shared-task.types";

@Injectable()
export class SharedTaskReminderWorker implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SharedTaskReminderWorker.name);
  private readonly workerId = `shared-task-${randomUUID()}`;
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly repository: SharedTaskRepository,
    private readonly notifications: NotificationsService,
  ) {}

  onModuleInit(): void {
    if (process.env.TASK_REMINDERS_ENABLED !== "true") return;
    this.timer = setInterval(() => {
      void this.dispatchDue(this.workerId).catch((error: unknown) => {
        this.logger.error(
          `Shared task reminder tick failed: ${this.errorName(error)}`,
        );
      });
    }, 30_000);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  async dispatchDue(
    workerId: string,
    options: {
      limit?: number;
      leaseSeconds?: number;
      maxAttempts?: number;
      backoffBaseSeconds?: number;
      backoffCapSeconds?: number;
    } = {},
  ) {
    const maxAttempts = options.maxAttempts ?? 5;
    const reminders = await this.repository.claimDueReminders(workerId, {
      limit: options.limit ?? 50,
      leaseSeconds: options.leaseSeconds ?? 300,
      maxAttempts,
    });
    let delivered = 0;
    let retried = 0;
    let poison = 0;
    for (const reminder of reminders) {
      try {
        const recipients = await this.repository.reminderRecipients(
          reminder.task_id,
        );
        for (const recipient of recipients.rows) {
          await this.deliver(recipient.user_id, reminder);
        }
        await this.repository.markReminderDelivered(reminder.id, workerId);
        delivered += 1;
      } catch (error) {
        await this.repository.markReminderFailed(
          reminder,
          workerId,
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
    const metrics = (await this.repository.reminderMetrics()).rows[0];
    return {
      claimed: reminders.length,
      delivered,
      retried,
      poison,
      metrics: {
        pending: metrics?.pending ?? 0,
        poison: metrics?.poison ?? 0,
        oldestDueAt: metrics?.oldest_due_at ?? null,
      },
    };
  }

  private async deliver(userId: string, reminder: SharedTaskReminderRow) {
    const channel = reminder.channel as NotificationChannel;
    try {
      await this.notifications.notifyUser({
        userId,
        title: "Напоминание о задаче",
        body: "Открытая общая задача ожидает действия.",
        data: { entityType: "task", entityId: reminder.task_id },
        channels: [channel],
        notificationId: this.notificationId(reminder, userId),
      });
    } catch (error) {
      if (channel === "in_app") throw error;
      await this.notifications.notifyUser({
        userId,
        title: "Напоминание о задаче",
        body: "Открытая общая задача ожидает действия.",
        data: { entityType: "task", entityId: reminder.task_id },
        channels: ["in_app"],
        notificationId: this.notificationId(reminder, userId),
      });
    }
  }

  private notificationId(
    reminder: SharedTaskReminderRow,
    userId: string,
  ): string {
    const digest = createHash("sha256")
      .update(`shared-task-reminder\0${reminder.id}\0${userId}`)
      .digest("hex");
    const variant = ((Number.parseInt(digest[16]!, 16) & 0x3) | 0x8).toString(
      16,
    );
    return `${digest.slice(0, 8)}-${digest.slice(8, 12)}-5${digest.slice(13, 16)}-${variant}${digest.slice(17, 20)}-${digest.slice(20, 32)}`;
  }

  private errorName(error: unknown): string {
    return error instanceof Error ? error.name : "ReminderDeliveryError";
  }
}
