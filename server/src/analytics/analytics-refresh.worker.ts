// server/src/analytics/analytics-refresh.worker.ts
import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";

const CHECK_INTERVAL_MS = 5 * 60_000;
const MATVIEWS = ["mv_finance_monthly", "mv_teacher_performance", "mv_room_load"] as const;

@Injectable()
export class AnalyticsRefreshWorker implements OnModuleInit, OnModuleDestroy {
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly database: DatabaseService) {}

  onModuleInit(): void {
    this.timer = setInterval(() => {
      void this.refreshNow().catch(() => undefined);
    }, CHECK_INTERVAL_MS);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  // Claim a refresh run (idempotent across instances/intervals); refresh the
  // matviews only if this caller wins the claim.
  async refreshNow(): Promise<{ refreshed: boolean }> {
    const claim = await this.database.query<{ id: string }>(
      `insert into app.analytics_refresh_runs (kind, status)
       select 'matviews', 'running'
       where not exists (
         select 1 from app.analytics_refresh_runs
          where kind = 'matviews'
            and (
              (status = 'completed' and finished_at > now() - interval '1 hour')
              or (status = 'running' and claimed_at > now() - interval '10 minutes')
            )
       )
       returning id`,
    );
    const runId = claim.rows[0]?.id;
    if (!runId) return { refreshed: false };
    try {
      for (const mv of MATVIEWS) {
        await this.database.query(`refresh materialized view app.${mv}`);
      }
      await this.database.query(
        `update app.analytics_refresh_runs set status = 'completed', ran_at = now(), finished_at = now() where id = $1`,
        [runId],
      );
      return { refreshed: true };
    } catch (error) {
      await this.database.query(
        `update app.analytics_refresh_runs set status = 'failed', finished_at = now(), error = $2 where id = $1`,
        [runId, error instanceof Error ? error.message : String(error)],
      );
      throw error;
    }
  }
}
