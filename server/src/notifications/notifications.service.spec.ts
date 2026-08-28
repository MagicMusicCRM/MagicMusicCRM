import { ForbiddenException, NotFoundException } from '@nestjs/common';
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
      dispatchPendingPush: jest.fn().mockResolvedValue({ processed: 0, failed: 0 }),
      dispatchEmailById: jest.fn().mockResolvedValue({ processed: true, status: 'sent' }),
      exhaustEmail: jest.fn().mockResolvedValue(undefined)
    } as unknown as jest.Mocked<Pick<
      NotificationWorker,
      'dispatchPendingEmails' | 'dispatchPendingPush' | 'dispatchEmailById' | 'exhaustEmail'
    >>;
    const tokenCrypto = {
      hash: jest.fn((token: string) => `hash-${token}`),
      encrypt: jest.fn((token: string) => `encrypted-${token}`)
    } as unknown as jest.Mocked<Pick<NotificationTokenCrypto, 'hash' | 'encrypt'>>;
    const realtime = {
      emitCrmChanged: jest.fn()
    } as unknown as jest.Mocked<Pick<RealtimeBus, 'emitCrmChanged'>>;
    const service = new NotificationsService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      new NotificationsPolicy(),
      worker as unknown as NotificationWorker,
      tokenCrypto as unknown as NotificationTokenCrypto,
      realtime as unknown as RealtimeBus
    );
    return { service, database, audit, worker, tokenCrypto, realtime };
  }

  const inboundSql = {
    preferences: `
        select role, channels
        from app.notification_preferences
        where event_type = $1 and enabled
      `,
    users: `
        select id, role::text as role, email
        from app.users
        where role::text = any($1::text[]) and deleted_at is null
        order by created_at desc
        limit 10000
      `,
    lead: `
        select lead.id,
          btrim(concat_ws(' ', lead.last_name, lead.first_name)) as name,
          coalesce(nullif(source.display_name, ''), nullif(lead.source, ''), 'Не указан') as source
        from app.leads lead
        left join app.lead_sources source on source.id = lead.source_id
        where lead.inbound_id = $1 and lead.deleted_at is null
        limit 1
      `,
    lock: 'select pg_advisory_xact_lock(hashtextextended($1::text, 0))',
    notification: `
          insert into app.notifications (id, type, title, body, data)
          values ($1, 'new_lead', $2, $3, $4::jsonb)
          on conflict (id) do nothing
        `,
    recipient: `
            insert into app.notification_recipients (notification_id, user_id, delivered_at)
            values ($1, $2, now())
            on conflict (notification_id, user_id) do nothing
          `,
    push: `
              insert into app.notification_deliveries (
                notification_id, user_id, channel, provider, status, attempt_count, last_error
              )
              select $1, $2, 'push', 'firebase', 'queued', 0, null
              where not exists (
                select 1 from app.notification_deliveries
                where notification_id = $1 and user_id = $2 and channel = 'push'
              )
            `,
    email: `
              insert into app.email_outbox (user_id, to_email_hash, template, payload)
              select $1, $2, 'new_lead', $3::jsonb
              where not exists (
                select 1 from app.email_outbox
                where user_id = $1
                  and template = 'new_lead'
                  and payload->>'notificationId' = $4
              )
            `
  } as const;

  function createInboundHarness(
    databaseRows: unknown[][],
    options: {
      failedClientQuery?: number;
      clientQueryResults?: Array<{ rows: unknown[]; rowCount: number }>;
    } = {}
  ) {
    const { service, database, worker, realtime } = createService();
    const ledger: unknown[] = [];
    let databaseQuery = 0;
    database.query.mockImplementation(async (sql, params) => {
      ledger.push({ event: 'database.query', sql, params });
      return { rows: databaseRows[databaseQuery++] ?? [] } as never;
    });
    const transactionError = new Error('transaction failed');
    let clientQuery = 0;
    const client = {
      query: jest.fn(async (sql: string, params?: unknown[]) => {
        ledger.push({ event: 'client.query', sql, params });
        const queryIndex = clientQuery++;
        if (queryIndex === options.failedClientQuery) throw transactionError;
        return options.clientQueryResults?.[queryIndex] ?? { rows: [] };
      })
    };
    database.transaction.mockImplementation(async (work) => {
      ledger.push({ event: 'transaction.begin' });
      try {
        const result = await work(client as never);
        ledger.push({ event: 'transaction.commit' });
        return result;
      } catch (error: unknown) {
        ledger.push({ event: 'transaction.rollback' });
        throw error;
      }
    });
    worker.dispatchPendingEmails.mockImplementation(async () => {
      ledger.push({ event: 'worker.email' });
      return { processed: 0, failed: 0 };
    });
    worker.dispatchPendingPush.mockImplementation(async () => {
      ledger.push({ event: 'worker.push' });
      return { processed: 0, failed: 0 };
    });
    realtime.emitCrmChanged.mockImplementation((payload) => {
      ledger.push({ event: 'realtime', payload });
    });
    return { service, ledger, transactionError };
  }

  it('waits for required OTP delivery and reports success only after a provider sends it', async () => {
    const { service, database, worker } = createService();
    database.query
      .mockResolvedValueOnce({ rows: [{ email: 'user@example.com' }] } as never)
      .mockResolvedValueOnce({ rows: [{ id: 'outbox-a' }] } as never);

    await expect(
      service.sendEmail({
        userId: 'user-a',
        template: 'auth_otp',
        title: 'Код',
        body: '123456',
        deliveryMode: 'required'
      })
    ).resolves.toEqual({ queued: true, delivered: true });

    expect(worker.dispatchEmailById).toHaveBeenCalledWith('outbox-a');
    expect(worker.exhaustEmail).not.toHaveBeenCalled();
  });

  it('stops retries when required OTP delivery fails', async () => {
    const { service, database, worker } = createService();
    database.query
      .mockResolvedValueOnce({ rows: [{ email: 'user@example.com' }] } as never)
      .mockResolvedValueOnce({ rows: [{ id: 'outbox-a' }] } as never);
    worker.dispatchEmailById.mockResolvedValueOnce({
      processed: true,
      status: 'retry'
    });

    await expect(
      service.sendEmail({
        userId: 'user-a',
        template: 'auth_otp',
        title: 'Код',
        body: '123456',
        deliveryMode: 'required'
      })
    ).resolves.toEqual({ queued: true, delivered: false });

    expect(worker.exhaustEmail).toHaveBeenCalledWith(
      'outbox-a',
      'required_delivery_failed'
    );
  });

  it('contains an immediate OTP worker error and exhausts the exact outbox row', async () => {
    const { service, database, worker } = createService();
    database.query
      .mockResolvedValueOnce({ rows: [{ email: 'user@example.com' }] } as never)
      .mockResolvedValueOnce({ rows: [{ id: 'outbox-a' }] } as never);
    worker.dispatchEmailById.mockRejectedValueOnce(new Error('provider timeout'));

    await expect(
      service.sendEmail({
        userId: 'user-a',
        template: 'auth_otp',
        title: 'Код',
        body: '123456',
        deliveryMode: 'required'
      })
    ).resolves.toEqual({ queued: true, delivered: false });

    expect(worker.exhaustEmail).toHaveBeenCalledWith(
      'outbox-a',
      'required_delivery_error'
    );
  });

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

  it('reuses an explicit notification id and guards channel side effects', async () => {
    const { service, database } = createService();
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [{ id: '11111111-1111-5111-8111-111111111111' }]
        })
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({ rows: [{ email: 'a@example.com' }] })
        .mockResolvedValue({ rows: [] })
    };
    database.transaction.mockImplementationOnce(async (work) => work(client as never));

    await service.notifyUser({
      userId: 'user-a',
      title: 'Напоминание',
      body: 'Открытая задача',
      data: { entityType: 'task', entityId: 'task-a' },
      channels: ['in_app', 'email', 'push'],
      notificationId: '11111111-1111-5111-8111-111111111111'
    });

    expect(String(client.query.mock.calls[0][0])).toContain('on conflict (id)');
    expect(client.query.mock.calls[0][1]?.[0]).toBe('11111111-1111-5111-8111-111111111111');
    expect(String(client.query.mock.calls[3][0])).toContain('where not exists');
    expect(String(client.query.mock.calls[4][0])).toContain('where not exists');
  });

  it('routes a rescheduled lesson to its successor and informs the removed teacher', async () => {
    const { service, database } = createService();
    database.query
      .mockResolvedValueOnce({
        rows: [
          {
            id: 'lesson-source',
            student_id: 'student-a',
            group_id: null,
            lead_id: null,
            teacher_id: 'teacher-old',
            teacher_user_id: 'user-old-teacher',
            successor_id: 'lesson-successor',
            when_local: '13.08.2026 10:00',
            branch_name: 'Центр',
            room_name: 'Аудитория 1'
          }
        ]
      } as never)
      .mockResolvedValueOnce({
        rows: [
          {
            id: 'lesson-successor',
            student_id: 'student-a',
            group_id: null,
            lead_id: null,
            teacher_id: 'teacher-new',
            teacher_user_id: 'user-new-teacher',
            successor_id: null,
            when_local: '14.08.2026 12:00',
            branch_name: 'Центр',
            room_name: 'Аудитория 2'
          }
        ]
      } as never)
      .mockResolvedValueOnce({
        rows: [
          { user_id: 'user-client' },
          { user_id: 'user-new-teacher' }
        ]
      } as never);
    const client = {
      query: jest.fn(async (sql: string, params?: unknown[]) =>
        sql.includes('insert into app.notifications')
          ? { rows: [{ id: params?.[0] }] }
          : { rows: [] }
      )
    };
    database.transaction.mockImplementation(async (work) => work(client as never));

    await service.notifyLessonChanged({
      eventId: '11111111-1111-4111-8111-111111111111',
      lessonId: 'lesson-source',
      action: 'rescheduled',
      successorId: 'lesson-successor'
    });

    const inserts = client.query.mock.calls.filter((call) =>
      String(call[0]).includes('insert into app.notifications')
    );
    expect(inserts).toHaveLength(2);
    expect(inserts[0][1]?.[0]).toBe('11111111-1111-4111-8111-111111111111');
    expect(inserts[0][1]?.[2]).toBe('Занятие перенесено');
    expect(JSON.parse(String(inserts[0][1]?.[4]))).toEqual({
      entityType: 'lesson',
      entityId: 'lesson-successor',
      eventType: 'rescheduled'
    });
    expect(inserts[1][1]?.[0]).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    );
    expect(inserts[1][1]?.[2]).toBe('Занятие переназначено');
    expect(JSON.parse(String(inserts[1][1]?.[4]))).toEqual({
      entityType: 'lesson',
      entityId: 'lesson-source',
      eventType: 'teacher_unassigned'
    });
  });

  it.each([
    ['created', 'Занятие назначено'],
    ['cancelled', 'Занятие отменено']
  ] as const)('materializes the %s lesson event with an exact route', async (action, title) => {
    const { service, database } = createService();
    database.query
      .mockResolvedValueOnce({
        rows: [
          {
            id: 'lesson-a',
            student_id: 'student-a',
            group_id: null,
            lead_id: null,
            teacher_id: 'teacher-a',
            teacher_user_id: 'user-teacher',
            successor_id: null,
            when_local: '14.08.2026 12:00',
            branch_name: 'Центр',
            room_name: 'Аудитория 1'
          }
        ]
      } as never)
      .mockResolvedValueOnce({ rows: [{ user_id: 'user-client' }] } as never);
    const client = {
      query: jest.fn(async (sql: string, params?: unknown[]) =>
        sql.includes('insert into app.notifications')
          ? { rows: [{ id: params?.[0] }] }
          : { rows: [] }
      )
    };
    database.transaction.mockImplementationOnce(async (work) => work(client as never));

    await service.notifyLessonChanged({
      eventId: '33333333-3333-4333-8333-333333333333',
      lessonId: 'lesson-a',
      action
    });

    const insert = client.query.mock.calls.find((call) =>
      String(call[0]).includes('insert into app.notifications')
    );
    expect(insert?.[1]?.[2]).toBe(title);
    expect(JSON.parse(String(insert?.[1]?.[4]))).toEqual({
      entityType: 'lesson',
      entityId: 'lesson-a',
      eventType: action
    });
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
      const client = {
        query: jest.fn(async (sql: string, _params?: unknown[]) =>
          sql.includes('insert into app.notifications')
            ? { rows: [{ id: 'notification-lesson' }] }
            : { rows: [] }
        )
      };
      database.transaction.mockImplementationOnce(async (work) => work(client as never));

      const result = await service.dispatchLessonReminders();

      expect(result.sent).toBe(1);
      // createNotification runs in a transaction exactly once (the day lesson).
      expect(database.transaction).toHaveBeenCalledTimes(1);
      const notificationInsert = client.query.mock.calls.find((call) =>
        String(call[0]).includes('insert into app.notifications')
      );
      expect(JSON.parse(String(notificationInsert?.[1]?.[4]))).toEqual({
        entityType: 'lesson',
        entityId: 'lesson-1',
        kind: 'day'
      });
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

  describe('inbound lead notification', () => {
    const ingestionId = 'ingestion-a';
    const notificationId = '11111111-1111-4111-8111-111111111111';

    it('stops after preferences when every role opted out', async () => {
      const { service, ledger } = createInboundHarness([[]]);

      await expect(
        service.notifyInboundLead(ingestionId, notificationId)
      ).resolves.toBeUndefined();

      expect(ledger).toEqual([
        {
          event: 'database.query',
          sql: inboundSql.preferences,
          params: ['new_lead']
        }
      ]);
    });

    it('stops after the ordered recipient lookup when no staff users exist', async () => {
      const { service, ledger } = createInboundHarness([
        [{ role: 'manager', channels: ['push'] }],
        []
      ]);

      await expect(
        service.notifyInboundLead(ingestionId, notificationId)
      ).resolves.toBeUndefined();

      expect(ledger).toEqual([
        {
          event: 'database.query',
          sql: inboundSql.preferences,
          params: ['new_lead']
        },
        {
          event: 'database.query',
          sql: inboundSql.users,
          params: [['manager']]
        }
      ]);
    });

    it('reports the exact not-found error after preferences and recipients', async () => {
      const { service, ledger } = createInboundHarness([
        [{ role: 'manager', channels: ['in_app'] }],
        [{ id: 'manager-a', role: 'manager', email: 'manager@example.com' }],
        []
      ]);

      const result = service.notifyInboundLead(ingestionId, notificationId);

      await expect(result).rejects.toBeInstanceOf(NotFoundException);
      await expect(result).rejects.toMatchObject({
        message: 'Входящая заявка не найдена.',
        response: {
          error: 'Not Found',
          message: 'Входящая заявка не найдена.',
          statusCode: 404
        },
        status: 404
      });
      expect(ledger).toEqual([
        {
          event: 'database.query',
          sql: inboundSql.preferences,
          params: ['new_lead']
        },
        {
          event: 'database.query',
          sql: inboundSql.users,
          params: [['manager']]
        },
        {
          event: 'database.query',
          sql: inboundSql.lead,
          params: [ingestionId]
        }
      ]);
    });

    it('persists mixed channels under the advisory lock before dispatch and realtime', async () => {
      const { service, ledger } = createInboundHarness([
        [
          { role: 'manager', channels: ['push', 'email', 'invalid'] },
          { role: 'admin', channels: ['in_app'] },
          { role: 'teacher', channels: [] }
        ],
        [
          { id: 'manager-a', role: 'manager', email: 'Manager@Example.COM' },
          { id: 'admin-a', role: 'admin', email: 'admin@example.com' },
          { id: 'manager-b', role: 'manager', email: '' }
        ],
        [{ id: 'lead-a', name: 'Лид Входящий', source: 'Веб-сайт' }]
      ]);
      const title = 'Новая заявка';
      const body = 'Лид Входящий — источник: Веб-сайт';

      await expect(
        service.notifyInboundLead(ingestionId, notificationId)
      ).resolves.toBeUndefined();

      expect(ledger).toEqual([
        {
          event: 'database.query',
          sql: inboundSql.preferences,
          params: ['new_lead']
        },
        {
          event: 'database.query',
          sql: inboundSql.users,
          params: [['manager', 'admin']]
        },
        {
          event: 'database.query',
          sql: inboundSql.lead,
          params: [ingestionId]
        },
        { event: 'transaction.begin' },
        {
          event: 'client.query',
          sql: inboundSql.lock,
          params: [notificationId]
        },
        {
          event: 'client.query',
          sql: inboundSql.notification,
          params: [
            notificationId,
            title,
            body,
            '{"entityType":"lead","entityId":"lead-a","entityName":"Лид Входящий"}'
          ]
        },
        {
          event: 'client.query',
          sql: inboundSql.recipient,
          params: [notificationId, 'manager-a']
        },
        {
          event: 'client.query',
          sql: inboundSql.push,
          params: [notificationId, 'manager-a']
        },
        {
          event: 'client.query',
          sql: inboundSql.email,
          params: [
            'manager-a',
            'cac240a80a231858a6b2451937984adce384b9b2b1995b7c71b332c580aac6e6',
            '{"notificationId":"11111111-1111-4111-8111-111111111111","title":"Новая заявка","body":"Лид Входящий — источник: Веб-сайт"}',
            notificationId
          ]
        },
        {
          event: 'client.query',
          sql: inboundSql.recipient,
          params: [notificationId, 'admin-a']
        },
        {
          event: 'client.query',
          sql: inboundSql.recipient,
          params: [notificationId, 'manager-b']
        },
        {
          event: 'client.query',
          sql: inboundSql.push,
          params: [notificationId, 'manager-b']
        },
        { event: 'transaction.commit' },
        { event: 'worker.email' },
        { event: 'worker.push' },
        {
          event: 'realtime',
          payload: {
            entity: 'notification',
            action: 'created',
            id: notificationId,
            affectedUserIds: ['manager-a', 'admin-a', 'manager-b']
          }
        }
      ]);
    });

    it('repairs notification and recipient conflicts without skipping deliveries', async () => {
      const { service, ledger } = createInboundHarness(
        [
          [{ role: 'manager', channels: ['push', 'email'] }],
          [{ id: 'manager-a', role: 'manager', email: 'Manager@Example.COM' }],
          [{ id: 'lead-a', name: 'Лид Входящий', source: 'Веб-сайт' }]
        ],
        {
          clientQueryResults: [
            { rows: [], rowCount: 1 },
            { rows: [], rowCount: 0 },
            { rows: [], rowCount: 0 },
            { rows: [], rowCount: 1 },
            { rows: [], rowCount: 1 }
          ]
        }
      );

      await expect(
        service.notifyInboundLead(ingestionId, notificationId)
      ).resolves.toBeUndefined();

      expect(ledger).toEqual([
        {
          event: 'database.query',
          sql: inboundSql.preferences,
          params: ['new_lead']
        },
        {
          event: 'database.query',
          sql: inboundSql.users,
          params: [['manager']]
        },
        {
          event: 'database.query',
          sql: inboundSql.lead,
          params: [ingestionId]
        },
        { event: 'transaction.begin' },
        {
          event: 'client.query',
          sql: inboundSql.lock,
          params: [notificationId]
        },
        {
          event: 'client.query',
          sql: inboundSql.notification,
          params: [
            notificationId,
            'Новая заявка',
            'Лид Входящий — источник: Веб-сайт',
            '{"entityType":"lead","entityId":"lead-a","entityName":"Лид Входящий"}'
          ]
        },
        {
          event: 'client.query',
          sql: inboundSql.recipient,
          params: [notificationId, 'manager-a']
        },
        {
          event: 'client.query',
          sql: inboundSql.push,
          params: [notificationId, 'manager-a']
        },
        {
          event: 'client.query',
          sql: inboundSql.email,
          params: [
            'manager-a',
            'cac240a80a231858a6b2451937984adce384b9b2b1995b7c71b332c580aac6e6',
            '{"notificationId":"11111111-1111-4111-8111-111111111111","title":"Новая заявка","body":"Лид Входящий — источник: Веб-сайт"}',
            notificationId
          ]
        },
        { event: 'transaction.commit' },
        { event: 'worker.email' },
        { event: 'worker.push' },
        {
          event: 'realtime',
          payload: {
            entity: 'notification',
            action: 'created',
            id: notificationId,
            affectedUserIds: ['manager-a']
          }
        }
      ]);
    });

    it('does not dispatch workers or realtime when the transaction fails', async () => {
      const { service, ledger, transactionError } = createInboundHarness(
        [
          [{ role: 'manager', channels: ['push', 'email'] }],
          [{ id: 'manager-a', role: 'manager', email: 'manager@example.com' }],
          [{ id: 'lead-a', name: 'Лид Входящий', source: 'Веб-сайт' }]
        ],
        { failedClientQuery: 2 }
      );

      await expect(
        service.notifyInboundLead(ingestionId, notificationId)
      ).rejects.toBe(transactionError);

      expect(ledger).toEqual([
        {
          event: 'database.query',
          sql: inboundSql.preferences,
          params: ['new_lead']
        },
        {
          event: 'database.query',
          sql: inboundSql.users,
          params: [['manager']]
        },
        {
          event: 'database.query',
          sql: inboundSql.lead,
          params: [ingestionId]
        },
        { event: 'transaction.begin' },
        {
          event: 'client.query',
          sql: inboundSql.lock,
          params: [notificationId]
        },
        {
          event: 'client.query',
          sql: inboundSql.notification,
          params: [
            notificationId,
            'Новая заявка',
            'Лид Входящий — источник: Веб-сайт',
            '{"entityType":"lead","entityId":"lead-a","entityName":"Лид Входящий"}'
          ]
        },
        {
          event: 'client.query',
          sql: inboundSql.recipient,
          params: [notificationId, 'manager-a']
        },
        { event: 'transaction.rollback' }
      ]);
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
