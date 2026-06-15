import { ConfigService } from '@nestjs/config';
import { FirebasePushProvider } from './notification-push.provider';

describe('FirebasePushProvider', () => {
  function createProvider(overrides: Record<string, unknown> = {}) {
    const values: Record<string, unknown> = {
      FIREBASE_PROJECT_ID: '',
      FIREBASE_CLIENT_EMAIL: '',
      FIREBASE_PRIVATE_KEY: '',
      FIREBASE_TIMEOUT_MS: 1000,
      ...overrides
    };
    const config = {
      get: jest.fn((key: string, fallback?: unknown) => values[key] ?? fallback)
    };
    return new FirebasePushProvider(config as unknown as ConfigService);
  }

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('skips delivery when Firebase service account is not configured', async () => {
    const provider = createProvider();
    const fetchMock = jest.spyOn(global, 'fetch');

    await expect(
      provider.send({
        token: 'push-token-1234567890',
        title: 'Title',
        body: 'Body'
      })
    ).resolves.toEqual({
      provider: 'firebase',
      status: 'skipped',
      error: 'not_configured'
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
