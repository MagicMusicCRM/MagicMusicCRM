import { Injectable } from '@nestjs/common';
import {
  LessonCompletionWorkerMetrics
} from '../crm/schedule/completion-worker.types';
import { LessonCompletionWorker } from '../crm/schedule/lesson-completion.worker';
import { DatabaseService } from '../db/database.service';
import {
  V4DomainFlagsService,
  V4DomainRollout
} from '../platform/v4-domain-flags';
import { PlatformOutboxWorker } from '../platform/platform-outbox.worker';
import { PlatformOutboxMetrics } from '../platform/platform-integrity.types';

export interface HealthResponse {
  status: 'ok';
  service: 'magic-music-crm-api';
  timestamp: string;
}

export interface ReadinessResponse extends Omit<HealthResponse, 'status'> {
  status: 'ok' | 'degraded';
  checks: {
    database: 'ok' | 'error';
    migrations: 'ok' | 'error';
    lessonCompletionWorker: 'ok' | 'degraded';
    platformOutbox: 'ok' | 'degraded';
    v4Rollout: 'ok' | 'blocked';
  };
  latestMigrationId: string | null;
  lessonCompletionWorker: LessonCompletionWorkerMetrics;
  platformOutbox: PlatformOutboxMetrics;
  v4Rollout: V4DomainRollout[];
}

@Injectable()
export class HealthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly lessonCompletionWorker: LessonCompletionWorker,
    private readonly v4DomainFlags: V4DomainFlagsService,
    private readonly platformOutboxWorker: PlatformOutboxWorker
  ) {}

  check(): HealthResponse {
    return {
      status: 'ok',
      service: 'magic-music-crm-api',
      timestamp: new Date().toISOString()
    };
  }

  live(): HealthResponse {
    return this.check();
  }

  async ready(): Promise<ReadinessResponse> {
    const [result, workerHealth, outboxHealth] = await Promise.all([
      this.database.query<{ id: string | null }>(
        `
          select id
          from app_schema_migrations
          order by applied_at desc
          limit 1
        `
      ),
      this.lessonCompletionWorker.health(),
      this.platformOutboxWorker.health()
    ]);
    const latestMigrationId = result.rows[0]?.id ?? null;
    const v4Rollout = this.v4DomainFlags.snapshot();
    const v4Blocked = v4Rollout.some(
      domain => domain.configuredMode === 'v4' && !domain.enableAllowed
    );

    const checks: ReadinessResponse['checks'] = {
      database: 'ok',
      migrations: latestMigrationId === null ? 'error' : 'ok',
      lessonCompletionWorker: workerHealth.status,
      platformOutbox: outboxHealth.status,
      v4Rollout: v4Blocked ? 'blocked' : 'ok'
    };
    const ready = Object.values(checks).every(check => check === 'ok');

    return {
      ...this.check(),
      status: ready ? 'ok' : 'degraded',
      checks,
      latestMigrationId,
      lessonCompletionWorker: workerHealth.metrics,
      platformOutbox: outboxHealth.metrics,
      v4Rollout
    };
  }
}
