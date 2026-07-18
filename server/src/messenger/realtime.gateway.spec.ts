// server/src/messenger/realtime.gateway.spec.ts
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { JWT_AUDIENCE, JWT_ISSUER } from '../common/security/actor-context';
import { RealtimeBus } from '../realtime/realtime-bus';
import { MessengerPolicy } from './messenger.policy';
import { RealtimeGateway, resolveRealtimeCorsOrigin } from './realtime.gateway';

describe('resolveRealtimeCorsOrigin', () => {
  it('parses comma-separated origins into a trimmed allowlist array', () => {
    expect(resolveRealtimeCorsOrigin('https://a.ru,https://b.ru')).toEqual([
      'https://a.ru',
      'https://b.ru'
    ]);
  });

  it('trims whitespace and drops empty entries', () => {
    expect(resolveRealtimeCorsOrigin(' https://a.ru , , https://b.ru ')).toEqual([
      'https://a.ru',
      'https://b.ru'
    ]);
  });

  it('returns false (closed) for empty/undefined config in production', () => {
    expect(resolveRealtimeCorsOrigin('', 'production')).toBe(false);
    expect(resolveRealtimeCorsOrigin(undefined, 'production')).toBe(false);
  });

  it('allows true in non-production (dev) when no origins configured', () => {
    expect(resolveRealtimeCorsOrigin('', 'development')).toBe(true);
    expect(resolveRealtimeCorsOrigin(undefined)).toBe(true);
  });
});

describe('RealtimeGateway authentication', () => {
  const createSocket = () => ({
    handshake: {
      auth: { token: 'access-token' },
      headers: {} as Record<string, string>
    },
    data: {} as Record<string, unknown>,
    join: jest.fn().mockResolvedValue(undefined),
    disconnect: jest.fn()
  });

  const createGateway = (payload: Record<string, unknown>) => {
    const verifyAsync = jest.fn().mockResolvedValue(payload);
    const config = {
      getOrThrow: jest.fn().mockReturnValue('access-secret')
    };
    const gateway = new RealtimeGateway(
      { verifyAsync } as unknown as JwtService,
      config as unknown as ConfigService,
      {} as MessengerPolicy,
      { setServer: jest.fn() } as unknown as RealtimeBus
    );
    return { gateway, verifyAsync, config };
  };

  it('verifies access tokens with the same invariants as REST auth', async () => {
    const { gateway, verifyAsync } = createGateway({
      sub: 'admin-a',
      role: 'admin'
    });
    const socket = createSocket();

    await gateway.handleConnection(socket as never);

    expect(verifyAsync).toHaveBeenCalledWith('access-token', {
      secret: 'access-secret',
      issuer: JWT_ISSUER,
      audience: JWT_AUDIENCE,
      algorithms: ['HS256']
    });
    expect(socket.data).toMatchObject({
      actor: { userId: 'admin-a', role: 'admin' }
    });
    expect(socket.join).toHaveBeenCalledWith('user:admin-a');
    expect(socket.join).toHaveBeenCalledWith('crm');
    expect(socket.join).toHaveBeenCalledWith(RealtimeGateway.adminInboxRoom);
    expect(socket.disconnect).not.toHaveBeenCalled();
  });

  it('rejects a signed token whose role is outside the application allowlist', async () => {
    const { gateway } = createGateway({ sub: 'user-a', role: 'owner' });
    const socket = createSocket();

    await gateway.handleConnection(socket as never);

    expect(socket.data.actor).toBeUndefined();
    expect(socket.join).not.toHaveBeenCalled();
    expect(socket.disconnect).toHaveBeenCalledWith(true);
  });
});
