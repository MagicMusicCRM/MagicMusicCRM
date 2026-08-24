import { Global, Module } from "@nestjs/common";
import { DatabaseModule } from "../db/database.module";
import { NotificationDeliveryModule } from "../notifications/notification-delivery.module";
import { PlatformIntegrityRepository } from "./platform-integrity.repository";
import { PlatformIntegrityService } from "./platform-integrity.service";
import { PlatformOutboxWorker } from "./platform-outbox.worker";
import { V4DomainFlagsService } from "./rollout/v4/domain-flags";

@Global()
@Module({
  imports: [DatabaseModule, NotificationDeliveryModule],
  providers: [
    PlatformIntegrityRepository,
    PlatformIntegrityService,
    PlatformOutboxWorker,
    V4DomainFlagsService,
  ],
  exports: [
    PlatformIntegrityRepository,
    PlatformIntegrityService,
    PlatformOutboxWorker,
    V4DomainFlagsService,
  ],
})
export class PlatformModule {}
