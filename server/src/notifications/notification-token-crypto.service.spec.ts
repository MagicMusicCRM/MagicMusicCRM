import { ConfigService } from '@nestjs/config';
import { NotificationTokenCrypto } from './notification-token-crypto.service';

describe('NotificationTokenCrypto', () => {
  function createCrypto(secret = '') {
    const config = {
      get: jest.fn((key: string, fallback?: unknown) =>
        key === 'NOTIFICATION_TOKEN_ENCRYPTION_KEY' ? secret : fallback
      )
    };
    return new NotificationTokenCrypto(config as unknown as ConfigService);
  }

  it('stores only a hash marker when encryption key is not configured', () => {
    const crypto = createCrypto();
    const encrypted = crypto.encrypt('push-token-1234567890');

    expect(encrypted).toMatch(/^sha256:[a-f0-9]{64}$/);
    expect(encrypted).not.toContain('push-token');
    expect(crypto.decrypt(encrypted)).toBeNull();
  });

  it('round-trips encrypted tokens when key is configured', () => {
    const crypto = createCrypto('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef');
    const encrypted = crypto.encrypt('push-token-1234567890');

    expect(encrypted).toMatch(/^v1:/);
    expect(encrypted).not.toContain('push-token');
    expect(crypto.decrypt(encrypted)).toBe('push-token-1234567890');
  });

  it('returns null for tampered encrypted tokens', () => {
    const crypto = createCrypto('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef');
    const encrypted = crypto.encrypt('push-token-1234567890');

    expect(crypto.decrypt(`${encrypted}tampered`)).toBeNull();
  });

  it('rejects a shortened GCM authentication tag', () => {
    const crypto = createCrypto('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef');
    const encrypted = crypto.encrypt('push-token-1234567890');
    const parts = encrypted.split(':');
    const shortenedTag = Buffer.from(parts[2], 'base64url').subarray(0, 12);

    expect(
      crypto.decrypt(
        [parts[0], parts[1], shortenedTag.toString('base64url'), parts[3]].join(':')
      )
    ).toBeNull();
  });
});
