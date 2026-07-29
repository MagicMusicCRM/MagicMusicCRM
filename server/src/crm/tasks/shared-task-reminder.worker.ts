import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
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
    if (process.env.V4_SHARED_TASK_REMINDERS_ENABLED !== "true") return;
    this.timer = setInterval(() => {
      void this.dispatchDue(this.workerId).catch((error: unknown) => {
        this.logger.error(`Shared task reminder tick failed: ${this.errorName(error)}`);
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
        data: { taskId: reminder.task_id },
        channels: [channel],
      });
    } catch (error) {
      if (channel === "in_app") throw error;
      await this.notifications.notifyUser({
        userId,
        title: "Напоминание о задаче",
        body: "Открытая общая задача ожидает действия.",
        data: { taskId: reminder.task_id },
        channels: ["in_app"],
      });
    }
  }

  private errorName(error: unknown): string {
    return error instanceof Error ? error.name : "ReminderDeliveryError";
  }
}
