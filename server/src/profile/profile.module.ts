import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { RolesGuard } from '../common/security/roles.guard';
import { DatabaseModule } from '../db/database.module';
import { CrmModule } from '../crm/crm.module';
import { AdminProfilesController, ProfileController } from './profile.controller';
import { ProfileLinkingService } from './profile-linking.service';
import { ProfilePolicy } from './profile.policy';
import { ProfileService } from './profile.service';

@Module({
  imports: [AuditModule, CrmModule, DatabaseModule, JwtModule.register({})],
  controllers: [ProfileController, AdminProfilesController],
  providers: [ProfileService, ProfileLinkingService, ProfilePolicy, JwtAuthGuard, RolesGuard],
  exports: [ProfileService]
})
export class ProfileModule {}
