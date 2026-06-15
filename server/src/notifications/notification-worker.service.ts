import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { DatabaseService } from '../db/database.service';
import { ResendEmailProvider, SmtpFallbackEmailProvider } from './notification-email.provider';
import { FirebasePushProvider } from './notification-push.provider';
import { NotificationTokenCrypto } from './notification-token-crypto.service';
import { ProviderResult } from './notifications.types';

interface OutboxRow {
  id: string;
  user_id: string;
  email: string;
  template: string;
  attempt_count: number | string;
  payload: {
    notificationId?: string;
    title?: string;
    body?: string;
  };
}

interface PushDeliveryRow {
  id: string;
  notification_id: string;
  user_id: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
}

interface DeviceTokenRow {
  id: string;
  encrypted_token: string | null;
}

@Injectable()
export class NotificationWorker implements OnModuleInit, OnModuleDestroy {
  private static readonly emailRetryLimit = 5;
  private emailTimer?: NodeJS.Timeout;

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly resend: ResendEmailProvider,
    private readonly smtpFallback: SmtpFallbackEmailProvider,
    private readonly tokenCrypto: NotificationTokenCrypto,
    private readonly pushProvider: FirebasePushProvider
  ) {}

  onModuleInit(): void {
    this.emailTimer = setInterval(() => {
      void this.dispatchPendingEmails().catch(() => undefined);
    }, 30_000);
    this.emailTimer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.emailTimer) clearInterval(this.emailTimer);
  }

  async dispatchPendingEmails(limit = 20): Promise<{ processed: number; failed: number }> {
    const outbox = await this.database.query<OutboxRow>(
      `
        select eo.id, eo.user_id, u.email, eo.template, eo.payload, eo.attempt_count
        from app.email_outbox eo
        join app.users u on u.id = eo.user_id and u.deleted_at is null
        where eo.status in ('queued', 'failed')
          and eo.next_attempt_at <= now()
          and eo.attempt_count < $2
        order by eo.created_at asc
        limit $1
      `,
      [limit, NotificationWorker.emailRetryLimit]
    );

    let failed = 0;
    for (const item of outbox.rows) {
      try {
        const delivered = await this.dispatchEmail(item);
        if (!delivered) failed += 1;
      } catch (error) {
        failed += 1;
        await this.markOutboxFailure(item, this.errorName(error));
        await this.recordDispatchFailure(item, error);
      }
    }
    return { processed: outbox.rows.length, failed };
  }

  async dispatchPendingPush(limit = 50): Promise<{ processed: number; failed: number }> {
    const deliveries = await this.database.query<PushDeliveryRow>(
      `
        select nd.id, nd.notification_id, nd.user_id, n.title, n.body, n.data
        from app.notification_deliveries nd
        join app.notifications n on n.id = nd.notification_id
        where nd.channel = 'push'
          and nd.status = 'queued'
        order by nd.created_at asc
        limit $1
      `,
      [limit]
    );

    let failed = 0;
    for (const delivery of deliveries.rows) {
      try {
        const delivered = await this.dispatchPush(delivery);
        if (!delivered) failed += 1;
      } catch (error) {
        failed += 1;
        await this.recordPushFailure(delivery, error);
      }
    }
    return { processed: deliveries.rows.length, failed };
  }

  private async dispatchEmail(item: OutboxRow): Promise<boolean> {
    const message = {
      to: item.email,
      subject: item.payload.title ?? 'Magic Music',
      text: item.payload.body ?? '',
      html: this.renderMagicEmailHtml(
        item.payload.title ?? 'Magic Music',
        item.payload.body ?? '',
        item.template,
      )
    };

    const primary = await this.safeSend(() => this.resend.send(message));
    await this.recordDelivery(item, primary);
    if (primary.status === 'sent') {
      await this.markOutboxSent(item.id);
      return true;
    }

    const fallback = await this.safeSend(() => this.smtpFallback.send(message));
    await this.recordDelivery(item, fallback);
    if (fallback.status === 'sent') {
      await this.markOutboxSent(item.id);
      return true;
    }

    const lastError = fallback.error ?? primary.error ?? 'provider_failed';
    await this.markOutboxFailure(item, lastError);
    if (!this.canRetryEmail(item)) {
      await this.audit.record({
        action: 'notifications.email_outbox_failed',
        entityType: 'email_outbox',
        entityId: item.id,
        metadata: {
          template: item.template,
          primaryProvider: primary.provider,
          primaryStatus: primary.status,
          fallbackProvider: fallback.provider,
          fallbackStatus: fallback.status
        }
      });
    }
    return false;
  }

  private renderMagicEmailHtml(
    title: string,
    body: string,
    template: string,
  ): string {
    const code = body.match(/\b\d{6}\b/)?.[0];
    const escapedTitle = this.escapeHtml(title);
    const escapedBody = this.escapeHtml(body);
    const preheader =
      template === 'auth_password_reset'
        ? 'Код для сброса пароля Magic Music'
        : template === 'student_invite'
          ? 'Приглашение в личный кабинет Magic Music'
        : 'Код подтверждения Magic Music';
    const footnote =
      template === 'student_invite'
        ? 'Если вы не ожидали приглашение, просто проигнорируйте письмо.'
        : 'Если вы не запрашивали этот код, просто проигнорируйте письмо.';
    const codeBlock = code
      ? `
        <div style="margin:28px 0 22px;text-align:center;">
          <div style="display:inline-block;letter-spacing:10px;font-size:34px;line-height:1;font-weight:800;color:#1f1d1a;background:#f6efe1;border:1px solid #d8ba72;border-radius:10px;padding:18px 18px 18px 28px;">${code}</div>
        </div>`
      : '';

    return `<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>${escapedTitle}</title>
  </head>
  <body style="margin:0;padding:0;background:#171614;font-family:Arial,Helvetica,sans-serif;color:#f7f1e6;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${this.escapeHtml(preheader)}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#171614;padding:32px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:520px;background:#23211e;border:1px solid #3a3428;border-radius:14px;overflow:hidden;">
            <tr>
              <td style="padding:28px 28px 18px;border-bottom:1px solid #3a3428;">
                <div style="font-size:13px;text-transform:uppercase;letter-spacing:1.8px;color:#c5a059;font-weight:700;">Magic Music CRM</div>
                <h1 style="margin:10px 0 0;font-size:24px;line-height:1.25;color:#ffffff;">${escapedTitle}</h1>
              </td>
            </tr>
            <tr>
              <td style="padding:28px;">
                <p style="margin:0;font-size:16px;line-height:1.55;color:#e7ddcb;">${escapedBody}</p>
                ${codeBlock}
                <p style="margin:24px 0 0;font-size:13px;line-height:1.5;color:#a79b87;">${this.escapeHtml(footnote)}</p>
              </td>
            </tr>
            <tr>
              <td style="padding:18px 28px;background:#1c1a17;color:#8f846f;font-size:12px;line-height:1.5;">
                Это системное письмо Magic Music CRM. Отвечать на него не нужно.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private async safeSend(work: () => Promise<ProviderResult>): Promise<ProviderResult> {
    try {
      return await work();
    } catch {
      return { provider: 'unknown', status: 'failed', error: 'provider_error' };
    }
  }

  private async dispatchPush(delivery: PushDeliveryRow): Promise<boolean> {
    const devices = await this.database.query<DeviceTokenRow>(
      `
        select id, encrypted_token
        from app.notification_devices
        where user_id = $1 and enabled = true
        order by last_seen_at desc
        limit 10
      `,
      [delivery.user_id]
    );

    if (devices.rows.length === 0) {
      await this.markPushDelivery(delivery, 'firebase', 'skipped', 'no_device');
      return true;
    }

    let sent = 0;
    let failed = 0;
    let skipped = 0;
    let lastProvider = 'firebase';
    let lastError = 'not_configured';

    for (const device of devices.rows) {
      const token = this.tokenCrypto.decrypt(device.encrypted_token);
      if (!token) {
        skipped += 1;
        lastError = 'missing_token_encryption_key';
        continue;
      }

      const result = await this.safeSend(() =>
        this.pushProvider.send({
          token,
          title: delivery.title,
          body: delivery.body,
          data: delivery.data
        })
      );
      lastProvider = result.provider;
      lastError = result.error ?? result.status;
      if (result.status === 'sent') sent += 1;
      if (result.status === 'failed') failed += 1;
      if (result.status === 'skipped') skipped += 1;
      await this.audit.record({
        action: 'notifications.push_delivery_attempted',
        entityType: 'notification',
        entityId: delivery.notification_id,
        metadata: { provider: result.provider, status: result.status, deviceId: device.id }
      });
    }

    if (sent > 0) {
      await this.markPushDelivery(delivery, lastProvider, 'sent', null);
      return true;
    }

    const status = failed > 0 ? 'failed' : 'skipped';
    await this.markPushDelivery(delivery, lastProvider, status, skipped > 0 ? lastError : lastError);
    return status !== 'failed';
  }

  private async recordDelivery(item: OutboxRow, result: ProviderResult): Promise<void> {
    if (!item.payload.notificationId) return;
    await this.database.query(
      `
        insert into app.notification_deliveries (
          notification_id, user_id, channel, provider, status, attempt_count, last_error
        )
        values ($1, $2, 'email', $3, $4::app.notification_delivery_status, 1, $5)
      `,
      [item.payload.notificationId, item.user_id, result.provider, result.status, result.error ?? null]
    );
    await this.audit.record({
      action: 'notifications.email_delivery_attempted',
      entityType: 'notification',
      entityId: item.payload.notificationId,
      metadata: { provider: result.provider, status: result.status }
    });
  }

  private async markOutboxSent(id: string): Promise<void> {
    await this.database.query(
      `
        update app.email_outbox
        set status = 'sent',
            attempt_count = attempt_count + 1,
            last_error = null,
            updated_at = now()
        where id = $1
      `,
      [id]
    );
  }

  private async markOutboxFailure(item: OutboxRow, error: string): Promise<void> {
    const nextDelay = this.canRetryEmail(item) ? this.nextEmailRetryDelay(item) : null;
    await this.database.query(
      `
        update app.email_outbox
        set status = 'failed',
            attempt_count = attempt_count + 1,
            last_error = $2,
            next_attempt_at = case
              when $3::text is null then next_attempt_at
              else now() + $3::interval
            end,
            updated_at = now()
        where id = $1
      `,
      [item.id, error, nextDelay]
    );
  }

  private async markPushDelivery(
    delivery: PushDeliveryRow,
    provider: string,
    status: ProviderResult['status'],
    lastError: string | null
  ): Promise<void> {
    await this.database.query(
      `
        update app.notification_deliveries
        set provider = $2,
            status = $3::app.notification_delivery_status,
            attempt_count = attempt_count + 1,
            last_error = $4,
            updated_at = now()
        where id = $1
      `,
      [delivery.id, provider, status, lastError]
    );
  }

  private async recordDispatchFailure(item: OutboxRow, error: unknown): Promise<void> {
    try {
      await this.audit.record({
        action: 'notifications.email_dispatch_failed',
        entityType: 'email_outbox',
        entityId: item.id,
        metadata: { template: item.template, error: this.errorName(error) }
      });
    } catch {
      // Keep the batch moving even if audit persistence is unavailable.
    }
  }

  private async recordPushFailure(delivery: PushDeliveryRow, error: unknown): Promise<void> {
    try {
      await this.markPushDelivery(delivery, 'firebase', 'failed', this.errorName(error));
      await this.audit.record({
        action: 'notifications.push_dispatch_failed',
        entityType: 'notification',
        entityId: delivery.notification_id,
        metadata: { error: this.errorName(error) }
      });
    } catch {
      // Keep the batch moving even if audit or status persistence is unavailable.
    }
  }

  private errorName(error: unknown): string {
    return error instanceof Error && error.name ? error.name.slice(0, 80) : 'dispatch_failed';
  }

  private canRetryEmail(item: OutboxRow): boolean {
    return this.emailAttemptCount(item) + 1 < NotificationWorker.emailRetryLimit;
  }

  private nextEmailRetryDelay(item: OutboxRow): string {
    const attempt = this.emailAttemptCount(item) + 1;
    const minutes = Math.min(30, Math.max(1, 2 ** (attempt - 1)));
    return `${minutes} minutes`;
  }

  private emailAttemptCount(item: OutboxRow): number {
    const value = Number(item.attempt_count);
    return Number.isFinite(value) && value > 0 ? value : 0;
  }
}
