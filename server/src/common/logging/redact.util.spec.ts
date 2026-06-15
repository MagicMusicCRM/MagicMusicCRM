import { redactSensitive } from './redact.util';

describe('redactSensitive', () => {
  it('redacts sensitive object fields recursively', () => {
    const result = redactSensitive({
      email: 'user@example.com',
      password: 'secret-password',
      nested: {
        refreshToken: 'refresh-token-value',
        safe: 'visible'
      }
    });

    expect(result).toEqual({
      email: 'user@example.com',
      password: '[REDACTED]',
      nested: {
        refreshToken: '[REDACTED]',
        safe: 'visible'
      }
    });
  });

  it('redacts bearer tokens in strings', () => {
    expect(redactSensitive('Authorization: Bearer abc.def.ghi')).toBe(
      'Authorization: Bearer [REDACTED]'
    );
  });
});
