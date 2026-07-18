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

  describe('task reminders', () => {
    // Each kind now runs two queries before any claim: load the subscribed
    // roles (app.notification_preferences), then scan for due tasks.
    const PREFS_ROW = { role: 'manager', channels: ['push'] };
    const prefs = (rows: Record<string, unknown>[] = [PREFS_ROW]) =>
      ({ rows } as never);
    const noTasks = () => ({ rows: [] } as never);

    it('claims the marker and notifies recipients for a due task', async () => {
      const { service, database } = createService();
      database.query
        // prefs (day)
        .mockResolvedValueOnce(prefs())
        // due (day)
        .mockResolvedValueOnce({
          rows: [
            {
              id: 'task-1',
              title: 'Позвонить',
              when_local: '19.06 18:00',
              assigned_to: 'u2',
              recipients: [
                { id: 'u1', role: 'manager' },
                { id: 'u2', role: 'manager' }
              ]
            }
          ]
        } as never)
        // claim (task-1, day)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        // hour / min10 / overdue -> prefs + no tasks each
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks());
      (database.transaction as jest.Mock).mockResolvedValue('notif-1');

      const result = await service.dispatchTaskReminders();

      expect(result.sent).toBe(1);
      // Both recipients want the same channels, so they share one notification.
      expect(database.transaction).toHaveBeenCalledTimes(1);
      // Recipients come from configuration now, not a literal role list.
      const dueSql = String(database.query.mock.calls[1][0]);
      expect(dueSql).toContain('u.role::text = any($2::text[])');
      expect(dueSql).not.toContain("in ('admin', 'manager', 'director')");
      // Still never casts to the enum: an absent 'director' role must not break
      // the scan.
      expect(dueSql).not.toContain('::app.user_role');
      const claimSql = String(database.query.mock.calls[2][0]);
      expect(claimSql).toContain('app.task_reminders');
      expect(claimSql).toContain('on conflict (task_id, kind) do nothing');
    });

    it('splits recipients who want different channels into separate sends', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce(
          prefs([
            { role: 'manager', channels: ['push'] },
            { role: 'director', channels: ['in_app'] }
          ])
        )
        .mockResolvedValueOnce({
          rows: [
            {
              id: 'task-1',
              title: 'Позвонить',
              when_local: '19.06 18:00',
              assigned_to: null,
              recipients: [
                { id: 'u1', role: 'manager' },
                { id: 'u2', role: 'director' }
              ]
            }
          ]
        } as never)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks());
      (database.transaction as jest.Mock).mockResolvedValue('notif-1');

      const result = await service.dispatchTaskReminders();

      // createNotification applies ONE channel list to everyone it is given, so
      // honouring both preferences takes two sends. Still one reminder per task.
      expect(database.transaction).toHaveBeenCalledTimes(2);
      expect(result.sent).toBe(1);
    });

    it('notifies the assignee even when their role opted out', async () => {
      const { service, database } = createService();
      database.query
        // Only managers subscribed; the assignee is a teacher.
        .mockResolvedValueOnce(prefs([{ role: 'manager', channels: ['push'] }]))
        .mockResolvedValueOnce({
          rows: [
            {
              id: 'task-1',
              title: 'Позвонить',
              when_local: '19.06 18:00',
              assigned_to: 'teacher-1',
              recipients: [{ id: 'teacher-1', role: 'teacher' }]
            }
          ]
        } as never)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks());
      (database.transaction as jest.Mock).mockResolvedValue('notif-1');

      const result = await service.dispatchTaskReminders();

      // "Assigned to you" is not a preference — a role toggle must not silence
      // the reminder for the person who owns the task.
      expect(result.sent).toBe(1);
      expect(database.transaction).toHaveBeenCalledTimes(1);
    });

    it('does not send when the marker was already claimed (race)', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce({
          rows: [
            {
              id: 'task-1',
              title: 'Позвонить',
              when_local: '19.06 18:00',
              assigned_to: null,
              recipients: [{ id: 'u1', role: 'manager' }]
            }
          ]
        } as never)
        // claim returns no row -> another tick already claimed it
        .mockResolvedValueOnce({ rows: [], rowCount: 0 } as never)
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks());

      const result = await service.dispatchTaskReminders();

      expect(result.sent).toBe(0);
      expect(database.transaction).not.toHaveBeenCalled();
    });

    it('claims but does not notify a task with no recipients', async () => {
      const { service, database } = createService();
      database.query
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce({
          rows: [
            {
              id: 'task-1',
              title: 'Позвонить',
              when_local: '19.06 18:00',
              assigned_to: null,
              recipients: []
            }
          ]
        } as never)
        .mockResolvedValueOnce({ rows: [{ id: 'rem-1' }], rowCount: 1 } as never)
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks())
        .mockResolvedValueOnce(prefs())
        .mockResolvedValueOnce(noTasks());

      const result = await service.dispatchTaskReminders();

      expect(result.sent).toBe(0);
      expect(database.transaction).not.toHaveBeenCalled();
    });

    it('scans four kinds: day, hour, min10 and overdue', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValue({ rows: [] } as never);

      await service.dispatchTaskReminders();

      // Two queries per kind: load subscribed roles, then scan for due tasks.
      expect(database.query).toHaveBeenCalledTimes(8);
      const kinds = database.query.mock.calls
        .filter((call) => String(call[0]).includes('app.tasks'))
        .map((call) => (call[1] as string[])[0]);
      expect(kinds).toEqual(['day', 'hour', 'min10', 'overdue']);
      // Each kind reads its own preference row.
      const events = database.query.mock.calls
        .filter((call) => String(call[0]).includes('notification_preferences'))
        .map((call) => (call[1] as string[])[0]);
      expect(events).toEqual([
        'task_reminder_day',
        'task_reminder_hour',
        'task_reminder_min10',
        'task_reminder_overdue'
      ]);
    });

    it('fires min10 inside the last ten minutes before the deadline', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValue({ rows: [] } as never);

      await service.dispatchTaskReminders();

      const min10Sql = String(database.query.mock.calls[5][0]);
      expect(min10Sql).toContain("t.due_at <= now() + interval '10 minutes'");
      expect(min10Sql).toContain('t.due_at > now()');
    });

    it('floors the overdue window so enabling it never blasts old tasks', async () => {
      const { service, database } = createService();
      database.query.mockResolvedValue({ rows: [] } as never);

      await service.dispatchTaskReminders();

      const overdueSql = String(database.query.mock.calls[7][0]);
      // Fires a minute past the deadline...
      expect(overdueSql).toContain("t.due_at <= now() - interval '1 minute'");
      // ...but never for tasks that went overdue long ago: without this floor
      // the first enabled tick would notify every stale task in the database.
      expect(overdueSql).toContain("t.due_at > now() - interval '1 hour'");
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
