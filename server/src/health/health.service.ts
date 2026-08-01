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

export interface HealthResponse {
  status: 'ok';
  service: 'magic-music-crm-api';
  timestamp: string;
}

export interface ReadinessResponse extends HealthResponse {
  checks: {
    database: 'ok' | 'error';
    migrations: 'ok' | 'error';
    lessonCompletionWorker: 'ok' | 'degraded';
    v4Rollout: 'ok' | 'blocked';
  };
  latestMigrationId: string | null;
  lessonCompletionWorker: LessonCompletionWorkerMetrics;
  v4Rollout: V4DomainRollout[];
}

@Injectable()
export class HealthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly lessonCompletionWorker: LessonCompletionWorker,
    private readonly v4DomainFlags: V4DomainFlagsService
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
    const [result, workerHealth] = await Promise.all([
      this.database.query<{ id: string | null }>(
        `
          select id
          from app_schema_migrations
          order by applied_at desc
          limit 1
        `
      ),
      this.lessonCompletionWorker.health()
    ]);
    const latestMigrationId = result.rows[0]?.id ?? null;
    const v4Rollout = this.v4DomainFlags.snapshot();
    const v4Blocked = v4Rollout.some(
      domain => domain.configuredMode === 'v4' && !domain.enableAllowed
    );

    return {
      ...this.check(),
      checks: {
        database: 'ok',
        migrations: latestMigrationId === null ? 'error' : 'ok',
        lessonCompletionWorker: workerHealth.status,
        v4Rollout: v4Blocked ? 'blocked' : 'ok'
      },
      latestMigrationId,
      lessonCompletionWorker: workerHealth.metrics,
      v4Rollout
    };
  }
}
