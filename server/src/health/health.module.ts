import { Module } from '@nestjs/common';
import { CrmModule } from '../crm/crm.module';
import { DatabaseModule } from '../db/database.module';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';

@Module({
  imports: [DatabaseModule, CrmModule],
  controllers: [HealthController],
  providers: [HealthService]
})
export class HealthModule {}
