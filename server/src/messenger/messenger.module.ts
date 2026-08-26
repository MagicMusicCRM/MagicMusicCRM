import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { CrmModule } from '../crm/crm.module';
import { DatabaseModule } from '../db/database.module';
import { ChannelsService } from './channels.service';
import { ChatInboxService } from './chat-inbox.service';
import { ChatsController } from './chats.controller';
import { MessageService } from './message.service';
import { MessengerPolicyModule } from './messenger-policy.module';
import { MessengerFanoutService } from './messenger-fanout.service';
import { ReadReceiptService } from './read-receipt.service';
import { MessengerController } from './messenger.controller';
import { MessengerChatAccessService } from './messenger-chat-access.service';
import { MessengerSystemChatService } from './messenger-system-chat.service';
import { MessengerChatQueryService } from './messenger-chat-query.service';
import { MessengerChatCommandService } from './messenger-chat-command.service';
import { MessengerMessageDeliveryService } from './messenger-message-delivery.service';
import { MessengerService } from './messenger.service';
import { RealtimeGateway } from './realtime.gateway';

@Module({
  imports: [
    AuditModule,
    CrmModule,
    DatabaseModule,
    JwtModule.register({}),
    MessengerPolicyModule
  ],
  controllers: [ChatsController, MessengerController],
  providers: [
    MessengerChatAccessService,
    MessengerSystemChatService,
    MessengerChatQueryService,
    MessengerChatCommandService,
    MessengerMessageDeliveryService,
    MessengerService,
    ChannelsService,
    ChatInboxService,
    MessageService,
    MessengerFanoutService,
    ReadReceiptService,
    RealtimeGateway,
    JwtAuthGuard
  ],
  exports: [MessengerService, MessengerPolicyModule, RealtimeGateway]
})
export class MessengerModule {}
