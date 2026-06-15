import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { RolesGuard } from '../common/security/roles.guard';
import { DatabaseModule } from '../db/database.module';
import { ResendEmailProvider, SmtpFallbackEmailProvider } from './notification-email.provider';
import { FirebasePushProvider } from './notification-push.provider';
import { NotificationTokenCrypto } from './notification-token-crypto.service';
import { NotificationWorker } from './notification-worker.service';
import {
  AdminNotificationsController,
  NotificationsController
} from './notifications.controller';
import { NotificationsPolicy } from './notifications.policy';
import { NotificationsService } from './notifications.service';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({})],
  controllers: [NotificationsController, AdminNotificationsController],
  providers: [
    NotificationsService,
    NotificationsPolicy,
    NotificationWorker,
    NotificationTokenCrypto,
    FirebasePushProvider,
    ResendEmailProvider,
    SmtpFallbackEmailProvider,
    JwtAuthGuard,
    RolesGuard
  ],
  exports: [NotificationsService, NotificationWorker]
})
export class NotificationsModule {}
