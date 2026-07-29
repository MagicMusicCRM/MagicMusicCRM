import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { hostname } from "node:os";
import {
  LessonCompletionRunResult,
  LessonCompletionWorkerMetrics,
} from "./completion-worker.types";
import { LessonCompletionWorkerRepository } from "./completion-worker.repository";
import { LessonCompletionService } from "./lesson-completion.service";

const DEFAULT_POLL_MS = 15_000;
const DEFAULT_BATCH_SIZE = 25;
const DEFAULT_LEASE_SECONDS = 60;
const DEFAULT_MAX_ATTEMPTS = 5;
const DEFAULT_BACKOFF_BASE_SECONDS = 5;
const DEFAULT_BACKOFF_CAP_SECONDS = 300;

@Injectable()
export class LessonCompletionWorker
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(LessonCompletionWorker.name);
  private readonly workerId =
    `${hostname()}:${process.pid}:${randomUUID()}`;
  private timer: ReturnType<typeof setInterval> | undefined;
  private startupTimer: ReturnType<typeof setTimeout> | undefined;
  private running = false;

  constructor(
    private readonly repository: LessonCompletionWorkerRepository,
    private readonly completion: LessonCompletionService,
  ) {}

  onModuleInit(): void {
    if (process.env.LESSON_COMPLETION_WORKER_ENABLED !== "true") {
      this.logger.log("Lesson completion worker disabled");
      return;
    }
    const pollMs = envInteger(
      "LESSON_COMPLETION_WORKER_POLL_MS",
      DEFAULT_POLL_MS,
      1_000,
      60_000,
    );
    const tick = () => {
      void this.tick().catch((error: unknown) => {
        this.logger.error(
          `Lesson completion tick failed: ${failureName(error)}`,
        );
      });
    };
    this.startupTimer = setTimeout(tick, Math.min(1_000, pollMs));
    this.startupTimer.unref?.();
    this.timer = setInterval(tick, pollMs);
    this.timer.unref?.();
    this.logger.log(`Lesson completion worker started (every ${pollMs}ms)`);
  }

  onModuleDestroy(): void {
    if (this.startupTimer) clearTimeout(this.startupTimer);
    if (this.timer) clearInterval(this.timer);
  }

  async runOnce(
    options: {
      workerId?: string;
      limit?: number;
      leaseSeconds?: number;
      maxAttempts?: number;
      backoffBaseSeconds?: number;
      backoffCapSeconds?: number;
    } = {},
  ): Promise<LessonCompletionRunResult> {
    const workerId = options.workerId ?? this.workerId;
    const maxAttempts =
      options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
    const claims = await this.repository.claimDue(workerId, {
      limit: options.limit ?? DEFAULT_BATCH_SIZE,
      leaseSeconds: options.leaseSeconds ?? DEFAULT_LEASE_SECONDS,
      maxAttempts,
    });
    const result: LessonCompletionRunResult = {
      claimed: claims.length,
      completed: 0,
      terminalObserved: 0,
      retry: 0,
      poison: 0,
    };
    for (const claim of claims) {
      try {
        await this.completion.complete(claim);
        result.completed += 1;
      } catch (error) {
        if (await this.repository.markTerminalObserved(claim)) {
          result.terminalObserved += 1;
          continue;
        }
        const failed = await this.repository.markFailed(claim, error, {
          baseSeconds:
            options.backoffBaseSeconds ??
            DEFAULT_BACKOFF_BASE_SECONDS,
          capSeconds:
            options.backoffCapSeconds ??
            DEFAULT_BACKOFF_CAP_SECONDS,
          maxAttempts,
        });
        if (failed === "retry") result.retry += 1;
        if (failed === "poison") {
          result.poison += 1;
          this.logger.error(
            `Poison Lesson completion work: lesson=${claim.lessonId} attempts=${claim.attempts} error=${failureName(error)}`,
          );
        }
      }
    }
    return result;
  }

  metrics(): Promise<LessonCompletionWorkerMetrics> {
    return this.repository.metrics();
  }

  async health(): Promise<{
    status: "ok" | "degraded";
    metrics: LessonCompletionWorkerMetrics;
  }> {
    const metrics = await this.metrics();
    return {
      status:
        metrics.poison > 0 ||
        (metrics.oldestDueSeconds !== null &&
          metrics.oldestDueSeconds > 120)
          ? "degraded"
          : "ok",
      metrics,
    };
  }

  private async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const result = await this.runOnce();
      if (result.completed > 0 || result.poison > 0) {
        this.logger.log(
          `Lesson completion run: claimed=${result.claimed} completed=${result.completed} retry=${result.retry} poison=${result.poison}`,
        );
      }
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
  const parsed = Number(process.env[key]);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.floor(parsed)));
}

function failureName(error: unknown): string {
  return error instanceof Error && error.name
    ? error.name.slice(0, 120)
    : "LessonCompletionFailure";
}
