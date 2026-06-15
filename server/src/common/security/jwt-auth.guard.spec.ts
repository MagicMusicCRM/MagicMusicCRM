import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { UnauthorizedException } from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth.guard';

function executionContext(authorization?: string) {
  const request = { headers: { authorization }, user: undefined };
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
      { secret: 'test-secret-test-secret-test-secret-123' }
    );
    const { request, context } = executionContext(`Bearer ${token}`);
    const guard = new JwtAuthGuard(jwt, config);

    await expect(guard.canActivate(context as never)).resolves.toBe(true);
    expect(request.user).toEqual({ userId: 'user-a', role: 'client' });
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
});
