import {
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { CrmPolicy } from "../crm.policy";
import {
  SubscriptionCancelCommandDto,
} from "../dto/subscription-cancel.dto";
import {
  SubscriptionReplaceCommandDto,
  SubscriptionReplacePreviewDto,
} from "../dto/subscription-replace.dto";
import { SubscriptionLifecycleRepository } from "./subscription-lifecycle.repository";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";
import { SubscriptionCancellationPolicy } from "./subscription-cancellation.policy";
import { SubscriptionReplacementService } from "./subscription-replacement.service";
import {
  CancellationResultRef,
  SubscriptionLifecycleMutationMetadata,
} from "./subscription-lifecycle.types";
import { SubscriptionReservationService } from "./subscription-reservation.service";

export type {
  CancellationResultRef,
  ReplacementResultRef,
  SubscriptionLifecycleMutationMetadata,
} from "./subscription-lifecycle.types";

@Injectable()
export class SubscriptionLifecycleService {
  constructor(
    private readonly repository: SubscriptionLifecycleRepository,
    private readonly issueRepository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly reservations: SubscriptionReservationService,
    private readonly commands: SubscriptionLifecycleCommandPolicy,
    private readonly cancellationPolicy: SubscriptionCancellationPolicy,
    private readonly replacement: SubscriptionReplacementService,
  ) {}

  async previewReplacement(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplacePreviewDto,
  ) {
    return this.replacement.preview(actor, studentId, issuedSubscriptionId, dto);
  }

  async replace(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplaceCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ) {
    return this.replacement.execute(
      actor,
      studentId,
      issuedSubscriptionId,
      dto,
      metadata,
    );
  }

  async previewCancellation(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const context = await this.repository.readCancellationContext(
      issuedSubscriptionId,
    );
    this.cancellationPolicy.assertContext(context);
    this.commands.assertStudentScope(context, studentId);
    await this.issueRepository.assertStudentsInScope(actor, [
      context.studentId,
      context.payerStudentId,
    ]);
    const calculation = this.cancellationPolicy.calculate(context);
    const signed = this.previewTokens.issueCancellation(
      this.cancellationPolicy.createTokenPayload(actor, context),
    );
    return {
      issuedSubscriptionId,
      expectedVersion: context.version,
      package: {
        id: context.package.id,
        name: context.package.name,
        unitCount: context.package.unitCount,
      },
      usage: {
        usedUnits: context.usedUnits,
        reservedUnits: context.reservedUnits,
        unusedUnits: hundredthsToUnits(calculation.unusedUnits),
      },
      financial: {
        payerStudentId: context.payerStudentId,
        fundingMode: context.fundingMode,
        currencyCode: context.currencyCode,
        finalMinor: context.finalMinor,
        actualPaidMinor: context.actualPaidMinor,
        confirmedFundedMinor: calculation.confirmedFundedMinor.toString(),
        previousRefundMinor: calculation.previousRefundMinor.toString(),
        writeoffMinor: context.writeoffMinor,
        balanceMinor: context.balanceMinor,
        unusedValueMinor: calculation.unusedValueMinor.toString(),
        unfundedCancellationMinor:
          calculation.unfundedCancellationMinor.toString(),
        recommendedRefundMinor:
          calculation.recommendedRefundMinor.toString(),
        maximumRefundMinor: calculation.recommendedRefundMinor.toString(),
      },
      openPayments: {
        count: context.openPaymentRecordRefs.length,
        amountMinor: sumMinor(
          context.openPaymentRecordRefs.map((record) => record.amountMinor),
        ).toString(),
      },
      future: {
        lessonCount: context.futureLessonCount,
        reservedLessonCount: context.reservedLessonCount,
        reservedUnits: context.reservedUnits,
        lessons: context.futureLessons.map((lesson) => ({
          lessonId: lesson.lessonId,
          scheduledAt: lesson.scheduledAt,
          units: lesson.units,
          reserved: lesson.reserved,
        })),
      },
      warnings: this.cancellationPolicy.warnings(context),
      previewToken: signed.token,
      expiresAt: signed.expiresAt,
    };
  }

  async cancel(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionCancelCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.commands.assertCancellationCommand(dto, metadata);
    const reason = dto.reason.trim();
    const auditId = randomUUID();
    const audit: PlatformAuditInput = {
      id: auditId,
      action: "crm.subscription_cancelled",
      entityType: "subscription",
      entityId: issuedSubscriptionId,
      reason: "subscription_cancel",
      reasonText: reason,
      beforeRef: {
        subscriptionId: issuedSubscriptionId,
        version: dto.expectedVersion,
        lifecycle: "active",
      },
      metadata: {
        lifecycle: "cancelled",
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<CancellationResultRef>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: {
          actor,
          capabilityKey: "commerce.client_finance.write",
        },
        operation: "crm.subscription.cancel",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType: "commerce:issued-subscription",
        aggregateId: issuedSubscriptionId,
        expectedVersion: dto.expectedVersion,
        payload: {
          issuedSubscriptionId,
          studentId,
          expectedVersion: dto.expectedVersion,
          previewToken: dto.previewToken,
          confirm: dto.confirm,
          reason,
          refundMinor: dto.refundMinor,
        },
        audit,
        outbox: {
          type: "commerce.subscription.changed",
          payload: {
            entityId: issuedSubscriptionId,
            state: "cancelled",
            invalidates: ["student-finance", "subscription", "schedule"],
          },
        },
        mutate: async (client, nextVersion) => {
          // Verification stays inside mutate so an idempotent replay remains
          // valid after the short-lived preview token expires.
          const signedPayload = this.previewTokens.verifyCancellation(
            dto.previewToken,
          );
          this.commands.assertCancellationTokenBinding(
            signedPayload,
            actor,
            studentId,
            issuedSubscriptionId,
            dto.expectedVersion,
          );
          const scopedStudents = new Set([
            studentId,
            signedPayload.payerStudentId,
          ]);
          if (
            (await this.issueRepository.lockPurchaseStudents(
              client,
              actor,
              [...scopedStudents],
            )).length !== scopedStudents.size
          ) {
            throw new NotFoundException("Клиент или плательщик не найден.");
          }
          const issued = await this.repository.lockIssuedSubscription(
            client,
            issuedSubscriptionId,
          );
          if (!issued) {
            throw new NotFoundException("Выданный абонемент не найден.");
          }
          if (
            issued.status !== "active" ||
            Number(issued.version) !== dto.expectedVersion
          ) {
            throw new ConflictException({
              code: "SUBSCRIPTION_CANCEL_CONFLICT",
              message: "Абонемент уже изменён или больше не активен.",
              expectedVersion: dto.expectedVersion,
              currentVersion: Number(issued.version),
              currentStatus: issued.status,
            });
          }
          await this.repository.lockCancellationInstallments(
            client,
            issuedSubscriptionId,
          );
          await this.repository.lockReservedRows(
            client,
            issuedSubscriptionId,
          );
          await this.repository.lockCancellationPaymentRecords(
            client,
            issuedSubscriptionId,
          );
          const context =
            await this.repository.readCancellationContextInTransaction(
              client,
              issuedSubscriptionId,
            );
          this.cancellationPolicy.assertContext(context);
          this.commands.assertStudentScope(context, studentId);
          this.cancellationPolicy.assertPreviewCurrent(
            signedPayload,
            this.cancellationPolicy.createTokenPayload(actor, context),
          );
          const calculation = this.cancellationPolicy.calculate(context);
          const chosenRefundMinor = this.cancellationPolicy.assertRefundWithinCap(
            dto.refundMinor,
            calculation.recommendedRefundMinor,
          );
          const totalCreditMinor =
            calculation.unfundedCancellationMinor + chosenRefundMinor;

          const closed = await this.repository.closeCancelledSubscription(
            client,
            {
              issuedSubscriptionId,
              expectedVersion: dto.expectedVersion,
              nextVersion,
            },
          );
          if (!closed) {
            throw new ConflictException({
              code: "SUBSCRIPTION_CANCEL_CONFLICT",
              message: "Абонемент изменился во время отмены.",
            });
          }
          const released =
            await this.repository.releaseCancellationReservations(
              client,
              issuedSubscriptionId,
            );
          if (
            released.count !== context.reservedLessonCount ||
            released.units !== context.reservedUnits ||
            released.remaining !== 0
          ) {
            throw new ConflictException({
              code: "SUBSCRIPTION_RESERVATION_CONFLICT",
              message:
                "Резервы занятий изменились во время отмены абонемента.",
            });
          }
          const closedPaymentRecordCount =
            await this.repository.closeCancellationPaymentRecords(client, {
              issuedSubscriptionId,
              reason,
              actorUserId: actor.userId,
              auditEventId: auditId,
            });
          if (
            closedPaymentRecordCount !== context.openPaymentRecordRefs.length
          ) {
            throw new ConflictException({
              code: "CANCELLATION_PAYMENT_RECORD_CONFLICT",
              message:
                "Статусы платежей изменились во время отмены абонемента.",
            });
          }
          const credit = await this.repository.createCancellationCredit(
            client,
            {
              payerStudentId: context.payerStudentId,
              issuedSubscriptionId,
              amountMinor: totalCreditMinor.toString(),
              currencyCode: context.currencyCode,
            },
          );
          await this.repository.createCancelLifecycle(client, {
            issuedSubscriptionId,
            actorUserId: actor.userId,
            reason,
            aggregateVersion: nextVersion,
          });
          audit.afterRef = {
            subscriptionId: issuedSubscriptionId,
            version: nextVersion,
            lifecycle: "cancelled",
          };
          audit.metadata = {
            lifecycle: "cancelled",
            releasedReservationCount: released.count,
            futureLessonCount: context.futureLessonCount,
            closedRecordCount: closedPaymentRecordCount,
            payerStudentId: context.payerStudentId,
            fundingMode: context.fundingMode,
            confirmedFundedMinor:
              calculation.confirmedFundedMinor.toString(),
            previousRefundMinor: calculation.previousRefundMinor.toString(),
            unfundedCancellationMinor:
              calculation.unfundedCancellationMinor.toString(),
            chosenRefundMinor: chosenRefundMinor.toString(),
            totalCreditMinor: totalCreditMinor.toString(),
          };
          return {
            sourceId: issuedSubscriptionId,
            resultVersion: nextVersion,
            state: "cancelled",
            payerStudentId: context.payerStudentId,
            releasedCount: released.count,
            releasedUnits: released.units,
            futureCount: context.futureLessonCount,
            closedRecordCount: closedPaymentRecordCount,
            confirmedFundedMinor:
              calculation.confirmedFundedMinor.toString(),
            previousRefundMinor: calculation.previousRefundMinor.toString(),
            unusedUnits: hundredthsToUnits(calculation.unusedUnits),
            unfundedCancellationMinor:
              calculation.unfundedCancellationMinor.toString(),
            chosenRefundMinor: chosenRefundMinor.toString(),
            totalCreditMinor: totalCreditMinor.toString(),
            creditFactId: credit?.id ?? null,
          };
        },
      });
    const response = {
      cancellation: {
        issuedSubscriptionId: result.resultRef.sourceId,
        version: result.resultRef.resultVersion,
        status: result.resultRef.state,
        payerStudentId: result.resultRef.payerStudentId,
        releasedReservationCount: result.resultRef.releasedCount,
        releasedReservationUnits: result.resultRef.releasedUnits,
        futureLessonCount: result.resultRef.futureCount,
        closedPaymentRecordCount:
          result.resultRef.closedRecordCount,
        confirmedFundedMinor: result.resultRef.confirmedFundedMinor,
        previousRefundMinor: result.resultRef.previousRefundMinor,
        unusedUnits: result.resultRef.unusedUnits,
        unfundedCancellationMinor:
          result.resultRef.unfundedCancellationMinor,
        chosenRefundMinor: result.resultRef.chosenRefundMinor,
        totalCreditMinor: result.resultRef.totalCreditMinor,
        creditFactId: result.resultRef.creditFactId,
      },
      replayed: result.replayed,
      auditId: result.auditId,
      eventId: result.eventId,
    };
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId,
        payerStudentId: result.resultRef.payerStudentId,
        subscriptionId: result.resultRef.sourceId,
      });
    }
    return response;
  }

}

function hundredthsToUnits(value: bigint): string {
  const whole = value / 100n;
  const fraction = (value % 100n).toString().padStart(2, "0");
  return fraction === "00"
    ? whole.toString()
    : `${whole}.${fraction.replace(/0$/, "")}`;
}


function sumMinor(values: string[]): bigint {
  return values.reduce((sum, value) => sum + BigInt(value), 0n);
}
