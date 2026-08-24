import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { DatabaseModule } from '../db/database.module';
import { ResendEmailProvider, SmtpFallbackEmailProvider } from './notification-email.provider';
import { FirebasePushProvider } from './notification-push.provider';
import { NotificationTokenCrypto } from './notification-token-crypto.service';
import { NotificationWorker } from './notification-worker.service';
import { NotificationsPolicy } from './notifications.policy';
import { NotificationsService } from './notifications.service';

@Module({
  imports: [AuditModule, DatabaseModule],
  providers: [
    NotificationsService,
    NotificationsPolicy,
    NotificationWorker,
    NotificationTokenCrypto,
    FirebasePushProvider,
    ResendEmailProvider,
    SmtpFallbackEmailProvider,
  ],
  exports: [NotificationsService, NotificationWorker],
})
export class NotificationDeliveryModule {}
