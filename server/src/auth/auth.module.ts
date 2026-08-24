import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationDeliveryModule } from '../notifications/notification-delivery.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { PasswordService } from './password.service';
import { SessionService } from './session.service';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({}), NotificationDeliveryModule],
  controllers: [AuthController],
  providers: [AuthService, PasswordService, SessionService, JwtAuthGuard],
  exports: [AuthService, PasswordService, SessionService]
})
export class AuthModule {}
