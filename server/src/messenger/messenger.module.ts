import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { MessengerController } from './messenger.controller';
import { MessengerPolicy } from './messenger.policy';
import { MessengerService } from './messenger.service';
import { RealtimeGateway } from './realtime.gateway';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({})],
  controllers: [MessengerController],
  providers: [MessengerService, MessengerPolicy, RealtimeGateway, JwtAuthGuard],
  exports: [MessengerService, MessengerPolicy, RealtimeGateway]
})
export class MessengerModule {}
