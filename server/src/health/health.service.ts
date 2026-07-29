import { Injectable } from '@nestjs/common';
import {
  LessonCompletionWorkerMetrics
} from '../crm/schedule/completion-worker.types';
import { LessonCompletionWorker } from '../crm/schedule/lesson-completion.worker';
import { DatabaseService } from '../db/database.service';

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
  };
  latestMigrationId: string | null;
  lessonCompletionWorker: LessonCompletionWorkerMetrics;
}

@Injectable()
export class HealthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly lessonCompletionWorker: LessonCompletionWorker
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

    return {
      ...this.check(),
      checks: {
        database: 'ok',
        migrations: latestMigrationId === null ? 'error' : 'ok',
        lessonCompletionWorker: workerHealth.status
      },
      latestMigrationId,
      lessonCompletionWorker: workerHealth.metrics
    };
  }
}
