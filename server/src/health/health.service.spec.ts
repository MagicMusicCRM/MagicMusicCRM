import { HealthService } from './health.service';

describe('HealthService', () => {
  it('returns an ok health response', () => {
    const service = new HealthService({ query: jest.fn() } as never);

    expect(service.check()).toMatchObject({
      status: 'ok',
      service: 'magic-music-crm-api'
    });
  });

  it('returns readiness with latest migration id', async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [{ id: '0012_readiness_performance_indexes' }]
    });
    const service = new HealthService({ query } as never);

    await expect(service.ready()).resolves.toMatchObject({
      status: 'ok',
      checks: { database: 'ok', migrations: 'ok' },
      latestMigrationId: '0012_readiness_performance_indexes'
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('app_schema_migrations'));
  });

  it('marks readiness migration check as error when no migration row exists', async () => {
    const service = new HealthService({
      query: jest.fn().mockResolvedValue({ rows: [] })
    } as never);

    await expect(service.ready()).resolves.toMatchObject({
      status: 'ok',
      checks: { database: 'ok', migrations: 'error' },
      latestMigrationId: null
    });
  });
});
