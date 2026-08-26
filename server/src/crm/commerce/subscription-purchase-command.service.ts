import {
  BadRequestException,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import { PurchaseSubscriptionCommandDto } from "../dto/issue-subscription.dto";
import { SubscriptionCommercialTermsService } from "./subscription-commercial-terms.service";
import {
  CommerceMutationMetadata,
  IssueMutationResult,
} from "./subscription-issue.contracts";
import { SubscriptionIssueResultService } from "./subscription-issue-result.service";
import {
  PurchaseContext,
  SubscriptionIssueRepository,
} from "./subscription-issue.repository";
import { SubscriptionPurchasePreviewService } from "./subscription-purchase-preview.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

@Injectable()
export class SubscriptionPurchaseCommandService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly reservations: SubscriptionReservationService,
    private readonly preview: SubscriptionPurchasePreviewService,
    private readonly terms: SubscriptionCommercialTermsService,
    private readonly results: SubscriptionIssueResultService,
  ) {}

  async purchase(
    actor: ActorContext,
    recipientStudentId: string,
    dto: PurchaseSubscriptionCommandDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.terms.assertPaymentMethod(dto.paymentMethod);
    const subscriptionId = this.deterministicId(
      actor.userId,
      "crm.subscription.purchase",
      metadata.idempotencyKey,
    );
    const audit: PlatformAuditInput = {
      action: "crm.subscription_purchased",
      entityType: "subscription",
      entityId: subscriptionId,
      reason: "subscription_purchase",
      reasonText: dto.purchaseReason?.trim() || "Покупка абонемента",
      metadata: {
        recipientStudentId,
        payerStudentId: dto.payerStudentId,
        packageId: dto.packageId,
        fundingMode: dto.fundingMode,
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<IssueMutationResult>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: {
          actor,
          capabilityKey: "commerce.client_finance.write",
        },
        operation: "crm.subscription.purchase",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType: "commerce:issued-subscription",
        aggregateId: subscriptionId,
        expectedVersion: 0,
        payload: {
          recipientStudentId,
          payerStudentId: dto.payerStudentId,
          fundingMode: dto.fundingMode,
          commandFingerprint: fingerprintPayload(dto),
        },
        audit,
        outbox: {
          type: "commerce.subscription.changed",
          payload: {
            entityId: subscriptionId,
            state: "active",
            invalidates: ["student-finance", "subscription"],
          },
        },
        mutate: async (client, nextVersion) => {
          const signedPayload = this.preview.decodeBoundToken(
            actor,
            recipientStudentId,
            dto,
          );
          const students = await this.repository.lockPurchaseStudents(
            client,
            actor,
            [recipientStudentId, dto.payerStudentId],
          );
          const packageRow = await this.repository.findActivePackageForShare(
            client,
            dto.packageId,
          );
          const context: PurchaseContext = {
            students,
            package: packageRow,
            payerBalanceMinor: packageRow
              ? await this.repository.readAccountBalance(
                  client,
                  dto.payerStudentId,
                  packageRow.currency_code,
                )
              : "0",
          };
          const activePackage = this.preview.assertPurchaseContext(
            context,
            recipientStudentId,
            dto.payerStudentId,
          );
          const normalized = this.terms.normalizePurchase(
            recipientStudentId,
            dto,
            activePackage,
          );
          audit.reasonText = this.terms.auditReasonForPurchase(normalized);
          this.preview.assertStillCurrent(
            signedPayload,
            this.preview.createTokenPayload(
              actor,
              recipientStudentId,
              dto,
              context,
              normalized,
            ),
          );
          this.assertSufficientBalance(
            dto.fundingMode,
            context.payerBalanceMinor,
            normalized.finalPriceMinor,
          );
          const subscription =
            await this.repository.createIssuedSubscription(client, {
              id: subscriptionId,
              studentId: recipientStudentId,
              payerStudentId: dto.payerStudentId,
              fundingMode: dto.fundingMode,
              purchaseReason: normalized.purchaseReason,
              package: activePackage,
              snapshot: normalized.snapshot,
              discount: normalized.discount.columns,
              finalPriceMinor: normalized.finalPriceMinor,
              version: nextVersion,
            });
          await this.repository.createInstallments(client, {
            issuedSubscriptionId: subscription.id,
            currencyCode: activePackage.currency_code,
            installments: normalized.installments,
          });
          await this.repository.createObligations(client, {
            studentId: dto.payerStudentId,
            issuedSubscriptionId: subscription.id,
            currencyCode: activePackage.currency_code,
            finalPriceMinor: normalized.finalPriceMinor,
            installments: normalized.installments,
            singlePurchaseDebit: true,
          });
          await this.repository.createIssueLifecycle(client, {
            issuedSubscriptionId: subscription.id,
            actorUserId: actor.userId,
            version: nextVersion,
            reason: normalized.purchaseReason ?? "Покупка абонемента",
          });
          audit.afterRef = {
            subscriptionId: subscription.id,
            subscriptionVersion: nextVersion,
            recipientStudentId,
            payerStudentId: dto.payerStudentId,
            packageId: activePackage.id,
            packageVersion: Number(activePackage.version),
          };
          return { entityId: subscription.id, version: nextVersion };
        },
      });
    const response = await this.results.load(
      result.resultRef.entityId,
      result.resultRef.version,
    );
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId: recipientStudentId,
        payerStudentId: dto.payerStudentId,
        subscriptionId: result.resultRef.entityId,
      });
    }
    return response;
  }

  private assertSufficientBalance(
    fundingMode: "personal_account" | "installment",
    availableMinor: string,
    requiredMinor: string,
  ): void {
    if (fundingMode === "personal_account" && BigInt(availableMinor) < BigInt(requiredMinor)) {
      throw new UnprocessableEntityException({
        code: "INSUFFICIENT_PERSONAL_ACCOUNT_BALANCE",
        message:
          "На личном счёте плательщика недостаточно средств для полной покупки.",
        availableMinor,
        requiredMinor,
      });
    }
  }

  private assertMetadata(metadata: CommerceMutationMetadata): void {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new BadRequestException({
        code: "INVALID_IDEMPOTENCY_KEY",
        message: "Idempotency-Key должен содержать 8–160 безопасных символов.",
      });
    }
    if (!metadata.requestId || metadata.requestId.length > 128 || /[\r\n]/.test(metadata.requestId)) {
      throw new BadRequestException({
        code: "INVALID_REQUEST_ID",
        message: "X-Request-Id обязателен и не должен превышать 128 символов.",
      });
    }
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
