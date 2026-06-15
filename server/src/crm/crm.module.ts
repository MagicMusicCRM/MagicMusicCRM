import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { CrmController } from './crm.controller';
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { CrmPolicy } from './crm.policy';
import { CrmService } from './crm.service';

@Module({
  imports: [AuditModule, DatabaseModule, JwtModule.register({}), NotificationsModule],
  controllers: [CrmController],
  providers: [CrmService, CrmPolicy, HolliHopMetadataService, JwtAuthGuard],
  exports: [CrmService]
})
export class CrmModule {}
