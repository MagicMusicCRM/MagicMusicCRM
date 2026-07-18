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
import { UpdateNotificationPreferenceDto } from './dto/update-notification-preference.dto';
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
    // Kill-switches: each scheduler is OFF unless explicitly enabled, so
    // deploying the code never starts pushing to real users by surprise.
    // Enable with LESSON_REMINDERS_ENABLED=true / TASK_REMINDERS_ENABLED=true
    // once the deployment is verified.
    const lessonsEnabled = process.env.LESSON_REMINDERS_ENABLED === 'true';
    const tasksEnabled = process.env.TASK_REMINDERS_ENABLED === 'true';
    if (!lessonsEnabled) {
      this.logger.log(
        'Lesson reminders disabled (set LESSON_REMINDERS_ENABLED=true to enable)'
      );
    }
    if (!tasksEnabled) {
      this.logger.log(
        'Task reminders disabled (set TASK_REMINDERS_ENABLED=true to enable)'
      );
    }
    if (!lessonsEnabled && !tasksEnabled) return;
    // Scan every minute: the -10m and overdue task reminders are only as
    // punctual as the tick, so a 5-minute scan would deliver "10 minutes left"
    // anywhere from 5 to 10 minutes out. Each tick is a bounded (limit 200)
    // indexed lookup, so the extra frequency is cheap.
    this.reminderTimer = setInterval(() => {
      if (lessonsEnabled) {
        void this.dispatchLessonReminders()
          .then(({ sent }) => {
            if (sent > 0) this.logger.log(`Lesson reminders enqueued: ${sent}`);
          })
          .catch((error: unknown) => {
            this.logger.error(
              `Lesson reminder tick failed: ${this.errorName(error)}`
            );
          });
      }
      if (tasksEnabled) {
        void this.dispatchTaskReminders()
          .then(({ sent }) => {
            if (sent > 0) this.logger.log(`Task reminders enqueued: ${sent}`);
          })
          .catch((error: unknown) => {
            this.logger.error(
              `Task reminder tick failed: ${this.errorName(error)}`
            );
          });
      }
    }, 60_000);
    this.reminderTimer.unref?.();
    this.logger.log('Reminder scheduler started (every 1m)');
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

  // Enqueue task due-date reminders. Same idempotency pattern as lesson
  // reminders: each (task, kind) is claimed in app.task_reminders before
  // sending, so a reminder is never sent twice even if two ticks overlap.
  async dispatchTaskReminders(): Promise<{ sent: number }> {
    let sent = 0;
    // "За день": fire once the deadline is within 24h but still more than 12h
    // away (same floor rationale as lesson reminders: no misleading "tomorrow"
    // for an already-imminent deadline, no first-enable blast).
    sent += await this.processTaskReminderKind(
      'day',
      "t.due_at > now() + interval '12 hours' and t.due_at <= now() + interval '24 hours'",
      'Задача: срок завтра',
      (title, when) => `«${title}» — срок ${when} (по Москве).`
    );
    // "За час": fire within the last hour before the deadline.
    sent += await this.processTaskReminderKind(
      'hour',
      "t.due_at > now() and t.due_at <= now() + interval '1 hour'",
      'Задача: срок через час',
      (title, when) => `«${title}» — срок ${when} (по Москве).`
    );
    // "За 10 минут": the last stretch before the deadline. Overlapping the
    // 'hour' window is intended — they are separate kinds, so both land.
    sent += await this.processTaskReminderKind(
      'min10',
      "t.due_at > now() and t.due_at <= now() + interval '10 minutes'",
      'Задача: срок через 10 минут',
      (title, when) => `«${title}» — срок ${when} (по Москве).`
    );
    // "Просрочено": one minute past the deadline. The 1-hour floor is what
    // stops a first-enable blast — without it, every task overdue since the
    // dawn of the database would fire on the first tick.
    sent += await this.processTaskReminderKind(
      'overdue',
      "t.due_at <= now() - interval '1 minute' and t.due_at > now() - interval '1 hour'",
      'Задача просрочена',
      (title, when) => `«${title}» — срок был ${when} (по Москве).`
    );
    if (sent > 0) this.schedulePushDispatch();
    return { sent };
  }

  /**
   * Roles that opted into an event, with the channels each wants. Empty map =
   * nobody subscribed, which is a legitimate configuration (the whole point of
   * a settings screen), not a failure.
   */
  private async loadRoleChannels(
    eventType: string
  ): Promise<Map<string, NotificationChannel[]>> {
    const result = await this.database.query<{
      role: string;
      channels: string[];
    }>(
      `
        select role, channels
        from app.notification_preferences
        where event_type = $1 and enabled
      `,
      [eventType]
    );
    const byRole = new Map<string, NotificationChannel[]>();
    for (const row of result.rows) {
      const channels = (row.channels ?? []).filter((channel): channel is NotificationChannel =>
        channel === 'in_app' || channel === 'push' || channel === 'email'
      );
      if (channels.length > 0) byRole.set(row.role, channels);
    }
    return byRole;
  }

  /**
   * Buckets recipients by the channel set they want, because createNotification
   * applies ONE channel list to every recipient it is given. One notification
   * row per distinct channel set; each user still gets exactly one recipient
   * row, so the bell never doubles up.
   */
  private groupRecipientsByChannels(
    recipients: { id: string; role: string }[],
    assignedTo: string | null,
    roleChannels: Map<string, NotificationChannel[]>,
    assigneeFallback: NotificationChannel[]
  ): Map<string, { channels: NotificationChannel[]; userIds: string[] }> {
    const groups = new Map<
      string,
      { channels: NotificationChannel[]; userIds: string[] }
    >();
    for (const recipient of recipients) {
      // The assignee is notified about their own task even when their role has
      // opted out of the broadcast — "assigned to you" is not a preference.
      const channels =
        roleChannels.get(recipient.role) ??
        (recipient.id === assignedTo ? assigneeFallback : null);
      if (!channels || channels.length === 0) continue;
      const key = [...channels].sort().join(',');
      const group = groups.get(key) ?? { channels, userIds: [] };
      if (!group.userIds.includes(recipient.id)) group.userIds.push(recipient.id);
      groups.set(key, group);
    }
    return groups;
  }

  private async processTaskReminderKind(
    kind: 'day' | 'hour' | 'min10' | 'overdue',
    windowSql: string,
    title: string,
    bodyFor: (taskTitle: string, when: string) => string
  ): Promise<number> {
    // Recipients are configuration now (app.notification_preferences), not a
    // literal in this query — see migration 0062.
    const roleChannels = await this.loadRoleChannels(`task_reminder_${kind}`);
    const roles = [...roleChannels.keys()];
    const due = await this.database.query<{
      id: string;
      title: string;
      when_local: string;
      assigned_to: string | null;
      recipients: { id: string; role: string }[];
    }>(
      `
        with due as (
          select t.id, t.title, t.assigned_to,
            to_char(t.due_at at time zone 'Europe/Moscow', 'DD.MM HH24:MI') as when_local
          from app.tasks t
          where t.deleted_at is null
            and t.status in ('open', 'in_progress')
            and ${windowSql}
            and not exists (
              select 1 from app.task_reminders tr
              where tr.task_id = t.id and tr.kind = $1
            )
          order by t.due_at asc
          limit 200
        )
        select d.id, d.title, d.when_local, d.assigned_to,
          (
            -- Recipients: the assignee (always) plus every role subscribed to
            -- this event. Roles are compared as text on purpose: 'director' may
            -- not exist in the app.user_role enum yet and an enum cast would
            -- make the whole query throw.
            select coalesce(
              json_agg(json_build_object('id', u.id, 'role', u.role::text)),
              '[]'::json
            )
            from app.users u
            where u.deleted_at is null
              and (u.role::text = any($2::text[]) or u.id = d.assigned_to)
          ) as recipients
        from due d
      `,
      [kind, roles]
    );

    let sent = 0;
    for (const row of due.rows) {
      // Claim the marker first; only the call that inserts the row sends.
      const claim = await this.database.query<{ id: string }>(
        `
          insert into app.task_reminders (task_id, kind)
          values ($1, $2)
          on conflict (task_id, kind) do nothing
          returning id
        `,
        [row.id, kind]
      );
      if (claim.rowCount === 0) continue;
      const groups = this.groupRecipientsByChannels(
        row.recipients ?? [],
        row.assigned_to,
        roleChannels,
        // Historic behaviour for an assignee whose role opted out: push only.
        ['push']
      );
      if (groups.size === 0) continue; // nobody to notify; marker stays
      try {
        for (const group of groups.values()) {
          await this.createNotification({
            type: 'task_reminder',
            title,
            body: bodyFor(row.title, row.when_local),
            data: { entityType: 'task', entityId: row.id },
            userIds: group.userIds,
            channels: group.channels
          });
        }
        sent += 1;
      } catch (error: unknown) {
        // Marker already set — do not retry, to avoid spamming on transient
        // delivery errors. Surface it so a misfire is observable.
        this.logger.error(
          `Failed to enqueue ${kind} reminder for task ${row.id}: ${this.errorName(error)}`
        );
      }
    }
    return sent;
  }

  /**
   * The whole preference matrix (role × event), for the settings screen.
   * Deliberately unfiltered by the caller's own role: this configures who the
   * school notifies, not what the caller personally receives.
   */
  async listPreferences(actor: ActorContext) {
    this.policy.assertCanManagePreferences(actor);
    const result = await this.database.query<{
      role: string;
      event_type: string;
      enabled: boolean;
      channels: string[];
      updated_at: Date | string;
    }>(
      `
        select role, event_type, enabled, channels, updated_at
        from app.notification_preferences
        order by event_type asc, role asc
      `
    );
    return {
      items: result.rows.map((row) => ({
        role: row.role,
        eventType: row.event_type,
        enabled: row.enabled,
        channels: row.channels ?? [],
        updatedAt:
          row.updated_at instanceof Date
            ? row.updated_at.toISOString()
            : row.updated_at
      }))
    };
  }

  async updatePreference(
    actor: ActorContext,
    dto: UpdateNotificationPreferenceDto
  ) {
    this.policy.assertCanManagePreferences(actor);
    // Upsert rather than update: migration 0062 seeds every (role, event) pair,
    // but a role added later would otherwise have no row to update.
    const result = await this.database.query<{
      role: string;
      event_type: string;
      enabled: boolean;
      channels: string[];
    }>(
      `
        insert into app.notification_preferences (
          role, event_type, enabled, channels, updated_by, updated_at
        )
        values ($1, $2, $3, $4::text[], $5, now())
        on conflict (role, event_type) do update
          set enabled = excluded.enabled,
            channels = excluded.channels,
            updated_by = excluded.updated_by,
            updated_at = now()
        returning role, event_type, enabled, channels
      `,
      [dto.role, dto.eventType, dto.enabled, dto.channels, actor.userId]
    );
    const row = result.rows[0];
    // Audited: silently redirecting who hears about new leads is exactly the
    // kind of change someone will later need to explain.
    await this.audit.record({
      actor,
      action: 'notifications.preference_updated',
      entityType: 'notification_preference',
      metadata: {
        role: dto.role,
        eventType: dto.eventType,
        enabled: dto.enabled,
        channels: dto.channels
      }
    });
    return {
      role: row.role,
      eventType: row.event_type,
      enabled: row.enabled,
      channels: row.channels ?? []
    };
  }

  // Notify staff about a freshly created lead (site webhook, CRM form or chat
  // auto-lead). Never called with an actor: the trigger is the lead itself.
  async notifyNewLead(input: {
    leadId: string;
    name: string;
    source: string;
  }): Promise<void> {
    const roleChannels = await this.loadRoleChannels('new_lead');
    const roles = [...roleChannels.keys()];
    if (roles.length === 0) return; // every role opted out — a valid setting
    // Text comparison instead of ::app.user_role — see processTaskReminderKind.
    const users = await this.database.query<{ id: string; role: string }>(
      `
        select id, role::text as role from app.users
        where role::text = any($1::text[]) and deleted_at is null
        order by created_at desc
        limit 10000
      `,
      [roles]
    );
    if (users.rows.length === 0) return;
    // A lead has no assignee yet, so there is no always-notify fallback here.
    const groups = this.groupRecipientsByChannels(
      users.rows,
      null,
      roleChannels,
      []
    );
    for (const group of groups.values()) {
      await this.createNotification({
        type: 'new_lead',
        title: 'Новая заявка',
        body: `${input.name} — источник: ${input.source}`,
        data: { entityType: 'lead', entityId: input.leadId },
        userIds: group.userIds,
        channels: group.channels
      });
    }
    this.schedulePushDispatch();
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
    const result = await this.database.transaction(async (client) => {
      // A physical installation may log out and then log in as another demo
      // role. Serialize ownership transfer by token hash, disable the previous
      // owner, then enable/upsert only the current actor. Migration 0072 adds a
      // partial unique index as the final race-proof invariant.
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
        [tokenHash]
      );
      await client.query(
        `
          update app.notification_devices
          set enabled = false, updated_at = now()
          where token_hash = $1
            and user_id <> $2
            and enabled = true
        `,
        [tokenHash, actor.userId]
      );
      return client.query<DeviceRow>(
        `
          insert into app.notification_devices (
            user_id, platform, token_hash, encrypted_token, enabled, last_seen_at
          )
          values ($1, $2, $3, $4, true, now())
          on conflict (user_id, token_hash) do update
          set platform = excluded.platform,
              encrypted_token = excluded.encrypted_token,
              enabled = true,
              last_seen_at = now(),
              updated_at = now()
          returning id, user_id, platform, token_hash, enabled, last_seen_at, created_at, updated_at
        `,
        [actor.userId, dto.platform, tokenHash, encryptedToken]
      );
    });
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
