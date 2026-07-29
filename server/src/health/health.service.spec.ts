import { HealthService } from './health.service';

describe('HealthService', () => {
  const worker = {
    health: jest.fn().mockResolvedValue({
      status: 'ok',
      metrics: {
        due: 0,
        claimed: 0,
        retry: 0,
        poison: 0,
        completed: 0,
        oldestDueSeconds: null,
        maxAttempts: 0
      }
    })
  };

  it('returns an ok health response', () => {
    const service = new HealthService(
      { query: jest.fn() } as never,
      worker as never
    );

    expect(service.check()).toMatchObject({
      status: 'ok',
      service: 'magic-music-crm-api'
    });
  });

  it('returns readiness with latest migration id', async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [{ id: '0012_readiness_performance_indexes' }]
    });
    const service = new HealthService({ query } as never, worker as never);

    await expect(service.ready()).resolves.toMatchObject({
      status: 'ok',
      checks: {
        database: 'ok',
        migrations: 'ok',
        lessonCompletionWorker: 'ok'
      },
      lessonCompletionWorker: { poison: 0, oldestDueSeconds: null },
      latestMigrationId: '0012_readiness_performance_indexes'
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('app_schema_migrations'));
  });

  it('marks readiness migration check as error when no migration row exists', async () => {
    const service = new HealthService({
      query: jest.fn().mockResolvedValue({ rows: [] })
    } as never, worker as never);

    await expect(service.ready()).resolves.toMatchObject({
      status: 'ok',
      checks: {
        database: 'ok',
        migrations: 'error',
        lessonCompletionWorker: 'ok'
      },
      latestMigrationId: null
    });
  });

  it('surfaces a degraded Lesson completion worker', async () => {
    const degradedWorker = {
      health: jest.fn().mockResolvedValue({
        status: 'degraded',
        metrics: {
          due: 1,
          claimed: 0,
          retry: 0,
          poison: 1,
          completed: 0,
          oldestDueSeconds: 121,
          maxAttempts: 5
        }
      })
    };
    const service = new HealthService({
      query: jest.fn().mockResolvedValue({ rows: [{ id: '0088' }] })
    } as never, degradedWorker as never);

    await expect(service.ready()).resolves.toMatchObject({
      checks: { lessonCompletionWorker: 'degraded' },
      lessonCompletionWorker: {
        due: 1,
        poison: 1,
        oldestDueSeconds: 121
      }
    });
  });
});
