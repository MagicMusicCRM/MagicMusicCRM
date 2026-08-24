import { Module } from '@nestjs/common';
import { DatabaseModule } from '../db/database.module';
import { MessengerPolicy } from './messenger.policy';

@Module({
  imports: [DatabaseModule],
  providers: [MessengerPolicy],
  exports: [MessengerPolicy]
})
export class MessengerPolicyModule {}
