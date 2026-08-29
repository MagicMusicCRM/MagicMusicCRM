import { Injectable } from "@nestjs/common";
import { createHash } from "crypto";
import { PoolClient } from "pg";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { PaymentLifecycleRepository } from "./payment-lifecycle.repository";
import { NormalizedPurchase } from "./subscription-issue.contracts";
import {
  ActualPaymentRow,
  SubscriptionIssueRepository,
} from "./subscription-issue.repository";

interface PersistPurchasePaymentInput {
  actorUserId: string;
  idempotencyKey: string;
  payerStudentId: string;
  payerBranchId: string | null;
  subscriptionId: string;
  currencyCode: string;
  payment: NormalizedPurchase["payment"];
}

export interface PersistedPurchasePayment {
  actualPaymentId: string;
  paymentRecordId: string;
  actualPayment: ActualPaymentRow;
}

@Injectable()
export class SubscriptionPurchasePaymentService {
  constructor(
    private readonly issueRepository: SubscriptionIssueRepository,
    private readonly paymentLifecycle: PaymentLifecycleRepository,
  ) {}

  async persist(
    client: PoolClient,
    input: PersistPurchasePaymentInput,
  ): Promise<PersistedPurchasePayment | null> {
    if (input.payment.amountMinor === "0") return null;
    const actualPaymentId = this.deterministicId(
      input.actorUserId,
      "crm.subscription.purchase.actual-payment",
      input.idempotencyKey,
    );
    const paymentRecordId = this.deterministicId(
      input.actorUserId,
      "crm.subscription.purchase.payment-record",
      input.idempotencyKey,
    );
    const actualPayment = await this.issueRepository.createActualPayment(client, {
      id: actualPaymentId,
      studentId: input.payerStudentId,
      issuedSubscriptionId: input.subscriptionId,
      amountMinor: input.payment.amountMinor,
      currencyCode: input.currencyCode,
      method: input.payment.method,
      occurredAt: input.payment.occurredAt!,
      actorUserId: input.actorUserId,
      branchId: input.payerBranchId,
      comment: input.payment.comment,
      invoiceIdentifier: null,
      idempotencyRef: `${input.actorUserId}:${input.idempotencyKey}:subscription-sale`,
      requestFingerprint: fingerprintPayload({
        subscriptionId: input.subscriptionId,
        payerStudentId: input.payerStudentId,
        amountMinor: input.payment.amountMinor,
        method: input.payment.method,
        occurredAt: input.payment.occurredAt!.toISOString(),
        comment: input.payment.comment,
      }),
    });
    const paymentRecord = await this.paymentLifecycle.createRecord(client, {
      id: paymentRecordId,
      studentId: input.payerStudentId,
      issuedSubscriptionId: input.subscriptionId,
      installmentId: null,
      amountMinor: input.payment.amountMinor,
      currencyCode: input.currencyCode,
      status: "paid",
      dueAt: null,
      method: input.payment.method,
      externalIdentifier: `subscription-sale:${input.subscriptionId}`,
      verificationNote: input.payment.comment,
      actualPaymentId,
      version: 1,
      createdBy: input.actorUserId,
      verifiedBy: input.actorUserId,
      verifiedAt: input.payment.occurredAt,
    });
    await this.paymentLifecycle.linkActualPayment(
      client,
      actualPaymentId,
      paymentRecord.id,
    );
    await this.paymentLifecycle.appendStatusEvent(client, {
      paymentRecordId: paymentRecord.id,
      beforeStatus: null,
      afterStatus: "paid",
      reason: input.payment.comment ?? "Оплата при продаже абонемента",
      actorUserId: input.actorUserId,
      aggregateVersion: 1,
      actualPaymentId,
      occurredAt: input.payment.occurredAt!,
    });
    await this.paymentLifecycle.initializeRecordAggregate(
      client,
      paymentRecord.id,
      1,
    );
    return { actualPaymentId: actualPayment.id, paymentRecordId, actualPayment };
  }

  private deterministicId(
    actorUserId: string,
    operation: string,
    idempotencyKey: string,
  ): string {
    const hex = createHash("sha256")
      .update(`${actorUserId}\0${operation}\0${idempotencyKey}`)
      .digest("hex")
      .slice(0, 32)
      .split("");
    hex[12] = "4";
    hex[16] = ["8", "9", "a", "b"][parseInt(hex[16]!, 16) % 4]!;
    const value = hex.join("");
    return [
      value.slice(0, 8),
      value.slice(8, 12),
      value.slice(12, 16),
      value.slice(16, 20),
      value.slice(20),
    ].join("-");
  }
}
