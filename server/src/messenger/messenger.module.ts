import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { CrmModule } from '../crm/crm.module';
import { DatabaseModule } from '../db/database.module';
import { ChannelsService } from './channels.service';
import { MessengerController } from './messenger.controller';
import { MessengerPolicy } from './messenger.policy';
import { MessengerService } from './messenger.service';
import { RealtimeGateway } from './realtime.gateway';

@Module({
  imports: [AuditModule, CrmModule, DatabaseModule, JwtModule.register({})],
  controllers: [MessengerController],
  providers: [MessengerService, ChannelsService, MessengerPolicy, RealtimeGateway, JwtAuthGuard],
  exports: [MessengerService, MessengerPolicy, RealtimeGateway]
})
export class MessengerModule {}
