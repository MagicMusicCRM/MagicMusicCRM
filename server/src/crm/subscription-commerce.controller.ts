import {
  Body,
  Controller,
  Headers,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { ActualPaymentService } from "./commerce/actual-payment.service";
import { PaymentLifecycleService } from "./commerce/payment-lifecycle.service";
import { PaymentReversalService } from "./commerce/payment-reversal.service";
import { SubscriptionLifecycleService } from "./commerce/subscription-lifecycle.service";
import { SubscriptionIssueService } from "./commerce/subscription-issue.service";
import {
  IssueSubscriptionDto,
  PurchaseSubscriptionCommandDto,
  PurchaseSubscriptionPreviewDto,
} from "./dto/issue-subscription.dto";
import { RecordActualPaymentDto } from "./dto/record-actual-payment.dto";
import {
  CreatePaymentRecordDto,
  PreviewPaymentReversalDto,
  ReversePaymentDto,
  TransitionPaymentRecordDto,
} from "./dto/payment-lifecycle.dto";
import {
  SubscriptionCancelCommandDto,
  SubscriptionCancelPreviewDto,
} from "./dto/subscription-cancel.dto";
import {
  SubscriptionReplaceCommandDto,
  SubscriptionReplacePreviewDto,
} from "./dto/subscription-replace.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm/students")
export class SubscriptionCommerceController {
  constructor(
    private readonly issueService: SubscriptionIssueService,
    private readonly paymentService: ActualPaymentService,
    private readonly lifecycleService: SubscriptionLifecycleService,
    private readonly paymentLifecycle: PaymentLifecycleService,
    private readonly paymentReversal: PaymentReversalService,
  ) {}

  @Post(":studentId/subscriptions/issue")
  issueSubscription(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: IssueSubscriptionDto,
  ) {
    return this.issueService.issue(actor, studentId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post(":studentId/payment-records/:paymentRecordId/reversal/preview")
  previewPaymentReversal(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Param("paymentRecordId", ParseUUIDPipe) paymentRecordId: string,
    @Body() dto: PreviewPaymentReversalDto,
  ) {
    return this.paymentReversal.preview(
      actor,
      studentId,
      paymentRecordId,
      dto,
    );
  }

  @Post(":studentId/payment-records/:paymentRecordId/reversal")
  reversePayment(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Param("paymentRecordId", ParseUUIDPipe) paymentRecordId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: ReversePaymentDto,
  ) {
    return this.paymentReversal.reverse(
      actor,
      studentId,
      paymentRecordId,
      dto,
      {
        idempotencyKey: idempotencyKey ?? "",
        requestId: requestId ?? "",
      },
    );
  }

  @Post(":studentId/payment-records")
  createPaymentRecord(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: CreatePaymentRecordDto,
  ) {
    return this.paymentLifecycle.create(actor, studentId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post(":studentId/payment-records/:paymentRecordId/transition")
  transitionPaymentRecord(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Param("paymentRecordId", ParseUUIDPipe) paymentRecordId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: TransitionPaymentRecordDto,
  ) {
    return this.paymentLifecycle.transition(
      actor,
      studentId,
      paymentRecordId,
      dto,
      {
        idempotencyKey: idempotencyKey ?? "",
        requestId: requestId ?? "",
      },
    );
  }

  @Post(":studentId/subscriptions/purchase/preview")
  previewSubscriptionPurchase(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Body() dto: PurchaseSubscriptionPreviewDto,
  ) {
    return this.issueService.previewPurchase(actor, studentId, dto);
  }

  @Post(":studentId/subscriptions/purchase")
  purchaseSubscription(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: PurchaseSubscriptionCommandDto,
  ) {
    return this.issueService.purchase(actor, studentId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post(":studentId/subscription-payments")
  recordActualPayment(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: RecordActualPaymentDto,
  ) {
    return this.paymentService.record(actor, studentId, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post(":studentId/subscriptions/:issuedSubscriptionId/replace/preview")
  previewSubscriptionReplacement(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Param("issuedSubscriptionId", ParseUUIDPipe)
    issuedSubscriptionId: string,
    @Body() dto: SubscriptionReplacePreviewDto,
  ) {
    return this.lifecycleService.previewReplacement(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
    );
  }

  @Post(":studentId/subscriptions/:issuedSubscriptionId/replace")
  replaceSubscription(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Param("issuedSubscriptionId", ParseUUIDPipe)
    issuedSubscriptionId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: SubscriptionReplaceCommandDto,
  ) {
    return this.lifecycleService.replace(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
      {
        idempotencyKey: idempotencyKey ?? "",
        requestId: requestId ?? "",
      },
    );
  }

  @Post(":studentId/subscriptions/:issuedSubscriptionId/cancel/preview")
  previewSubscriptionCancellation(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Param("issuedSubscriptionId", ParseUUIDPipe)
    issuedSubscriptionId: string,
    @Body() _dto: SubscriptionCancelPreviewDto,
  ) {
    return this.lifecycleService.previewCancellation(
      actor,
      studentId,
      issuedSubscriptionId,
    );
  }

  @Post(":studentId/subscriptions/:issuedSubscriptionId/cancel")
  cancelSubscription(
    @CurrentActor() actor: ActorContext,
    @Param("studentId", ParseUUIDPipe) studentId: string,
    @Param("issuedSubscriptionId", ParseUUIDPipe)
    issuedSubscriptionId: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: SubscriptionCancelCommandDto,
  ) {
    return this.lifecycleService.cancel(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
      {
        idempotencyKey: idempotencyKey ?? "",
        requestId: requestId ?? "",
      },
    );
  }
}
