import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationDeliveryModule } from '../notifications/notification-delivery.module';
import { AuthAccountService } from './auth-account.service';
import { AuthController } from './auth.controller';
import { AuthEmailChallengeService } from './auth-email-challenge.service';
import { AuthLoginService } from './auth-login.service';
import { AuthPasswordRecoveryService } from './auth-password-recovery.service';
import { AuthRateLimitService } from './auth-rate-limit.service';
import { AuthRegistrationService } from './auth-registration.service';
import { AuthService } from './auth.service';
import { AuthVerificationService } from './auth-verification.service';
import { PasswordService } from './password.service';
import { SessionService } from './session.service';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({}), NotificationDeliveryModule],
  controllers: [AuthController],
  providers: [
    AuthRateLimitService,
    AuthEmailChallengeService,
    AuthRegistrationService,
    AuthLoginService,
    AuthVerificationService,
    AuthPasswordRecoveryService,
    AuthAccountService,
    AuthService,
    PasswordService,
    SessionService,
    JwtAuthGuard
  ],
  exports: [AuthService, PasswordService, SessionService]
})
export class AuthModule {}
