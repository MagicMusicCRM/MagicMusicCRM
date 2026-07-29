import { Module } from "@nestjs/common";
import { DatabaseModule } from "../db/database.module";
import { PlatformIntegrityRepository } from "./platform-integrity.repository";
import { PlatformIntegrityService } from "./platform-integrity.service";

@Module({
  imports: [DatabaseModule],
  providers: [PlatformIntegrityRepository, PlatformIntegrityService],
  exports: [PlatformIntegrityRepository, PlatformIntegrityService],
})
export class PlatformModule {}
