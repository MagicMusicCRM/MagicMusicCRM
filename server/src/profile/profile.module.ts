import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { RolesGuard } from '../common/security/roles.guard';
import { DatabaseModule } from '../db/database.module';
import { CrmModule } from '../crm/crm.module';
import { AdminProfilesController, ProfileController } from './profile.controller';
import { MyProfileService } from './my-profile.service';
import { ProfileDirectoryService } from './profile-directory.service';
import { ProfileLinkingService } from './profile-linking.service';
import { ProfileNotesService } from './profile-notes.service';
import { ProfilePolicy } from './profile.policy';
import { ProfileRecordRepository } from './profile-record.repository';
import { ProfileService } from './profile.service';

@Module({
  imports: [AuditModule, CrmModule, DatabaseModule, JwtModule.register({})],
  controllers: [ProfileController, AdminProfilesController],
  providers: [
    ProfileService,
    ProfileRecordRepository,
    MyProfileService,
    ProfileDirectoryService,
    ProfileNotesService,
    ProfileLinkingService,
    ProfilePolicy,
    JwtAuthGuard,
    RolesGuard
  ],
  exports: [ProfileService]
})
export class ProfileModule {}
