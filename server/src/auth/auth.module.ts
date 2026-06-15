import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { googleOAuthClientProvider } from './google-oauth.provider';
import { GoogleOAuthService } from './google-oauth.service';
import { PasswordService } from './password.service';
import { SessionService } from './session.service';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({}), NotificationsModule],
  controllers: [AuthController],
  providers: [
    AuthService,
    PasswordService,
    SessionService,
    JwtAuthGuard,
    GoogleOAuthService,
    googleOAuthClientProvider
  ],
  exports: [AuthService, PasswordService, SessionService, GoogleOAuthService]
})
export class AuthModule {}
