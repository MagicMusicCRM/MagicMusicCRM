import { Global, Module } from '@nestjs/common';
import { RealtimeBus } from './realtime-bus';

/**
 * Global so any feature module can inject [RealtimeBus] without creating an
 * import cycle with MessengerModule (which owns the gateway and depends on
 * CrmModule).
 */
@Global()
@Module({
  providers: [RealtimeBus],
  exports: [RealtimeBus]
})
export class RealtimeModule {}
