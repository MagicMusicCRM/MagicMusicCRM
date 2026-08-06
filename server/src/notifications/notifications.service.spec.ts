import { ForbiddenException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { DatabaseService } from '../db/database.service';
import { NotificationTokenCrypto } from './notification-token-crypto.service';
import { NotificationWorker } from './notification-worker.service';
import { NotificationsPolicy } from './notifications.policy';
import { NotificationsService } from './notifications.service';
import { RealtimeBus } from '../realtime/realtime-bus';

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
      tokenCrypto as unknown as NotificationTokenCrypto,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus
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

  it('registers an encrypted device token and atomically transfers its active owner', async () => {
    const { service, database, tokenCrypto } = createService();
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [] }) // token advisory lock
        .mockResolvedValueOnce({ rows: [] }) // disable previous owner
        .mockResolvedValueOnce({
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
        })
    };
    database.transaction.mockImplementationOnce(async (work) => work(client as never));

    await expect(
      service.registerDevice({ userId: 'user-a', role: 'client' }, {
        platform: 'android',
        token: 'push-token-1234567890'
      })
    ).resolves.toMatchObject({ id: 'device-a', tokenHash: 'hash-push-token-1234567890' });

    expect(tokenCrypto.encrypt).toHaveBeenCalledWith('push-token-1234567890');
    expect(String(client.query.mock.calls[0][0])).toContain('pg_advisory_xact_lock');
    expect(String(client.query.mock.calls[1][0])).toContain('enabled = false');
    expect(client.query.mock.calls[1][1]).toEqual([
      'hash-push-token-1234567890',
      'user-a'
    ]);
    expect(client.query).toHaveBeenLastCalledWith(expect.stringContaining('encrypted_token'), [
      'user-a',
      'android',
      'hash-push-token-1234567890',
      'encrypted-push-token-1234567890'
    ]);
    expect(client.query.mock.calls[2][0]).toContain('encrypted_token = excluded.encrypted_token');
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

  describe('lesson reminders', () => {
    it('claims the marker and notifies recipients for a due lesson', async () => {
      const { service, database } = createService();
      database.query
        // due (day)
        .mockResolvedValueOnce({
          rows: [
            { id: 'lesson-1', when_local: '19.06 18:00', user_ids: ['u1', 'u2'] }
          ]
        } as never)
        // claim (lesson-1, day)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        // due (hour) -> none
        .mockResolvedValueOnce({ rows: [] } as never);
      (database.transaction as jest.Mock).mockResolvedValue('notif-1');

      const result = await service.dispatchLessonReminders();

      expect(result.sent).toBe(1);
      // createNotification runs in a transaction exactly once (the day lesson).
      expect(database.transaction).toHaveBeenCalledTimes(1);
    });

    it('does not send when the marker was already claimed (race)', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce({
          rows: [{ id: 'lesson-1', when_local: '19.06 18:00', user_ids: ['u1'] }]
        } as never)
        // claim returns no row -> another tick already claimed it
        .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never)
        .mockResolvedValueOnce({ rows: [] } as never);

      const result = await service.dispatchLessonReminders();

      expect(result.sent).toBe(0);
      expect(database.transaction).not.toHaveBeenCalled();
    });

    it('claims but does not notify a lesson with no recipients', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce({
          rows: [{ id: 'lesson-1', when_local: '19.06 18:00', user_ids: [] }]
        } as never)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        .mockResolvedValueOnce({ rows: [] } as never);

      const result = await service.dispatchLessonReminders();

      expect(result.sent).toBe(0);
      expect(database.transaction).not.toHaveBeenCalled();
    });
  });

  describe('new lead notification', () => {
    it('targets the subscribed roles by text role and queues their channels', async () => {
      const { service, database, worker } = createService();
      database.query
        // subscribed roles come from configuration, not a literal
        .mockResolvedValueOnce({
          rows: [
            { role: 'admin', channels: ['in_app', 'push'] },
            { role: 'manager', channels: ['in_app', 'push'] }
          ]
        } as never)
        .mockResolvedValueOnce({
          rows: [
            { id: 'admin-1', role: 'admin' },
            { id: 'manager-1', role: 'manager' }
          ]
        } as never);
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [{ id: 'notification-a' }] })
          .mockResolvedValue({ rows: [] })
      };
      database.transaction.mockImplementationOnce(async (work) => work(client as never));

      await service.notifyNewLead({ leadId: 'lead-1', name: 'Иван', source: 'site' });

      const rolesSql = String(database.query.mock.calls[1][0]);
      expect(rolesSql).toContain('role::text = any');
      expect(rolesSql).not.toContain('::app.user_role');
      // Exactly the roles the settings say, not a hardcoded trio.
      expect(database.query.mock.calls[1][1]).toEqual([['admin', 'manager']]);
      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining("'push', 'firebase', 'queued'"),
        ['notification-a', 'admin-1']
      );
      expect(worker.dispatchPendingPush).toHaveBeenCalled();
    });

    it('is a no-op when every role opted out', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValueOnce({ rows: [] } as never);

      await service.notifyNewLead({ leadId: 'lead-1', name: 'Иван', source: 'site' });

      // Nobody subscribed is a valid setting, not an error: it must not fall
      // back to notifying everyone.
      expect(database.query).toHaveBeenCalledTimes(1);
      expect(database.transaction).not.toHaveBeenCalled();
    });

    it('is a no-op when no staff users exist', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce({
          rows: [{ role: 'admin', channels: ['push'] }]
        } as never)
        .mockResolvedValueOnce({ rows: [] } as never);

      await service.notifyNewLead({ leadId: 'lead-1', name: 'Иван', source: 'site' });

      expect(database.transaction).not.toHaveBeenCalled();
    });
  });

  describe('preferences', () => {
    const actor = { userId: 'director-1', role: 'director' as const };

    it('upserts a preference and audits who changed it', async () => {
      const { service, database, audit } = createService();
      database.query.mockResolvedValueOnce({
        rows: [
          {
            role: 'teacher',
            event_type: 'new_lead',
            enabled: true,
            channels: ['in_app']
          }
        ]
      } as never);

      await expect(
        service.updatePreference(actor, {
          role: 'teacher',
          eventType: 'new_lead',
          enabled: true,
          channels: ['in_app']
        })
      ).resolves.toEqual({
        role: 'teacher',
        eventType: 'new_lead',
        enabled: true,
        channels: ['in_app']
      });

      // Upsert, not update: a role added after the seed has no row yet.
      expect(String(database.query.mock.calls[0][0])).toContain(
        'on conflict (role, event_type) do update'
      );
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'notifications.preference_updated',
          metadata: expect.objectContaining({ role: 'teacher' })
        })
      );
    });

    it('refuses to let a teacher reroute the school notifications', async () => {
      const { service } = createService();

      await expect(
        service.listPreferences({ userId: 'teacher-1', role: 'teacher' })
      ).rejects.toBeInstanceOf(ForbiddenException);
    });
  });
});
