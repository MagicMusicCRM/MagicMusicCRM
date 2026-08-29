import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { NormalizedPurchase } from "./subscription-issue.contracts";
import {
  IssuePackageRow,
  IssuedSubscriptionRow,
  SubscriptionIssueRepository,
} from "./subscription-issue.repository";
import {
  PersistedPurchasePayment,
  SubscriptionPurchasePaymentService,
} from "./subscription-purchase-payment.service";

interface PersistPurchaseInput {
  subscriptionId: string;
  studentId: string;
  payerStudentId: string;
  payerBranchId: string | null;
  fundingMode: "personal_account" | "installment";
  conversionLeadId?: string;
  package: IssuePackageRow;
  normalized: NormalizedPurchase;
  actorUserId: string;
  idempotencyKey: string;
  version: number;
  lifecycleReason: string;
}

export interface PersistedPurchase {
  subscription: IssuedSubscriptionRow;
  payment: PersistedPurchasePayment | null;
}

@Injectable()
export class SubscriptionPurchasePersistenceService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly payment: SubscriptionPurchasePaymentService,
  ) {}

  async persist(
    client: PoolClient,
    input: PersistPurchaseInput,
  ): Promise<PersistedPurchase> {
    const subscription = await this.repository.createIssuedSubscription(client, {
      id: input.subscriptionId,
      studentId: input.studentId,
      payerStudentId: input.payerStudentId,
      fundingMode: input.fundingMode,
      purchaseReason: input.normalized.purchaseReason,
      package: input.package,
      snapshot: input.normalized.snapshot,
      discount: input.normalized.discount.columns,
      finalPriceMinor: input.normalized.finalPriceMinor,
      startsAt: input.normalized.startsAt,
      expiresAt: input.normalized.expiresAt,
      conversionLeadId: input.conversionLeadId,
      version: input.version,
    });
    const payment = await this.payment.persist(client, {
      actorUserId: input.actorUserId,
      idempotencyKey: input.idempotencyKey,
      payerStudentId: input.payerStudentId,
      payerBranchId: input.payerBranchId,
      subscriptionId: subscription.id,
      currencyCode: input.package.currency_code,
      payment: input.normalized.payment,
    });
    await this.repository.createInstallments(client, {
      issuedSubscriptionId: subscription.id,
      currencyCode: input.package.currency_code,
      installments: input.normalized.installments,
    });
    await this.repository.createObligations(client, {
      studentId: input.payerStudentId,
      issuedSubscriptionId: subscription.id,
      currencyCode: input.package.currency_code,
      finalPriceMinor: input.normalized.finalPriceMinor,
      installments: input.normalized.installments,
      singlePurchaseDebit: true,
    });
    await this.repository.createIssueLifecycle(client, {
      issuedSubscriptionId: subscription.id,
      actorUserId: input.actorUserId,
      version: input.version,
      reason: input.lifecycleReason,
    });
    return { subscription, payment };
  }
}
