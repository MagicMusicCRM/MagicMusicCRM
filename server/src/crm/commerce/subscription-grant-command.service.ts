import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { createHash } from "crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { CrmPolicy } from "../crm.policy";
import { IssueSubscriptionDto } from "../dto/issue-subscription.dto";
import { SubscriptionCommercialTermsService } from "./subscription-commercial-terms.service";
import {
  CommerceMutationMetadata,
  IssueMutationResult,
} from "./subscription-issue.contracts";
import { SubscriptionIssueResultService } from "./subscription-issue-result.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionReservationService } from "./subscription-reservation.service";

@Injectable()
export class SubscriptionGrantCommandService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly reservations: SubscriptionReservationService,
    private readonly terms: SubscriptionCommercialTermsService,
    private readonly results: SubscriptionIssueResultService,
  ) {}

  async issue(
    actor: ActorContext,
    studentId: string,
    dto: IssueSubscriptionDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.terms.assertPaymentMethod(dto.paymentMethod);
    await this.repository.assertStudentsInScope(actor, [studentId]);
    const subscriptionId = this.deterministicId(
      actor.userId,
      "crm.subscription.issue",
      metadata.idempotencyKey,
    );
    const audit: PlatformAuditInput = {
      action: "crm.subscription_issued",
      entityType: "subscription",
      entityId: subscriptionId,
      metadata: {
        studentId,
        packageId: dto.packageId,
        lifecycle: "issued",
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<IssueMutationResult>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: {
          actor,
          capabilityKey: "commerce.subscription.issue",
        },
        operation: "crm.subscription.issue",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType: "commerce:issued-subscription",
        aggregateId: subscriptionId,
        expectedVersion: 0,
        payload: { studentId, ...dto },
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
          if (
            (await this.repository.lockPurchaseStudents(client, actor, [studentId]))
              .length !== 1
          ) {
            throw new NotFoundException("Ученик не найден.");
          }
          const packageRow = await this.repository.findActivePackageForShare(
            client,
            dto.packageId,
          );
          if (!packageRow) {
            throw new NotFoundException("Абонемент не найден или находится в архиве.");
          }
          const normalized = this.terms.normalizeIssue(dto, packageRow);
          audit.reasonText =
            normalized.discount.columns.reason ??
            (normalized.surcharge.snapshot.type === "fixed"
              ? normalized.surcharge.snapshot.reason
              : null) ??
            "Выдача абонемента";
          const subscription =
            await this.repository.createIssuedSubscription(client, {
              id: subscriptionId,
              studentId,
              payerStudentId: studentId,
              fundingMode: "legacy",
              purchaseReason: null,
              package: packageRow,
              snapshot: normalized.snapshot,
              discount: normalized.discount.columns,
              finalPriceMinor: normalized.finalPriceMinor,
              version: nextVersion,
            });
          await this.repository.createInstallments(client, {
            issuedSubscriptionId: subscription.id,
            currencyCode: packageRow.currency_code,
            installments: normalized.installments,
          });
          await this.repository.createObligations(client, {
            studentId,
            issuedSubscriptionId: subscription.id,
            currencyCode: packageRow.currency_code,
            finalPriceMinor: normalized.finalPriceMinor,
            installments: normalized.installments,
          });
          await this.repository.createIssueLifecycle(client, {
            issuedSubscriptionId: subscription.id,
            actorUserId: actor.userId,
            version: nextVersion,
          });
          audit.afterRef = {
            subscriptionId: subscription.id,
            subscriptionVersion: nextVersion,
            packageId: packageRow.id,
            packageVersion: Number(packageRow.version),
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
        studentId,
        subscriptionId: result.resultRef.entityId,
      });
    }
    return response;
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
