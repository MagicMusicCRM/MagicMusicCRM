import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { RolesGuard } from '../common/security/roles.guard';
import { DatabaseModule } from '../db/database.module';
import {
  AdminDeletionRequestsController,
  LegalController,
  ProfileDeletionController
} from './legal.controller';
import { LegalPolicy } from './legal.policy';
import { LegalService } from './legal.service';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({})],
  controllers: [LegalController, ProfileDeletionController, AdminDeletionRequestsController],
  providers: [LegalService, LegalPolicy, JwtAuthGuard, RolesGuard],
  exports: [LegalService]
})
export class LegalModule {}
