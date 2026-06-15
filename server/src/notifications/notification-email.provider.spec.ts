import { ConfigService } from '@nestjs/config';
import { ResendEmailProvider } from './notification-email.provider';

describe('ResendEmailProvider', () => {
  const message = {
    to: 'user@example.com',
    subject: 'Subject',
    text: 'Body'
  };

  function createProvider(overrides: Record<string, unknown> = {}) {
    const values: Record<string, unknown> = {
      RESEND_API_KEY: 'resend-key',
      RESEND_FROM_EMAIL: 'noreply@example.com',
      RESEND_TIMEOUT_MS: 1000,
      ...overrides
    };
    const config = {
      get: jest.fn((key: string, fallback?: unknown) => values[key] ?? fallback)
    };
    return {
      provider: new ResendEmailProvider(config as unknown as ConfigService),
      config
    };
  }

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('aborts Resend fetch after configured timeout', async () => {
    jest.useFakeTimers();
    const { provider } = createProvider({ RESEND_TIMEOUT_MS: 25 });
    const fetchMock = jest.spyOn(global, 'fetch').mockImplementation((async (_url, init) => {
      return new Promise<Response>((_resolve, reject) => {
        const signal = init?.signal;
        signal?.addEventListener('abort', () => {
          const error = new Error('aborted');
          error.name = 'AbortError';
          reject(error);
        });
      });
    }) as typeof fetch);

    const result = provider.send(message);
    await jest.advanceTimersByTimeAsync(25);

    await expect(result).resolves.toEqual({
      provider: 'resend',
      status: 'failed',
      error: 'timeout'
    });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://api.resend.com/emails',
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
  });

  it('returns failed provider result on Resend network errors', async () => {
    const { provider } = createProvider();
    jest.spyOn(global, 'fetch').mockRejectedValueOnce(new Error('network down'));

    await expect(provider.send(message)).resolves.toEqual({
      provider: 'resend',
      status: 'failed',
      error: 'provider_error'
    });
  });
});
