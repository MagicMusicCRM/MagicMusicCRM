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
      email: '[PII]',
      password: '[REDACTED]',
      nested: {
        refreshToken: '[REDACTED]',
        safe: 'visible'
      }
    });
  });

  it('masks PII fields and emails embedded in strings', () => {
    expect(
      redactSensitive({
        phone: '+79991234567',
        firstName: 'Анна',
        note: 'напишите на a.b@example.com'
      })
    ).toEqual({
      phone: '[PII]',
      firstName: '[PII]',
      note: 'напишите на [EMAIL]'
    });
  });

  it('redacts bearer tokens in strings', () => {
    expect(redactSensitive('Authorization: Bearer abc.def.ghi')).toBe(
      'Authorization: Bearer [REDACTED]'
    );
  });
});
