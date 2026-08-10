import { HttpStatus } from '@nestjs/common';
import { HealthController } from './health.controller';

describe('HealthController', () => {
  it('keeps healthy readiness at HTTP 200', async () => {
    const readiness = { status: 'ok' };
    const controller = new HealthController({
      ready: jest.fn().mockResolvedValue(readiness)
    } as never);
    const response = { status: jest.fn() };

    await expect(controller.ready(response as never)).resolves.toBe(readiness);
    expect(response.status).not.toHaveBeenCalled();
  });

  it('returns HTTP 503 when any readiness check is degraded', async () => {
    const readiness = { status: 'degraded' };
    const controller = new HealthController({
      ready: jest.fn().mockResolvedValue(readiness)
    } as never);
    const response = { status: jest.fn() };

    await expect(controller.ready(response as never)).resolves.toBe(readiness);
    expect(response.status).toHaveBeenCalledWith(
      HttpStatus.SERVICE_UNAVAILABLE
    );
  });
});
