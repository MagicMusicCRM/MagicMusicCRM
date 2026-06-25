import {
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { AuditService } from '../audit/audit.service';
import { ActorContext, UserRole } from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';
import { AdminSendNotificationDto } from './dto/admin-send-notification.dto';
import { ListNotificationsQuery } from './dto/list-notifications.query';
import { RegisterDeviceDto } from './dto/register-device.dto';
import { NotificationTokenCrypto } from './notification-token-crypto.service';
import { NotificationWorker } from './notification-worker.service';
import { NotificationsPolicy } from './notifications.policy';
import { NotificationChannel } from './notifications.types';
import { RealtimeBus } from '../realtime/realtime-bus';

interface NotificationRow {
  id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  created_by: string | null;
  created_at: Date | string;
  recipient_id: string;
  is_read: boolean;
  read_at: Date | string | null;
  delivered_at: Date | string | null;
}

interface CountRow {
  total: string;
}

interface RecipientRow {
  notification_id: string;
  user_id: string;
}

interface DeviceRow {
  id: string;
  user_id: string;
  platform: string;
  token_hash: string;
  enabled: boolean;
  last_seen_at: Date | string;
  created_at: Date | string;
  updated_at: Date | string;
}

@Injectable()
export class NotificationsService implements OnModuleInit, OnModuleDestroy {
  private reminderTimer?: NodeJS.Timeout;
  private readonly logger = new Logger('LessonReminders');

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: NotificationsPolicy,
    private readonly worker: NotificationWorker,
    private readonly tokenCrypto: NotificationTokenCrypto,
    private readonly realtime: RealtimeBus
  ) {}

  onModuleInit(): void {
    // Kill-switch: the scheduler is OFF unless explicitly enabled, so deploying
    // the code never starts pushing to real students by surprise. Enable with
    // LESSON_REMINDERS_ENABLED=true once the deployment is verified.
    if (process.env.LESSON_REMINDERS_ENABLED !== 'true') {
      this.logger.log(
        'Lesson reminders disabled (set LESSON_REMINDERS_ENABLED=true to enable)'
      );
      return;
    }
    // Scan for upcoming lessons and enqueue -24h / -1h reminders every 5 min.
    this.reminderTimer = setInterval(() => {
      void this.dispatchLessonReminders()
        .then(({ sent }) => {
          if (sent > 0) this.logger.log(`Lesson reminders enqueued: ${sent}`);
        })
        .catch((error: unknown) => {
          this.logger.error(
            `Lesson reminder tick failed: ${this.errorName(error)}`
          );
        });
    }, 5 * 60_000);
    this.reminderTimer.unref?.();
    this.logger.log('Lesson reminder scheduler started (every 5m)');
  }

  onModuleDestroy(): void {
    if (this.reminderTimer) clearInterval(this.reminderTimer);
  }

  // Enqueue lesson reminders. Idempotent via app.lesson_reminders: each
  // (lesson, kind) is claimed before sending, so a reminder is never sent
  // twice even if two ticks overlap. Cancelled/rescheduled lessons fall out of
  // the window automatically (status <> 'scheduled').
  async dispatchLessonReminders(): Promise<{ sent: number }> {
    let sent = 0;
    // "За день": fire once the lesson is within 24h but still more than 12h
    // away. The 12h floor (a) avoids a misleading "tomorrow" reminder for a
    // lesson only a few hours out and (b) prevents a first-enable blast of
    // "day" reminders for already-imminent lessons — those get only the -1h
    // reminder when they reach the hour window.
    sent += await this.processReminderKind(
      'day',
      "l.scheduled_at > now() + interval '12 hours' and l.scheduled_at <= now() + interval '24 hours'",
      'Напоминание о занятии',
      (when) => `Напоминаем о занятии ${when} (по Москве).`
    );
    // "За час": fire within the last hour before the lesson.
    sent += await this.processReminderKind(
      'hour',
      "l.scheduled_at > now() and l.scheduled_at <= now() + interval '1 hour'",
      'Скоро занятие',
      (when) => `Ваше занятие начнётся примерно через час — ${when} (по Москве).`
    );
    // Flush the push queue promptly instead of waiting for the worker's timer.
    if (sent > 0) this.schedulePushDispatch();
    return { sent };
  }

  private async processReminderKind(
    kind: 'day' | 'hour',
    windowSql: string,
    title: string,
    bodyFor: (when: string) => string
  ): Promise<number> {
    const due = await this.database.query<{
      id: string;
      when_local: string;
      user_ids: string[];
    }>(
      `
        with due as (
          select l.id, l.student_id, l.group_id,
            to_char(l.scheduled_at at time zone 'Europe/Moscow', 'DD.MM HH24:MI') as when_local
          from app.lessons l
          where l.deleted_at is null
            and l.status = 'scheduled'
            and ${windowSql}
            and not exists (
              select 1 from app.lesson_reminders lr
              where lr.lesson_id = l.id and lr.kind = $1
            )
          order by l.scheduled_at asc
          limit 200
        )
        select d.id, d.when_local,
          (
            select coalesce(array_agg(distinct uid), '{}')
            from (
              select sp.user_id as uid
              from app.students s
              join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
              where s.id = d.student_id and s.deleted_at is null
                and s.status = 'active' and sp.user_id is not null
              union
              select gsp.user_id as uid
              from app.group_students gs
              join app.students gss on gss.id = gs.student_id and gss.deleted_at is null
              join app.profiles gsp on gsp.id = gss.profile_id and gsp.deleted_at is null
              where gs.group_id = d.group_id and gs.left_at is null
                and gss.status = 'active' and gsp.user_id is not null
            ) recips
          ) as user_ids
        from due d
      `,
      [kind]
    );

    let sent = 0;
    for (const row of due.rows) {
      // Claim the marker first; only the call that inserts the row sends.
      const claim = await this.database.query<{ id: string }>(
        `
          insert into app.lesson_reminders (lesson_id, kind)
          values ($1, $2)
          on conflict (lesson_id, kind) do nothing
          returning id
        `,
        [row.id, kind]
      );
      if (claim.rowCount === 0) continue;
      const userIds = (row.user_ids ?? []).filter(Boolean);
      if (userIds.length === 0) continue; // nobody to notify; marker stays
      try {
        await this.createNotification({
          type: 'lesson_reminder',
          title,
          body: bodyFor(row.when_local),
          data: { lessonId: row.id, kind },
          userIds,
          channels: ['push']
        });
        sent += 1;
      } catch (error: unknown) {
        // Marker already set — do not retry, to avoid spamming on transient
        // delivery errors. Surface it so a misfire is observable.
        this.logger.error(
          `Failed to enqueue ${kind} reminder for lesson ${row.id}: ${this.errorName(error)}`
        );
      }
    }
    return sent;
  }

  async list(actor: ActorContext, query: ListNotificationsQuery) {
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<NotificationRow & CountRow>(
      `
        select n.id, n.type, n.title, n.body, n.data, n.created_by, n.created_at,
          nr.id as recipient_id, nr.is_read, nr.read_at, nr.delivered_at,
          count(*) over() as total
        from app.notification_recipients nr
        join app.notifications n on n.id = nr.notification_id
        where nr.user_id = $1
          and ($2::boolean is null or nr.is_read = false)
          and ($3::timestamptz is null or n.created_at < $3::timestamptz)
        order by n.created_at desc, n.id desc
        limit $4
      `,
      [actor.userId, query.unread ?? null, query.cursor ?? null, limit]
    );

    return {
      items: result.rows.map((row) => this.toNotificationDto(row)),
      total: Number(result.rows[0]?.total ?? '0')
    };
  }

  async markRead(actor: ActorContext, notificationId: string) {
    const recipient = await this.requireRecipient(actor, notificationId);
    this.policy.assertCanReadRecipient(actor, recipient);
    const result = await this.database.query<NotificationRow>(
      `
        update app.notification_recipients nr
        set is_read = true, read_at = coalesce(read_at, now())
        from app.notifications n
        where nr.notification_id = n.id
          and nr.notification_id = $1
          and nr.user_id = $2
        returning n.id, n.type, n.title, n.body, n.data, n.created_by, n.created_at,
          nr.id as recipient_id, nr.is_read, nr.read_at, nr.delivered_at
      `,
      [notificationId, actor.userId]
    );
    return this.toNotificationDto(result.rows[0]);
  }

  async markAllRead(actor: ActorContext) {
    await this.database.query(
      `
        update app.notification_recipients
        set is_read = true, read_at = coalesce(read_at, now())
        where user_id = $1 and is_read = false
      `,
      [actor.userId]
    );
    return { success: true };
  }

  async registerDevice(actor: ActorContext, dto: RegisterDeviceDto) {
    const tokenHash = this.tokenCrypto.hash(dto.token);
    const encryptedToken = this.tokenCrypto.encrypt(dto.token);
    const result = await this.database.query<DeviceRow>(
      `
        insert into app.notification_devices (
          user_id, platform, token_hash, encrypted_token, enabled, last_seen_at
        )
        values ($1, $2, $3, $4, true, now())
        on conflict (user_id, token_hash) do update
        set platform = excluded.platform,
            enabled = true,
            last_seen_at = now(),
            updated_at = now()
        returning id, user_id, platform, token_hash, enabled, last_seen_at, created_at, updated_at
      `,
      [actor.userId, dto.platform, tokenHash, encryptedToken]
    );
    await this.audit.record({
      actor,
      action: 'notifications.device_registered',
      entityType: 'notification_device',
      entityId: result.rows[0].id,
      metadata: { platform: dto.platform, tokenHash }
    });
    return this.toDeviceDto(result.rows[0]);
  }

  async deleteDevice(actor: ActorContext, id: string) {
    const result = await this.database.query<DeviceRow>(
      `
        update app.notification_devices
        set enabled = false, updated_at = now()
        where id = $1 and user_id = $2 and enabled = true
        returning id, user_id, platform, token_hash, enabled, last_seen_at, created_at, updated_at
      `,
      [id, actor.userId]
    );
    const device = result.rows[0];
    if (!device) throw new NotFoundException('Устройство не найдено.');
    await this.audit.record({
      actor,
      action: 'notifications.device_deleted',
      entityType: 'notification_device',
      entityId: id
    });
    return { success: true };
  }

  async adminSend(actor: ActorContext, dto: AdminSendNotificationDto) {
    this.policy.assertCanAdminSend(actor);
    const channels = dto.channels ?? ['in_app'];
    const userIds = await this.resolveTargetUsers(dto);
    const notificationId = await this.createNotification({
      actor,
      type: 'admin_broadcast',
      title: dto.title.trim(),
      body: dto.body.trim(),
      data: this.sanitizeData(dto.data),
      userIds,
      channels
    });
    await this.audit.record({
      actor,
      action: 'notifications.admin_sent',
      entityType: 'notification',
      entityId: notificationId,
      metadata: { target: dto.target, count: userIds.length, channels }
    });
    this.scheduleDelivery(channels);
    return { notificationId, recipientCount: userIds.length };
  }

  async notifyUser(input: {
    userId: string;
    title: string;
    body: string;
    data?: Record<string, unknown>;
    channels?: NotificationChannel[];
  }): Promise<{ notificationId: string }> {
    const channels = input.channels ?? ['in_app'];
    const notificationId = await this.createNotification({
      type: 'system',
      title: input.title,
      body: input.body,
      data: this.sanitizeData(input.data),
      userIds: [input.userId],
      channels
    });
    this.scheduleDelivery(channels);
    return { notificationId };
  }

  async sendEmail(input: {
    userId: string;
    template: string;
    title: string;
    body: string;
  }): Promise<{ queued: true }> {
    const user = await this.database.query<{ email: string }>(
      'select email from app.users where id = $1 and deleted_at is null limit 1',
      [input.userId]
    );
    const email = user.rows[0]?.email;
    if (!email) return { queued: true };
    await this.enqueueEmail(input.userId, email, input.template, {
      title: input.title,
      body: input.body
    });
    this.scheduleEmailDispatch();
    return { queued: true };
  }

  private async createNotification(input: {
    actor?: ActorContext;
    type: string;
    title: string;
    body: string;
    data: Record<string, unknown>;
    userIds: string[];
    channels: NotificationChannel[];
  }): Promise<string> {
    if (input.userIds.length === 0) throw new NotFoundException('Получатели не найдены.');
    const uniqueUserIds = [...new Set(input.userIds)];
    const notificationId = await this.database.transaction(async (client) => {
      const notification = await client.query<{ id: string }>(
        `
          insert into app.notifications (type, title, body, data, created_by)
          values ($1, $2, $3, $4::jsonb, $5)
          returning id
        `,
        [
          input.type,
          input.title,
          input.body,
          JSON.stringify(input.data),
          input.actor?.userId ?? null
        ]
      );
      const notificationId = notification.rows[0].id;
      for (const userId of uniqueUserIds) {
        await client.query(
          `
            insert into app.notification_recipients (notification_id, user_id, delivered_at)
            values ($1, $2, now())
            on conflict (notification_id, user_id) do nothing
          `,
          [notificationId, userId]
        );
        if (input.channels.includes('email')) {
          const user = await client.query<{ email: string }>(
            'select email from app.users where id = $1 and deleted_at is null limit 1',
            [userId]
          );
          if (user.rows[0]?.email) {
            await client.query(
              `
                insert into app.email_outbox (user_id, to_email_hash, template, payload)
                values ($1, $2, $3, $4::jsonb)
              `,
              [
                userId,
                this.sha256(user.rows[0].email.toLowerCase()),
                input.type,
                JSON.stringify({ notificationId, title: input.title, body: input.body })
              ]
            );
          }
        }
        if (input.channels.includes('push')) {
          await client.query(
            `
              insert into app.notification_deliveries (
                notification_id, user_id, channel, provider, status, attempt_count, last_error
              )
              values ($1, $2, 'push', 'firebase', 'queued', 0, null)
            `,
            [notificationId, userId]
          );
        }
      }
      return notificationId;
    });
    // After the row + recipients commit, nudge each recipient's bell live so the
    // unread badge updates without a poll. Scoped per-user via affectedUserIds.
    this.realtime.emitCrmChanged({
      entity: 'notification',
      action: 'created',
      id: notificationId,
      affectedUserIds: uniqueUserIds
    });
    return notificationId;
  }

  private async enqueueEmail(
    userId: string,
    email: string,
    template: string,
    payload: Record<string, unknown>
  ): Promise<void> {
    await this.database.query(
      `
        insert into app.email_outbox (user_id, to_email_hash, template, payload)
        values ($1, $2, $3, $4::jsonb)
      `,
      [userId, this.sha256(email.toLowerCase()), template, JSON.stringify(payload)]
    );
  }

  private async requireRecipient(
    actor: ActorContext,
    notificationId: string
  ): Promise<RecipientRow> {
    const result = await this.database.query<RecipientRow>(
      `
        select notification_id, user_id
        from app.notification_recipients
        where notification_id = $1 and user_id = $2
        limit 1
      `,
      [notificationId, actor.userId]
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException('Уведомление не найдено.');
    return row;
  }

  private async resolveTargetUsers(dto: AdminSendNotificationDto): Promise<string[]> {
    if (dto.target === 'users') return dto.userIds ?? [];
    if (dto.target === 'role') return this.findUsersByRole(dto.role!);
    const result = await this.database.query<{ id: string }>(
      'select id from app.users where deleted_at is null order by created_at desc limit 10000'
    );
    return result.rows.map((row) => row.id);
  }

  private async findUsersByRole(role: UserRole): Promise<string[]> {
    const result = await this.database.query<{ id: string }>(
      'select id from app.users where role = $1::app.user_role and deleted_at is null order by created_at desc limit 10000',
      [role]
    );
    return result.rows.map((row) => row.id);
  }

  private sanitizeData(data: Record<string, unknown> = {}): Record<string, unknown> {
    const allowed = new Set(['route', 'entityType', 'entityId', 'chatId', 'lessonId']);
    return Object.fromEntries(
      Object.entries(data).filter(([key, value]) => allowed.has(key) && typeof value !== 'object')
    );
  }

  private sha256(value: string): string {
    return createHash('sha256').update(value).digest('hex');
  }

  private scheduleEmailDispatch(): void {
    void this.worker.dispatchPendingEmails().catch((error: unknown) => {
      void this.audit
        .record({
          action: 'notifications.email_dispatch_failed',
          entityType: 'email_outbox',
          metadata: { error: this.errorName(error) }
        })
        .catch(() => undefined);
    });
  }

  private schedulePushDispatch(): void {
    void this.worker.dispatchPendingPush().catch((error: unknown) => {
      void this.audit
        .record({
          action: 'notifications.push_dispatch_failed',
          entityType: 'notification_delivery',
          metadata: { error: this.errorName(error) }
        })
        .catch(() => undefined);
    });
  }

  private scheduleDelivery(channels: NotificationChannel[]): void {
    if (channels.includes('email')) this.scheduleEmailDispatch();
    if (channels.includes('push')) this.schedulePushDispatch();
  }

  private errorName(error: unknown): string {
    return error instanceof Error && error.name ? error.name.slice(0, 80) : 'dispatch_failed';
  }

  private toNotificationDto(row: NotificationRow) {
    return {
      id: row.id,
      type: row.type,
      title: row.title,
      body: row.body,
      data: row.data,
      createdBy: row.created_by,
      createdAt: row.created_at,
      isRead: row.is_read,
      readAt: row.read_at,
      deliveredAt: row.delivered_at
    };
  }

  private toDeviceDto(row: DeviceRow) {
    return {
      id: row.id,
      userId: row.user_id,
      platform: row.platform,
      tokenHash: row.token_hash,
      enabled: row.enabled,
      lastSeenAt: row.last_seen_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    };
  }
}
