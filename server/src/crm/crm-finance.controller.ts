import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { CreatePaymentDto } from "./dto/create-payment.dto";
import { ExpenseQuery } from "./dto/expense.query";
import { UpsertExpenseDto } from "./dto/upsert-expense.dto";
import { UpdateExpenseDto } from "./dto/update-expense.dto";
import { UpsertSubscriptionPackageDto } from "./dto/upsert-subscription-package.dto";
import { UpdateSubscriptionPackageDto } from "./dto/update-subscription-package.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { PaymentQuery } from "./dto/payment.query";
import {
  SubscriptionPackageListQuery,
  SubscriptionPackageVersionQuery,
} from "./dto/subscription-package.query";
import { PackageCatalogService } from "./commerce/package-catalog.service";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmFinanceController {
  constructor(
    private readonly finance: FinanceService,
    private readonly subscriptions: SubscriptionsService,
    private readonly packageCatalog: PackageCatalogService,
  ) {}

  @Get("payments")
  listPayments(
    @CurrentActor() actor: ActorContext,
    @Query() query: PaymentQuery,
  ) {
    return this.finance.listPayments(actor, query);
  }

  @Get("expected-payments")
  listExpectedPayments(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.finance.listExpectedPayments(actor, query);
  }

  @Get("subscriptions")
  listSubscriptions(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.subscriptions.listSubscriptions(actor, query);
  }

  @Post("payments")
  createPayment(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreatePaymentDto,
  ) {
    return this.finance.createPayment(actor, dto);
  }

  @Get("expenses")
  listExpenses(
    @CurrentActor() actor: ActorContext,
    @Query() query: ExpenseQuery,
  ) {
    return this.finance.listExpenses(actor, query);
  }

  @Post("expenses")
  createExpense(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertExpenseDto,
  ) {
    return this.finance.createExpense(actor, dto);
  }

  @Patch("expenses/:id")
  updateExpense(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateExpenseDto,
  ) {
    return this.finance.updateExpense(actor, id, dto);
  }

  @Delete("expenses/:id")
  deleteExpense(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.finance.deleteExpense(actor, id);
  }

  @Get("subscription-packages")
  listSubscriptionPackages(
    @CurrentActor() actor: ActorContext,
    @Query() query: SubscriptionPackageListQuery,
  ) {
    return this.packageCatalog.list(actor, query);
  }

  @Post("subscription-packages")
  createSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpsertSubscriptionPackageDto,
  ) {
    return this.packageCatalog.create(actor, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Patch("subscription-packages/:id")
  updateSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Body() dto: UpdateSubscriptionPackageDto,
  ) {
    return this.packageCatalog.update(actor, id, dto, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Delete("subscription-packages/:id")
  archiveSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Query() query: SubscriptionPackageVersionQuery,
  ) {
    return this.packageCatalog.archive(actor, id, query.expectedVersion, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }

  @Post("subscription-packages/:id/restore")
  restoreSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Headers("idempotency-key") idempotencyKey: string | undefined,
    @Headers("x-request-id") requestId: string | undefined,
    @Query() query: SubscriptionPackageVersionQuery,
  ) {
    return this.packageCatalog.restore(actor, id, query.expectedVersion, {
      idempotencyKey: idempotencyKey ?? "",
      requestId: requestId ?? "",
    });
  }
}
