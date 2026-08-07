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
      note: '[PRIVATE]'
    });
  });

  it('masks financial, comment and representative fields', () => {
    expect(
      redactSensitive({
        balance: 1500,
        debt: 200,
        clientCost: 1200,
        teacherRate: 900,
        payerStudentId: 'payer-1',
        refundReason: 'duplicate',
        reversalId: 'reversal-1',
        exclusionId: 'exclusion-1',
        compensationRule: 'fixed',
        commentBody: 'private note',
        representativeName: 'Parent'
      })
    ).toEqual({
      balance: '[PRIVATE]',
      debt: '[PRIVATE]',
        clientCost: '[PRIVATE]',
        teacherRate: '[PRIVATE]',
        payerStudentId: '[PRIVATE]',
        refundReason: '[PRIVATE]',
        reversalId: '[PRIVATE]',
        exclusionId: '[PRIVATE]',
        compensationRule: '[PRIVATE]',
        commentBody: '[PRIVATE]',
      representativeName: '[PRIVATE]'
    });
  });

  it('redacts bearer tokens in strings', () => {
    expect(redactSensitive('Authorization: Bearer abc.def.ghi')).toBe(
      'Authorization: Bearer [REDACTED]'
    );
  });

  it('keeps accessVersion concurrency metadata while redacting accessToken', () => {
    expect(
      redactSensitive({
        accessVersion: 7,
        accessToken: 'private-token'
      })
    ).toEqual({
      accessVersion: 7,
      accessToken: '[REDACTED]'
    });
  });
});
