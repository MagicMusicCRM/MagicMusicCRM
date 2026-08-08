import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { hostname } from "node:os";
import {
  CrmChangedPayload,
  CrmEntity,
  RealtimeBus,
} from "../realtime/realtime-bus";
import { PlatformIntegrityService } from "./platform-integrity.service";
import {
  ClaimedOutboxEvent,
  PlatformOutboxMetrics,
} from "./platform-integrity.types";

const POLL_MS = 5_000;
const HEALTH_MAX_AGE_SECONDS = 120;

@Injectable()
export class PlatformOutboxWorker implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PlatformOutboxWorker.name);
  private readonly workerId = `${hostname()}:${process.pid}:${randomUUID()}`;
  private timer?: ReturnType<typeof setInterval>;
  private startupTimer?: ReturnType<typeof setTimeout>;
  private running = false;

  constructor(
    private readonly integrity: PlatformIntegrityService,
    private readonly realtime: RealtimeBus,
  ) {}

  onModuleInit(): void {
    if (process.env.PLATFORM_OUTBOX_WORKER_ENABLED === "false") return;
    if (
      process.env.NODE_ENV === "test" &&
      process.env.PLATFORM_OUTBOX_WORKER_ENABLED !== "true"
    ) {
      return;
    }
    const tick = () => {
      void this.tick().catch((error: unknown) => {
        this.logger.error(`Platform outbox tick failed: ${failureName(error)}`);
      });
    };
    this.startupTimer = setTimeout(tick, 1_000);
    this.startupTimer.unref?.();
    this.timer = setInterval(tick, POLL_MS);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.startupTimer) clearTimeout(this.startupTimer);
    if (this.timer) clearInterval(this.timer);
  }

  async runOnce(workerId = this.workerId): Promise<{
    claimed: number;
    published: number;
    retry: number;
    deadLetter: number;
  }> {
    const events = await this.integrity.claimOutbox(workerId);
    const result = {
      claimed: events.length,
      published: 0,
      retry: 0,
      deadLetter: 0,
    };
    for (const event of events) {
      try {
        this.dispatch(event);
        if (await this.integrity.markOutboxPublished(event.eventId, workerId)) {
          result.published += 1;
        }
      } catch (error) {
        const failed = await this.integrity.markOutboxFailed(
          event,
          workerId,
          error,
        );
        if (failed === "retry") result.retry += 1;
        if (failed === "dead-letter") result.deadLetter += 1;
      }
    }
    return result;
  }

  async health(): Promise<{
    status: "ok" | "degraded";
    metrics: PlatformOutboxMetrics;
  }> {
    const metrics = await this.integrity.outboxMetrics();
    return {
      status:
        metrics.deadLetter > 0 ||
        (metrics.oldestDueSeconds !== null &&
          metrics.oldestDueSeconds > HEALTH_MAX_AGE_SECONDS)
          ? "degraded"
          : "ok",
      metrics,
    };
  }

  private dispatch(event: ClaimedOutboxEvent): void {
    if (!this.realtime.isReady()) {
      throw new Error("RealtimeBusUnavailable");
    }
    if (event.type === "access.invalidated") {
      this.realtime.emitUserAccessInvalidated(
        requiredString(event.payload.entityId, event.type),
        event.aggregateVersion,
      );
      return;
    }
    if (event.type === "access.package.changed") {
      this.realtime.emitRoleAccessInvalidated(
        requiredString(event.payload.scope, event.type),
        event.aggregateVersion,
      );
      return;
    }

    const entity = entityFor(event);
    if (event.type.startsWith("commerce.")) {
      this.realtime.emitFinanceChanged(stringList(event.payload.affectedUserIds));
    }
    this.realtime.emitCrmChanged({
      entity,
      action: actionFor(event),
      id: event.type === "schedule.lessons.changed" ? null : eventId(event),
      branchId: optionalString(event.payload.branchId),
      affectedUserIds: stringList(event.payload.affectedUserIds),
    } satisfies CrmChangedPayload);
  }

  private async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const result = await this.runOnce();
      if (result.retry > 0 || result.deadLetter > 0) {
        this.logger.warn(
          `Platform outbox run: claimed=${result.claimed} published=${result.published} retry=${result.retry} deadLetter=${result.deadLetter}`,
        );
      } else if (result.published > 0) {
        this.logger.log(
          `Platform outbox run: claimed=${result.claimed} published=${result.published} retry=${result.retry} deadLetter=${result.deadLetter}`,
        );
      }
    } finally {
      this.running = false;
    }
  }
}

function entityFor(event: ClaimedOutboxEvent): CrmEntity {
  if (event.type.startsWith("commerce.payment")) return "payment";
  if (
    event.type.startsWith("commerce.subscription") ||
    event.type.startsWith("commerce.package")
  ) {
    return "subscription";
  }
  if (event.type.startsWith("schedule.")) return "lesson";
  if (event.type.startsWith("workflow.task.")) return "task";
  if (event.type === "crm.comment.teacher-sharing.changed") return "comment";
  if (event.type === "inbound.lead.created") return "lead";
  if (event.type === "crm.client.archived") {
    return event.aggregateType.includes("student") ? "student" : "lead";
  }
  throw new Error(`UnsupportedPlatformEvent:${event.type.slice(0, 80)}`);
}

function actionFor(event: ClaimedOutboxEvent): CrmChangedPayload["action"] {
  const action = optionalString(event.payload.action);
  if (action === "created" || action === "updated" || action === "deleted" || action === "moved") {
    return action;
  }
  if (event.type.endsWith(".created")) return "created";
  return "updated";
}

function eventId(event: ClaimedOutboxEvent): string {
  return (
    optionalString(event.payload.entityId) ??
    optionalString(event.payload.taskId) ??
    optionalString(event.payload.lessonId) ??
    event.aggregateId
  );
}

function requiredString(value: unknown, eventType: string): string {
  const result = optionalString(value);
  if (!result) throw new Error(`InvalidPlatformEvent:${eventType.slice(0, 80)}`);
  return result;
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function stringList(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string" && !!item)
    : [];
}

function failureName(error: unknown): string {
  return error instanceof Error && error.name
    ? error.name.slice(0, 120)
    : "PlatformOutboxFailure";
}
