import 'reflect-metadata';
import { CanActivate, INestApplication, UnauthorizedException, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { OpenAPIObject } from '@nestjs/swagger';
import { taggedDocument } from './tagged-document';
import { CrmFinanceController } from '../../src/crm/crm-finance.controller';
import { FinanceService } from '../../src/crm/finance.service';
import { SubscriptionsService } from '../../src/crm/subscriptions.service';
import { PackageCatalogService } from '../../src/crm/commerce/package-catalog.service';
import { JwtAuthGuard } from '../../src/common/security/jwt-auth.guard';
import { SafeExceptionFilter } from '../../src/common/filters/safe-exception.filter';
import { SafeLogger } from '../../src/common/logging/safe-logger.service';
import { RequestIdMiddleware } from '../../src/common/middleware/request-id.middleware';

// Only used by offline export and tests. AppModule, workers, DB and env loading
// are deliberately absent; no documentation endpoint is installed at runtime.
export async function createExpenseContractApp(
  finance: unknown = {},
  guard: CanActivate = { canActivate: () => { throw new UnauthorizedException(); } },
): Promise<INestApplication> {
  const module = await Test.createTestingModule({
    controllers: [CrmFinanceController],
    providers: [
      { provide: FinanceService, useValue: finance },
      { provide: SubscriptionsService, useValue: {} },
      { provide: PackageCatalogService, useValue: {} },
    ],
  }).overrideGuard(JwtAuthGuard).useValue(guard).compile();
  const app = module.createNestApplication({ logger: false });
  app.setGlobalPrefix('api');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  app.useGlobalFilters(new SafeExceptionFilter({ warn() {}, error() {} } as unknown as SafeLogger));
  const requestId = new RequestIdMiddleware();
  app.use(requestId.use.bind(requestId));
  await app.init();
  return app;
}

export function expenseDocument(app: INestApplication): OpenAPIObject {
  return taggedDocument(app, { title: 'MagicMusicCRM expense API',
    description: 'Expense contract only. Other CRM domains are not covered by this document.',
    tag: 'expenses', closedSchemas: ['UpsertExpenseDto', 'UpdateExpenseDto'] });
}
