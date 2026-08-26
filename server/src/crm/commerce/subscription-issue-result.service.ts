import { ConflictException, Injectable } from "@nestjs/common";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";

@Injectable()
export class SubscriptionIssueResultService {
  constructor(private readonly repository: SubscriptionIssueRepository) {}

  async load(subscriptionId: string, subscriptionVersion: number) {
    const subscription =
      await this.repository.findIssuedSubscription(subscriptionId);
    if (!subscription) {
      throw new ConflictException({
        code: "ISSUE_RESULT_MISSING",
        message: "Зафиксированный результат выдачи не найден.",
        subscriptionId,
      });
    }
    const [installments, obligations] = await Promise.all([
      this.repository.listInstallments(subscriptionId),
      this.repository.listObligations(subscriptionId),
    ]);
    const finalPriceMinor = subscription.commercial_snapshot.finalPriceMinor;
    const netMinor = finalPriceMinor === "0" ? "0" : `-${finalPriceMinor}`;
    return {
      subscription: {
        id: subscription.id,
        studentId: subscription.student_id,
        payerStudentId: subscription.payer_student_id,
        fundingMode: subscription.funding_mode,
        purchaseReason: subscription.purchase_reason,
        packageId: subscription.package_id,
        unitCount: Number(subscription.lessons_total),
        unitsUsed: 0,
        startsAt: subscription.starts_at,
        expiresAt: subscription.expires_at,
        status: "active",
        version: subscriptionVersion,
        commercialSnapshot: subscription.commercial_snapshot,
        createdAt: subscription.created_at,
      },
      installments: installments.map((item) => ({
        id: item.id,
        installmentNumber: item.installment_number,
        dueAt: item.due_at,
        amountMinor: item.amount_minor,
        currencyCode: item.currency_code,
        status: "pending" as const,
        version: 1,
      })),
      obligations: obligations.map((item) => ({
        id: item.id,
        factType: item.fact_type,
        direction: item.direction,
        amountMinor: item.amount_minor,
        currencyCode: item.currency_code,
        sourceType: item.source_type,
        sourceRef: item.source_ref,
        occurredAt: item.occurred_at,
      })),
      balanceAtIssue: {
        currencyCode: subscription.commercial_snapshot.currencyCode,
        actualPaymentsMinor: "0",
        obligationsMinor: finalPriceMinor,
        netMinor,
      },
    };
  }
}
