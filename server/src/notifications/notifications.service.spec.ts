import { AuditService } from '../audit/audit.service';
import { DatabaseService } from '../db/database.service';
import { NotificationTokenCrypto } from './notification-token-crypto.service';
import { NotificationWorker } from './notification-worker.service';
import { NotificationsPolicy } from './notifications.policy';
import { NotificationsService } from './notifications.service';

describe('NotificationsService', () => {
  const admin = { userId: 'admin-a', role: 'admin' as const };

  function createService() {
    const database = {
      query: jest.fn(),
      transaction: jest.fn()
    } as unknown as jest.Mocked<Pick<DatabaseService, 'query' | 'transaction'>>;
    const audit = {
      record: jest.fn().mockResolvedValue(undefined)
    } as unknown as jest.Mocked<Pick<AuditService, 'record'>>;
    const worker = {
      dispatchPendingEmails: jest.fn().mockResolvedValue({ processed: 0, failed: 0 }),
      dispatchPendingPush: jest.fn().mockResolvedValue({ processed: 0, failed: 0 })
    } as unknown as jest.Mocked<Pick<NotificationWorker, 'dispatchPendingEmails' | 'dispatchPendingPush'>>;
    const tokenCrypto = {
      hash: jest.fn((token: string) => `hash-${token}`),
      encrypt: jest.fn((token: string) => `encrypted-${token}`)
    } as unknown as jest.Mocked<Pick<NotificationTokenCrypto, 'hash' | 'encrypt'>>;
    const service = new NotificationsService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      new NotificationsPolicy(),
      worker as unknown as NotificationWorker,
      tokenCrypto as unknown as NotificationTokenCrypto
    );
    return { service, database, audit, worker, tokenCrypto };
  }

  it('marks only current actor notification recipient as read', async () => {
    const { service, database } = createService();
    database.query
      .mockResolvedValueOnce({
        rows: [{ notification_id: 'notification-a', user_id: 'user-a' }]
      } as never)
      .mockResolvedValueOnce({
        rows: [
          {
            id: 'notification-a',
            type: 'system',
            title: 'Title',
            body: 'Body',
            data: {},
            created_by: null,
            created_at: new Date('2026-06-11T00:00:00Z'),
            recipient_id: 'recipient-a',
            is_read: true,
            read_at: new Date('2026-06-11T00:01:00Z'),
            delivered_at: null
          }
        ]
      } as never);

    await expect(
      service.markRead({ userId: 'user-a', role: 'client' }, 'notification-a')
    ).resolves.toMatchObject({ id: 'notification-a', isRead: true });

    expect(database.query).toHaveBeenLastCalledWith(expect.stringContaining('nr.user_id = $2'), [
      'notification-a',
      'user-a'
    ]);
  });

  it('admin broadcast persists recipients, email outbox and audit event', async () => {
    const { service, database, audit, worker } = createService();
    database.query.mockResolvedValueOnce({
      rows: [{ id: 'user-a' }, { id: 'user-b' }]
    } as never);
    database.transaction.mockImplementationOnce(async (work) => {
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [{ id: 'notification-a' }] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [{ email: 'a@example.com' }] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [{ email: 'b@example.com' }] })
          .mockResolvedValue({ rows: [] })
      };
      return work(client as never);
    });

    await expect(
      service.adminSend(admin, {
        target: 'role',
        role: 'client',
        title: 'Title',
        body: 'Body',
        channels: ['in_app', 'email']
      })
    ).resolves.toEqual({ notificationId: 'notification-a', recipientCount: 2 });

    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'notifications.admin_sent',
        metadata: { target: 'role', count: 2, channels: ['in_app', 'email'] }
      })
    );
    expect(worker.dispatchPendingEmails).toHaveBeenCalled();
  });

  it('registers device with encrypted token instead of raw token', async () => {
    const { service, database, tokenCrypto } = createService();
    database.query.mockResolvedValueOnce({
      rows: [
        {
          id: 'device-a',
          user_id: 'user-a',
          platform: 'android',
          token_hash: 'hash-push-token-1234567890',
          enabled: true,
          last_seen_at: new Date('2026-06-13T00:00:00Z'),
          created_at: new Date('2026-06-13T00:00:00Z'),
          updated_at: new Date('2026-06-13T00:00:00Z')
        }
      ]
    } as never);

    await expect(
      service.registerDevice({ userId: 'user-a', role: 'client' }, {
        platform: 'android',
        token: 'push-token-1234567890'
      })
    ).resolves.toMatchObject({ id: 'device-a', tokenHash: 'hash-push-token-1234567890' });

    expect(tokenCrypto.encrypt).toHaveBeenCalledWith('push-token-1234567890');
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('encrypted_token'), [
      'user-a',
      'android',
      'hash-push-token-1234567890',
      'encrypted-push-token-1234567890'
    ]);
  });

  it('queues push delivery and schedules push worker', async () => {
    const { service, database, worker } = createService();
    database.query.mockResolvedValueOnce({
      rows: [{ id: 'user-a' }]
    } as never);
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [{ id: 'notification-a' }] })
        .mockResolvedValue({ rows: [] })
    };
    database.transaction.mockImplementationOnce(async (work) => work(client as never));

    await expect(
      service.adminSend(admin, {
        target: 'role',
        role: 'client',
        title: 'Title',
        body: 'Body',
        channels: ['in_app', 'push']
      })
    ).resolves.toEqual({ notificationId: 'notification-a', recipientCount: 1 });

    expect(client.query).toHaveBeenCalledWith(expect.stringContaining("'push', 'firebase', 'queued'"), [
      'notification-a',
      'user-a'
    ]);
    expect(worker.dispatchPendingEmails).not.toHaveBeenCalled();
    expect(worker.dispatchPendingPush).toHaveBeenCalled();
  });
});
