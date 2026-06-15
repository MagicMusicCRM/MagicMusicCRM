import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AuditModule } from "../audit/audit.module";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { RolesGuard } from "../common/security/roles.guard";
import { DatabaseModule } from "../db/database.module";
import {
  AdminSettingsController,
  SettingsController,
} from "./settings.controller";
import { SettingsService } from "./settings.service";

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({})],
  controllers: [SettingsController, AdminSettingsController],
  providers: [SettingsService, JwtAuthGuard, RolesGuard],
  exports: [SettingsService],
})
export class SettingsModule {}
