import { HealthService } from './health.service';

describe('HealthService', () => {
  const flags = {
    snapshot: jest.fn().mockReturnValue([
      {
        domain: 'access',
        configuredMode: 'shadow',
        effectivePath: 'legacy',
        shadowCompare: true,
        killSwitch: false,
        enableAllowed: true,
        reason: 'shadow_compare'
      }
    ])
  };
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
  const outboxWorker = {
    health: jest.fn().mockResolvedValue({
      status: 'ok',
      metrics: {
        pending: 0,
        deadLetter: 0,
        oldestDueSeconds: null,
        maxAttempts: 0
      }
    })
  };

  it('returns an ok health response', () => {
    const service = new HealthService(
      { query: jest.fn() } as never,
      worker as never,
      flags as never,
      outboxWorker as never
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
    const service = new HealthService(
      { query } as never,
      worker as never,
      flags as never,
      outboxWorker as never
    );

    await expect(service.ready()).resolves.toMatchObject({
      status: 'ok',
      checks: {
        database: 'ok',
        migrations: 'ok',
        lessonCompletionWorker: 'ok',
        platformOutbox: 'ok',
        v4Rollout: 'ok'
      },
      lessonCompletionWorker: { poison: 0, oldestDueSeconds: null },
      platformOutbox: { pending: 0, deadLetter: 0 },
      latestMigrationId: '0012_readiness_performance_indexes'
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('app_schema_migrations'));
  });

  it('marks readiness migration check as error when no migration row exists', async () => {
    const service = new HealthService({
      query: jest.fn().mockResolvedValue({ rows: [] })
    } as never, worker as never, flags as never, outboxWorker as never);

    await expect(service.ready()).resolves.toMatchObject({
      status: 'ok',
      checks: {
        database: 'ok',
        migrations: 'error',
        lessonCompletionWorker: 'ok',
        platformOutbox: 'ok',
        v4Rollout: 'ok'
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
    } as never, degradedWorker as never, flags as never, outboxWorker as never);

    await expect(service.ready()).resolves.toMatchObject({
      checks: { lessonCompletionWorker: 'degraded' },
      lessonCompletionWorker: {
        due: 1,
        poison: 1,
        oldestDueSeconds: 121
      }
    });
  });

  it('blocks readiness enable state when v4 parity is unexplained', async () => {
    const blockedFlags = {
      snapshot: jest.fn().mockReturnValue([{
        domain: 'access',
        configuredMode: 'v4',
        effectivePath: 'legacy',
        shadowCompare: true,
        killSwitch: false,
        enableAllowed: false,
        reason: 'unexplained_parity_diff'
      }])
    };
    const service = new HealthService({
      query: jest.fn().mockResolvedValue({ rows: [{ id: '0093' }] })
    } as never, worker as never, blockedFlags as never, outboxWorker as never);

    await expect(service.ready()).resolves.toMatchObject({
      checks: { v4Rollout: 'blocked' },
      v4Rollout: [{ reason: 'unexplained_parity_diff' }]
    });
  });

  it('degrades readiness when the platform outbox is stuck', async () => {
    const degradedOutbox = {
      health: jest.fn().mockResolvedValue({
        status: 'degraded',
        metrics: {
          pending: 1,
          deadLetter: 0,
          oldestDueSeconds: 121,
          maxAttempts: 0
        }
      })
    };
    const service = new HealthService({
      query: jest.fn().mockResolvedValue({ rows: [{ id: '0113' }] })
    } as never, worker as never, flags as never, degradedOutbox as never);

    await expect(service.ready()).resolves.toMatchObject({
      checks: { platformOutbox: 'degraded' },
      platformOutbox: { pending: 1, oldestDueSeconds: 121 }
    });
  });
});
