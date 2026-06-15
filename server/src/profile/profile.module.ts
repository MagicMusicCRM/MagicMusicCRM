import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { RolesGuard } from '../common/security/roles.guard';
import { DatabaseModule } from '../db/database.module';
import { AdminProfilesController, ProfileController } from './profile.controller';
import { ProfilePolicy } from './profile.policy';
import { ProfileService } from './profile.service';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({})],
  controllers: [ProfileController, AdminProfilesController],
  providers: [ProfileService, ProfilePolicy, JwtAuthGuard, RolesGuard],
  exports: [ProfileService]
})
export class ProfileModule {}
