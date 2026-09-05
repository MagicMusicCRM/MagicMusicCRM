import 'reflect-metadata';
import { CanActivate, INestApplication, UnauthorizedException, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { SubscriptionCommerceController } from '../../src/crm/subscription-commerce.controller';
import { PaymentLifecycleService } from '../../src/crm/commerce/payment-lifecycle.service';
import { ActualPaymentService } from '../../src/crm/commerce/actual-payment.service';
import { SubscriptionIssueService } from '../../src/crm/commerce/subscription-issue.service';
import { SubscriptionLifecycleService } from '../../src/crm/commerce/subscription-lifecycle.service';
import { PaymentReversalService } from '../../src/crm/commerce/payment-reversal.service';
import { PaymentCorrectionService } from '../../src/crm/commerce/payment-correction.service';
import { JwtAuthGuard } from '../../src/common/security/jwt-auth.guard';
import { SafeExceptionFilter } from '../../src/common/filters/safe-exception.filter';
import { SafeLogger } from '../../src/common/logging/safe-logger.service';
import { RequestIdMiddleware } from '../../src/common/middleware/request-id.middleware';
import { taggedDocument } from './tagged-document';

export async function createPaymentContractApp(
  service: unknown = {},
  guard: CanActivate = { canActivate: () => { throw new UnauthorizedException(); } },
  adjustments: { reversal?: PaymentReversalService; correction?: PaymentCorrectionService } = {},
): Promise<INestApplication> {
  const module = await Test.createTestingModule({
    controllers: [SubscriptionCommerceController],
    providers: [
      { provide: PaymentLifecycleService, useValue: service },
      ...[ActualPaymentService, SubscriptionIssueService, SubscriptionLifecycleService].map(provide => ({ provide, useValue: {} })),
      { provide: PaymentReversalService, useValue: adjustments.reversal ?? {} },
      { provide: PaymentCorrectionService, useValue: adjustments.correction ?? {} },
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

export function paymentDocument(app: INestApplication) {
  return taggedDocument(app, { title: 'MagicMusicCRM payment record commands',
    description: 'Create, transition, correct and reverse payment records. Subscription and account adjustment commands are not covered.',
    tag: 'payment-records', closedSchemas: ['CreatePaymentRecordDto', 'TransitionPaymentRecordDto',
      'PreviewPaymentCorrectionDto', 'CorrectPaymentDto', 'PreviewPaymentReversalDto', 'ReversePaymentDto'] });
}
