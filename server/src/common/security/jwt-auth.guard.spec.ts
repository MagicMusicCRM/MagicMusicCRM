import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { DatabaseService } from '../../db/database.service';
import {
  V4DomainFlagsService,
  V4DomainRollout,
} from '../../platform/v4-domain-flags';
import { JwtAuthGuard } from './jwt-auth.guard';

function flags(rollout: Partial<V4DomainRollout>): V4DomainFlagsService {
  return {
    get: jest.fn(() => ({
      domain: 'access',
      configuredMode: 'shadow',
      effectivePath: 'legacy',
      shadowCompare: true,
      killSwitch: false,
      enableAllowed: true,
      reason: 'shadow_compare',
      ...rollout,
    })),
  } as unknown as V4DomainFlagsService;
}

function executionContext(authorization?: string) {
  const request = {
    headers: { authorization },
    user: undefined,
    capabilityAccess: undefined,
    method: 'GET',
    baseUrl: '/api',
    path: '/analytics/status',
    route: { path: '/analytics/status' }
  };
  return {
    request,
    context: {
      switchToHttp: () => ({
        getRequest: () => request
      })
    }
  };
}

describe('JwtAuthGuard', () => {
  const config = {
    getOrThrow: jest.fn(() => 'test-secret-test-secret-test-secret-123')
  } as unknown as ConfigService;

  it('accepts a valid bearer token and sets actor context', async () => {
    const jwt = new JwtService();
    const token = await jwt.signAsync(
      { sub: 'user-a', role: 'client' },
      {
        secret: 'test-secret-test-secret-test-secret-123',
        issuer: 'magicmusiccrm',
        audience: 'magicmusiccrm-app'
      }
    );
    const { request, context } = executionContext(`Bearer ${token}`);
    const guard = new JwtAuthGuard(jwt, config);

    await expect(guard.canActivate(context as never)).resolves.toBe(true);
    expect(request.user).toEqual({ userId: 'user-a', role: 'client' });
  });

  it('rejects a token missing the expected audience/issuer', async () => {
    const jwt = new JwtService();
    const token = await jwt.signAsync(
      { sub: 'user-a', role: 'client' },
      { secret: 'test-secret-test-secret-test-secret-123' } // no iss/aud
    );
    const guard = new JwtAuthGuard(jwt, config);
    const { context } = executionContext(`Bearer ${token}`);

    await expect(guard.canActivate(context as never)).rejects.toThrow(
      UnauthorizedException
    );
  });

  it('rejects missing bearer token', async () => {
    const guard = new JwtAuthGuard(new JwtService(), config);
    const { context } = executionContext();

    await expect(guard.canActivate(context as never)).rejects.toThrow(
      UnauthorizedException
    );
  });

  it('rejects forged roles', async () => {
    const jwt = new JwtService();
    const token = await jwt.signAsync(
      { sub: 'user-a', role: 'owner' },
      { secret: 'test-secret-test-secret-test-secret-123' }
    );
    const guard = new JwtAuthGuard(jwt, config);
    const { context } = executionContext(`Bearer ${token}`);

    await expect(guard.canActivate(context as never)).rejects.toThrow(
      UnauthorizedException
    );
  });

  it('enforces the dynamic capability after JWT and preserves 403 semantics', async () => {
    const jwt = new JwtService();
    const token = await jwt.signAsync(
      { sub: 'user-a', role: 'teacher' },
      {
        secret: 'test-secret-test-secret-test-secret-123',
        issuer: 'magicmusiccrm',
        audience: 'magicmusiccrm-app'
      }
    );
    const database = {
      query: jest.fn().mockResolvedValue({
        rows: [
          {
            role: 'teacher',
            active: true,
            definition_active: true,
            role_effect: 'deny',
            override_effect: null
          }
        ]
      })
    } as unknown as DatabaseService;
    const guard = new JwtAuthGuard(jwt, config, database, flags({
      configuredMode: 'v4',
      effectivePath: 'v4',
      shadowCompare: false,
      reason: 'v4',
    }));
    const { context } = executionContext(`Bearer ${token}`);

    await expect(guard.canActivate(context as never)).rejects.toThrow(
      ForbiddenException
    );
  });

  it('keeps the legacy allow decision when shadow capability denies', async () => {
    const jwt = new JwtService();
    const token = await jwt.signAsync(
      { sub: 'user-a', role: 'teacher' },
      {
        secret: 'test-secret-test-secret-test-secret-123',
        issuer: 'magicmusiccrm',
        audience: 'magicmusiccrm-app'
      }
    );
    const database = {
      query: jest.fn().mockResolvedValue({
        rows: [{
          role: 'teacher',
          active: true,
          definition_active: true,
          role_effect: 'deny',
          override_effect: null
        }]
      })
    } as unknown as DatabaseService;
    const guard = new JwtAuthGuard(jwt, config, database, flags({}));
    const { request, context } = executionContext(`Bearer ${token}`);
    request.path = '/crm/lessons';
    request.route.path = '/crm/lessons';

    await expect(guard.canActivate(context as never)).resolves.toBe(true);
    expect((request as {
      capabilityAccess?: { decisionSource: string };
    }).capabilityAccess?.decisionSource).toBe('legacy;shadow:deny');
  });

  it('uses the legacy denial immediately when the access kill switch is on', async () => {
    const jwt = new JwtService();
    const token = await jwt.signAsync(
      { sub: 'user-a', role: 'teacher' },
      {
        secret: 'test-secret-test-secret-test-secret-123',
        issuer: 'magicmusiccrm',
        audience: 'magicmusiccrm-app'
      }
    );
    const database = { query: jest.fn() } as unknown as DatabaseService;
    const guard = new JwtAuthGuard(jwt, config, database, flags({
      configuredMode: 'v4',
      killSwitch: true,
      shadowCompare: false,
      enableAllowed: false,
      reason: 'kill_switch',
    }));
    const { context } = executionContext(`Bearer ${token}`);

    await expect(guard.canActivate(context as never)).rejects.toThrow(
      ForbiddenException
    );
    expect(database.query).not.toHaveBeenCalled();
  });
});
