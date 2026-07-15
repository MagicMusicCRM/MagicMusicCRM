import {
  Body,
  Controller,
  Delete,
  Get,
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

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmFinanceController {
  constructor(
    private readonly finance: FinanceService,
    private readonly subscriptions: SubscriptionsService,
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
    @Query() query: CrmListQuery,
  ) {
    return this.subscriptions.listSubscriptionPackages(actor, query);
  }

  @Post("subscription-packages")
  createSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpsertSubscriptionPackageDto,
  ) {
    return this.subscriptions.createSubscriptionPackage(actor, dto);
  }

  @Patch("subscription-packages/:id")
  updateSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateSubscriptionPackageDto,
  ) {
    return this.subscriptions.updateSubscriptionPackage(actor, id, dto);
  }

  @Delete("subscription-packages/:id")
  deleteSubscriptionPackage(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.subscriptions.deleteSubscriptionPackage(actor, id);
  }
}
