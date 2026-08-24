import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { RolesGuard } from '../common/security/roles.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationDeliveryModule } from './notification-delivery.module';
import {
  AdminNotificationsController,
  NotificationsController
} from './notifications.controller';

@Module({
  imports: [NotificationDeliveryModule, DatabaseModule, JwtModule.register({})],
  controllers: [NotificationsController, AdminNotificationsController],
  providers: [JwtAuthGuard, RolesGuard],
  exports: [NotificationDeliveryModule]
})
export class NotificationsModule {}
