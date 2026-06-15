import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { RolesGuard } from './roles.guard';

function contextWithUser(user: unknown) {
  return {
    getHandler: () => 'handler',
    getClass: () => 'class',
    switchToHttp: () => ({
      getRequest: () => ({ user })
    })
  };
}

describe('RolesGuard', () => {
  it('allows requests when no roles are required', () => {
    const reflector = { getAllAndOverride: jest.fn().mockReturnValue(undefined) };
    const guard = new RolesGuard(reflector as unknown as Reflector);

    expect(guard.canActivate(contextWithUser(undefined) as never)).toBe(true);
  });

  it('denies unauthenticated requests for protected routes', () => {
    const reflector = { getAllAndOverride: jest.fn().mockReturnValue(['admin']) };
    const guard = new RolesGuard(reflector as unknown as Reflector);

    expect(() => guard.canActivate(contextWithUser(undefined) as never)).toThrow(
      UnauthorizedException
    );
  });

  it('denies actors without required role', () => {
    const reflector = { getAllAndOverride: jest.fn().mockReturnValue(['admin']) };
    const guard = new RolesGuard(reflector as unknown as Reflector);

    expect(() =>
      guard.canActivate(
        contextWithUser({ userId: 'user-a', role: 'client' }) as never
      )
    ).toThrow(ForbiddenException);
  });

  it('allows actors with required role', () => {
    const reflector = { getAllAndOverride: jest.fn().mockReturnValue(['admin']) };
    const guard = new RolesGuard(reflector as unknown as Reflector);

    expect(
      guard.canActivate(contextWithUser({ userId: 'admin-a', role: 'admin' }) as never)
    ).toBe(true);
  });
});
