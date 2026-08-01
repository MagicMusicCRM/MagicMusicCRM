import { Module } from "@nestjs/common";
import { DatabaseModule } from "../db/database.module";
import { PlatformIntegrityRepository } from "./platform-integrity.repository";
import { PlatformIntegrityService } from "./platform-integrity.service";
import { V4DomainFlagsService } from "./v4-domain-flags";

@Module({
  imports: [DatabaseModule],
  providers: [
    PlatformIntegrityRepository,
    PlatformIntegrityService,
    V4DomainFlagsService,
  ],
  exports: [
    PlatformIntegrityRepository,
    PlatformIntegrityService,
    V4DomainFlagsService,
  ],
})
export class PlatformModule {}
