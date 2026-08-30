import { Module } from '@nestjs/common';
import { DatabaseModule } from '../db/database.module';
import { AuditPresentationService } from './audit-presentation.service';
import { AuditService } from './audit.service';

@Module({
  imports: [DatabaseModule],
  providers: [AuditService, AuditPresentationService],
  exports: [AuditService, AuditPresentationService]
})
export class AuditModule {}
