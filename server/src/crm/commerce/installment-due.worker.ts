import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { PaymentLifecycleRepository } from "./payment-lifecycle.repository";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const DEFAULT_POLL_MS = 60_000;
const DEFAULT_BATCH_SIZE = 50;

@Injectable()
export class InstallmentDueWorker implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(InstallmentDueWorker.name);
  private timer?: ReturnType<typeof setInterval>;
  private running = false;

  constructor(
    private readonly repository: PaymentLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
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

  private async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const count = await this.runOnce();
      if (count > 0) this.logger.log(`Created ${count} due payment records`);
    } catch (error) {
      this.logger.error(`Installment due tick failed: ${String(error)}`);
    } finally {
      this.running = false;
    }
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
