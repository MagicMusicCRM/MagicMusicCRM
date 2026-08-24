import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuditModule } from '../audit/audit.module';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { DatabaseModule } from '../db/database.module';
import { MessengerPolicyModule } from '../messenger/messenger-policy.module';
import { FileValidator } from './file-validator.service';
import { FilesController } from './files.controller';
import { FilesPolicy } from './files.policy';
import { FilesService } from './files.service';
import { LocalStorageDriver } from './local-storage.driver';

@Module({
  imports: [
    AuditModule,
    DatabaseModule,
    JwtModule.register({}),
    MessengerPolicyModule
  ],
  controllers: [FilesController],
  providers: [FilesService, FilesPolicy, FileValidator, LocalStorageDriver, JwtAuthGuard],
  exports: [FilesService, FilesPolicy]
})
export class FilesModule {}
