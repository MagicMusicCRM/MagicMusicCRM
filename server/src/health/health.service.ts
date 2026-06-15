import { Injectable } from '@nestjs/common';
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
  };
  latestMigrationId: string | null;
}

@Injectable()
export class HealthService {
  constructor(private readonly database: DatabaseService) {}

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
    const result = await this.database.query<{ id: string | null }>(
      `
        select id
        from app_schema_migrations
        order by applied_at desc
        limit 1
      `
    );
    const latestMigrationId = result.rows[0]?.id ?? null;

    return {
      ...this.check(),
      checks: {
        database: 'ok',
        migrations: latestMigrationId === null ? 'error' : 'ok'
      },
      latestMigrationId
    };
  }
}
