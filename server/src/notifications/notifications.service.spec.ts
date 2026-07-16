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
    expect(database.query.mock.calls[0][0]).toContain('encrypted_token = excluded.encrypted_token');
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

  describe('task reminders', () => {
    it('claims the marker and notifies recipients for a due task', async () => {
      const { service, database } = createService();
      database.query
        // due (day)
        .mockResolvedValueOnce({
          rows: [
            { id: 'task-1', title: 'Позвонить', when_local: '19.06 18:00', user_ids: ['u1', 'u2'] }
          ]
        } as never)
        // claim (task-1, day)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        // due (hour) -> none
        .mockResolvedValueOnce({ rows: [] } as never)
        // due (min10) -> none
        .mockResolvedValueOnce({ rows: [] } as never)
        // due (overdue) -> none
        .mockResolvedValueOnce({ rows: [] } as never);
      (database.transaction as jest.Mock).mockResolvedValue('notif-1');

      const result = await service.dispatchTaskReminders();

      expect(result.sent).toBe(1);
      // createNotification runs in a transaction exactly once (the day task).
      expect(database.transaction).toHaveBeenCalledTimes(1);
      // The recipients query never casts roles to the enum, so an absent
      // 'director' role can not break the scan.
      const dueSql = String(database.query.mock.calls[0][0]);
      expect(dueSql).toContain("u.role::text in ('admin', 'manager', 'director')");
      expect(dueSql).not.toContain('::app.user_role');
      // The claim targets the idempotency table.
      const claimSql = String(database.query.mock.calls[1][0]);
      expect(claimSql).toContain('app.task_reminders');
      expect(claimSql).toContain('on conflict (task_id, kind) do nothing');
    });

    it('does not send when the marker was already claimed (race)', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce({
          rows: [{ id: 'task-1', title: 'Позвонить', when_local: '19.06 18:00', user_ids: ['u1'] }]
        } as never)
        // claim returns no row -> another tick already claimed it
        .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never)
        .mockResolvedValueOnce({ rows: [] } as never)
        .mockResolvedValueOnce({ rows: [] } as never)
        .mockResolvedValueOnce({ rows: [] } as never);

      const result = await service.dispatchTaskReminders();

      expect(result.sent).toBe(0);
      expect(database.transaction).not.toHaveBeenCalled();
    });

    it('claims but does not notify a task with no recipients', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce({
          rows: [{ id: 'task-1', title: 'Позвонить', when_local: '19.06 18:00', user_ids: [] }]
        } as never)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        .mockResolvedValueOnce({ rows: [] } as never)
        .mockResolvedValueOnce({ rows: [] } as never)
        .mockResolvedValueOnce({ rows: [] } as never);

      const result = await service.dispatchTaskReminders();

      expect(result.sent).toBe(0);
      expect(database.transaction).not.toHaveBeenCalled();
    });

    it('scans four kinds: day, hour, min10 and overdue', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValue({ rows: [] } as never);

      await service.dispatchTaskReminders();

      // One "due" scan per kind, in order, each claiming its own marker kind.
      expect(database.query).toHaveBeenCalledTimes(4);
      const kinds = database.query.mock.calls.map((call) => (call[1] as string[])[0]);
      expect(kinds).toEqual(['day', 'hour', 'min10', 'overdue']);
    });

    it('fires min10 inside the last ten minutes before the deadline', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValue({ rows: [] } as never);

      await service.dispatchTaskReminders();

      const min10Sql = String(database.query.mock.calls[2][0]);
      expect(min10Sql).toContain("t.due_at <= now() + interval '10 minutes'");
      expect(min10Sql).toContain('t.due_at > now()');
    });

    it('floors the overdue window so enabling it never blasts old tasks', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValue({ rows: [] } as never);

      await service.dispatchTaskReminders();

      const overdueSql = String(database.query.mock.calls[3][0]);
      // Fires a minute past the deadline...
      expect(overdueSql).toContain("t.due_at <= now() - interval '1 minute'");
      // ...but never for tasks that went overdue long ago: without this floor
      // the first enabled tick would notify every stale task in the database.
      expect(overdueSql).toContain("t.due_at > now() - interval '1 hour'");
    });
  });

  describe('new lead notification', () => {
    it('targets admin/manager/director by text role and queues in_app+push', async () => {
      const { service, database, worker } = createService();
      database.query.mockResolvedValueOnce({
        rows: [{ id: 'admin-1' }, { id: 'manager-1' }]
      } as never);
      const client = {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [{ id: 'notification-a' }] })
          .mockResolvedValue({ rows: [] })
      };
      database.transaction.mockImplementationOnce(async (work) => work(client as never));

      await service.notifyNewLead({ leadId: 'lead-1', name: 'Иван', source: 'site' });

      const rolesSql = String(database.query.mock.calls[0][0]);
      expect(rolesSql).toContain('role::text = any');
      expect(rolesSql).not.toContain('::app.user_role');
      expect(database.query.mock.calls[0][1]).toEqual([
        ['admin', 'manager', 'director']
      ]);
      expect(client.query).toHaveBeenCalledWith(
        expect.stringContaining("'push', 'firebase', 'queued'"),
        ['notification-a', 'admin-1']
      );
      expect(worker.dispatchPendingPush).toHaveBeenCalled();
    });

    it('is a no-op when no staff users exist', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValueOnce({ rows: [] } as never);

      await service.notifyNewLead({ leadId: 'lead-1', name: 'Иван', source: 'site' });

      expect(database.transaction).not.toHaveBeenCalled();
    });
  });
});
