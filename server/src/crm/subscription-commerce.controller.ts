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
import { SubscriptionLifecycleService } from "./commerce/subscription-lifecycle.service";
import { SubscriptionIssueService } from "./commerce/subscription-issue.service";
import { IssueSubscriptionDto } from "./dto/issue-subscription.dto";
import { RecordActualPaymentDto } from "./dto/record-actual-payment.dto";
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
}
