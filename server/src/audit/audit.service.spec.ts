import { AuditService } from './audit.service';
import { DatabaseService } from '../db/database.service';

describe('AuditService', () => {
  it('records audit event with redacted metadata', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const service = new AuditService({ query } as unknown as DatabaseService);

    await service.record({
      actor: { userId: 'user-a', role: 'admin' },
      action: 'auth.login',
      entityType: 'session',
      entityId: 'session-a',
      metadata: {
        ip: '127.0.0.1',
        reason: 'Повторяющийся спам',
        refreshToken: 'secret-refresh-token'
      }
    });

    expect(query).toHaveBeenCalledTimes(1);
    const params = query.mock.calls[0][1] as unknown[];
    expect(params[0]).toBe('user-a');
    expect(params[4]).toContain('[REDACTED]');
    expect(params[4]).toContain('[PRIVATE]');
    expect(params[4]).not.toContain('secret-refresh-token');
    expect(params[5]).toBe('Повторяющийся спам');
  });
});
