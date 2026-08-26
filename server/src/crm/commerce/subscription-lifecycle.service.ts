import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import {
  SubscriptionCancelCommandDto,
} from "../dto/subscription-cancel.dto";
import {
  SubscriptionReplaceCommandDto,
  SubscriptionReplacePreviewDto,
} from "../dto/subscription-replace.dto";
import {
  CancellationContext,
  SubscriptionLifecycleRepository,
} from "./subscription-lifecycle.repository";
import {
  SubscriptionCancelPreviewTokenPayload,
} from "./subscription-preview-token";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";
import { SubscriptionReplacementPolicy } from "./subscription-replacement.policy";
import {
  CancellationResultRef,
  LifecycleWarning,
  ReplacementResultRef,
  SubscriptionLifecycleMutationMetadata,
} from "./subscription-lifecycle.types";
import { SubscriptionReservationService } from "./subscription-reservation.service";

export type {
  CancellationResultRef,
  ReplacementResultRef,
  SubscriptionLifecycleMutationMetadata,
} from "./subscription-lifecycle.types";

interface CancellationCalculation {
  confirmedFundedMinor: bigint;
  previousRefundMinor: bigint;
  unusedUnits: bigint;
  unusedValueMinor: bigint;
  unfundedCancellationMinor: bigint;
  recommendedRefundMinor: bigint;
}

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
    private readonly replacements: SubscriptionReplacementPolicy,
  ) {}

  async previewReplacement(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplacePreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const context = await this.repository.readReplacementContext(
      issuedSubscriptionId,
      dto.newPackageId,
    );
    this.replacements.assertContext(context);
    this.commands.assertStudentScope(context, studentId);
    await this.issueRepository.assertStudentsInScope(actor, [
      context.studentId,
      context.payerStudentId,
    ]);
    const tokenPayload = this.replacements.createTokenPayload(actor, context);
    const signed = this.previewTokens.issue(tokenPayload);
    const calculation = this.replacements.calculate(context);
    const reservationPlan = this.replacements.planReservations(context);
    return {
      issuedSubscriptionId,
      expectedVersion: context.oldVersion,
      oldPackageId: context.oldPackageId,
      newPackage: {
        id: context.newPackage.id,
        version: context.newPackage.version,
        name: context.newPackage.name,
        unitCount: context.newPackage.unitCount,
      },
      usage: {
        usedUnits: context.usedUnits,
        reservedLessonCount: context.reservedLessonCount,
        reservedUnits: context.reservedUnits,
        transferableReservationCount:
          reservationPlan.transferReservationIds.length,
        transferableReservationUnits: reservationPlan.transferredUnits,
        releasedReservationCount:
          reservationPlan.releaseReservationIds.length,
        releasedReservationUnits: reservationPlan.releasedUnits,
        futureLessonCount: context.futureLessonCount,
        futureUnits: context.futureUnits,
      },
      financial: {
        currencyCode: context.oldCurrencyCode,
        oldFinalMinor: context.oldFinalPriceMinor,
        newFinalMinor: context.newPackage.basePriceMinor,
        actualPaidMinor: context.actualPaidMinor,
        obligationDeltaMinor: calculation.deltaMinor.toString(),
        resultingPosition: {
          kind: calculation.positionKind,
          amountMinor: absolute(calculation.positionMinor).toString(),
        },
      },
      warnings: this.replacements.warnings(context),
      previewToken: signed.token,
      expiresAt: signed.expiresAt,
    };
  }

  async replace(
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    dto: SubscriptionReplaceCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.commands.assertReplacementCommand(dto, metadata);
    const reason = dto.reason.trim();
    const newSubscriptionId = this.commands.deterministicId(
      actor.userId,
      "crm.subscription.replace",
      metadata.idempotencyKey,
    );
    const audit: PlatformAuditInput = {
      action: "crm.subscription_replaced",
      entityType: "subscription",
      entityId: issuedSubscriptionId,
      reason: "subscription_replace",
      reasonText: reason,
      beforeRef: {
        subscriptionId: issuedSubscriptionId,
        version: dto.expectedVersion,
        lifecycle: "active",
      },
      metadata: {
        lifecycle: "replaced",
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<ReplacementResultRef>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: {
          actor,
          capabilityKey: "commerce.client_finance.write",
        },
        operation: "crm.subscription.replace",
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
        },
        audit,
        outbox: {
          type: "commerce.subscription.changed",
          payload: {
            entityId: issuedSubscriptionId,
            state: "replaced",
            invalidates: ["student-finance", "subscription", "schedule"],
          },
        },
        mutate: async (client, nextVersion) => {
          // Verify before taking domain locks so recipient and payer are always
          // locked in the same UUID order as every other commerce command.
          const signedPayload = this.previewTokens.verify(dto.previewToken);
          this.commands.assertReplacementTokenBinding(
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
              code: "SUBSCRIPTION_REPLACE_CONFLICT",
              message: "Абонемент уже изменён или больше не активен.",
              expectedVersion: dto.expectedVersion,
              currentVersion: Number(issued.version),
              currentStatus: issued.status,
            });
          }

          const lockedPackage = await this.repository.lockPackage(
            client,
            signedPayload.newPackageId,
          );
          if (!lockedPackage) {
            throw new NotFoundException("Новый пакет абонемента не найден.");
          }
          await this.repository.lockReservedRows(
            client,
            issuedSubscriptionId,
          );
          const context =
            await this.repository.readReplacementContextInTransaction(
              client,
              issuedSubscriptionId,
              signedPayload.newPackageId,
            );
          this.replacements.assertContext(context);
          this.commands.assertStudentScope(context, studentId);
          this.replacements.assertPreviewCurrent(
            signedPayload,
            this.replacements.createTokenPayload(actor, context),
          );

          const calculation = this.replacements.calculate(context);
          const reservationPlan = this.replacements.planReservations(context);
          const snapshot = this.replacements.createSnapshot(
            issuedSubscriptionId,
            context,
            lockedPackage,
          );
          const replacement =
            await this.repository.createReplacementSubscription(client, {
              id: newSubscriptionId,
              studentId: context.studentId,
              package: lockedPackage,
              usedUnits: context.usedUnits,
              snapshot,
              payerStudentId: context.payerStudentId,
              fundingMode: context.fundingMode,
              purchaseReason: context.purchaseReason,
            });
          await this.repository.initializeIssuedAggregate(
            client,
            replacement.id,
          );
          const closed = await this.repository.closeReplacedSubscription(
            client,
            {
              issuedSubscriptionId,
              expectedVersion: dto.expectedVersion,
              nextVersion,
            },
          );
          if (!closed) {
            throw new ConflictException({
              code: "SUBSCRIPTION_REPLACE_CONFLICT",
              message: "Абонемент изменился во время замены.",
            });
          }
          const reservationResult =
            await this.repository.applyReservationPlan(client, {
              oldIssuedSubscriptionId: issuedSubscriptionId,
              newIssuedSubscriptionId: replacement.id,
              transferReservationIds:
                reservationPlan.transferReservationIds,
              releaseReservationIds:
                reservationPlan.releaseReservationIds,
            });
          if (
            reservationResult.transferred !==
              reservationPlan.transferReservationIds.length ||
            reservationResult.released !==
              reservationPlan.releaseReservationIds.length ||
            reservationResult.remaining !== 0
          ) {
            throw new ConflictException({
              code: "SUBSCRIPTION_RESERVATION_CONFLICT",
              message:
                "Резервы занятий изменились во время замены абонемента.",
            });
          }
          const obligation =
            await this.repository.createReplacementObligation(client, {
              studentId: context.payerStudentId,
              issuedSubscriptionId: replacement.id,
              deltaMinor: calculation.deltaMinor,
              currencyCode: context.oldCurrencyCode,
            });
          await this.repository.createReplaceLifecycle(client, {
            oldIssuedSubscriptionId: issuedSubscriptionId,
            newIssuedSubscriptionId: replacement.id,
            actorUserId: actor.userId,
            reason,
          });
          const resultRef: ReplacementResultRef = {
            sourceId: issuedSubscriptionId,
            sourceVersion: nextVersion,
            resultId: replacement.id,
            resultVersion: 1,
            payerStudentId: context.payerStudentId,
            newPackageId: context.newPackage.id,
            newPackageVersion: context.newPackage.version,
            usedUnits: context.usedUnits,
            transferredReservationCount: reservationResult.transferred,
            transferredReservationUnits: reservationPlan.transferredUnits,
            releasedReservationCount: reservationResult.released,
            releasedReservationUnits: reservationPlan.releasedUnits,
            deltaMinor: calculation.deltaMinor.toString(),
            positionKind: calculation.positionKind,
            positionMinor: absolute(calculation.positionMinor).toString(),
            ccy: context.oldCurrencyCode,
            obligationFactId: obligation?.id ?? null,
          };
          audit.afterRef = {
            oldSubscriptionId: issuedSubscriptionId,
            oldSubscriptionVersion: nextVersion,
            newSubscriptionId: replacement.id,
            newSubscriptionVersion: 1,
            lifecycle: "active",
          };
          audit.metadata = {
            lifecycle: "replaced",
            newPackageId: context.newPackage.id,
            newPackageVersion: context.newPackage.version,
            usedUnits: context.usedUnits,
            transferredReservationCount: reservationResult.transferred,
            releasedReservationCount: reservationResult.released,
            positionKind: calculation.positionKind,
          };
          return resultRef;
        },
      });
    const response = {
      replacement: {
        oldSubscriptionId: result.resultRef.sourceId,
        oldSubscriptionVersion: result.resultRef.sourceVersion,
        newSubscriptionId: result.resultRef.resultId,
        newSubscriptionVersion: result.resultRef.resultVersion,
        newPackageId: result.resultRef.newPackageId,
        newPackageVersion: result.resultRef.newPackageVersion,
        usedUnits: result.resultRef.usedUnits,
        transferredReservationCount:
          result.resultRef.transferredReservationCount,
        transferredReservationUnits:
          result.resultRef.transferredReservationUnits,
        releasedReservationCount:
          result.resultRef.releasedReservationCount,
        releasedReservationUnits:
          result.resultRef.releasedReservationUnits,
        deltaMinor: result.resultRef.deltaMinor,
        positionKind: result.resultRef.positionKind,
        positionMinor: result.resultRef.positionMinor,
        ccy: result.resultRef.ccy,
        obligationFactId: result.resultRef.obligationFactId,
      },
      replayed: result.replayed,
      auditId: result.auditId,
      eventId: result.eventId,
    };
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId,
        payerStudentId: result.resultRef.payerStudentId,
        subscriptionId: result.resultRef.resultId,
      });
    }
    return response;
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
    this.assertCancellableContext(context);
    this.commands.assertStudentScope(context, studentId);
    await this.issueRepository.assertStudentsInScope(actor, [
      context.studentId,
      context.payerStudentId,
    ]);
    const calculation = this.calculateCancellation(context);
    const signed = this.previewTokens.issueCancellation(
      this.createCancellationTokenPayload(actor, context),
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
      warnings: this.cancellationWarnings(context),
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
          this.assertCancellableContext(context);
          this.commands.assertStudentScope(context, studentId);
          this.assertCancellationPreviewStillCurrent(
            signedPayload,
            this.createCancellationTokenPayload(actor, context),
          );
          const calculation = this.calculateCancellation(context);
          const chosenRefundMinor = BigInt(dto.refundMinor);
          if (chosenRefundMinor > calculation.recommendedRefundMinor) {
            throw new UnprocessableEntityException({
              code: "CANCELLATION_REFUND_EXCEEDS_CAP",
              message: "Возврат превышает подтверждённый доступный максимум.",
              maximumRefundMinor:
                calculation.recommendedRefundMinor.toString(),
            });
          }
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

  private createCancellationTokenPayload(
    actor: ActorContext,
    context: CancellationContext,
  ): Omit<
    SubscriptionCancelPreviewTokenPayload,
    "issuedAtSeconds" | "expiresAtSeconds"
  > {
    return {
      kind: "subscription.cancel",
      actorUserId: actor.userId,
      studentId: context.studentId,
      payerStudentId: context.payerStudentId,
      issuedSubscriptionId: context.issuedSubscriptionId,
      expectedVersion: context.version,
      packageId: context.package.id,
      packageVersion: context.package.version,
      unitCount: context.package.unitCount,
      usedUnits: context.usedUnits,
      currencyCode: context.currencyCode,
      finalMinor: context.finalMinor,
      actualPaidMinor: context.actualPaidMinor,
      fundingMode: context.fundingMode,
      previousRefundMinor: context.previousRefundMinor,
      writeoffMinor: context.writeoffMinor,
      balanceMinor: context.balanceMinor,
      openPaymentRecordCount: context.openPaymentRecordRefs.length,
      openPaymentRecordMinor: sumMinor(
        context.openPaymentRecordRefs.map((record) => record.amountMinor),
      ).toString(),
      futureLessonCount: context.futureLessonCount,
      reservedLessonCount: context.reservedLessonCount,
      reservedUnits: context.reservedUnits,
      impactFingerprint: fingerprintPayload({
        payments: context.paymentRefs,
        refunds: context.previousRefundRefs,
        openPaymentRecords: context.openPaymentRecordRefs,
        writeoffs: context.writeoffRefs,
        obligations: context.obligationRefs,
        future: context.futureLessons,
      }),
    };
  }

  private assertCancellableContext(
    context: CancellationContext | null,
  ): asserts context is CancellationContext {
    if (!context) {
      throw new NotFoundException("Выданный абонемент не найден.");
    }
    if (context.status !== "active") {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_NOT_ACTIVE",
        message: "Отменить можно только активный абонемент.",
        status: context.status,
      });
    }
  }

  private assertCancellationPreviewStillCurrent(
    signed: SubscriptionCancelPreviewTokenPayload,
    current: Omit<
      SubscriptionCancelPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
  ): void {
    const {
      issuedAtSeconds: _issuedAtSeconds,
      expiresAtSeconds: _expiresAtSeconds,
      ...signedFacts
    } = signed;
    if (fingerprintPayload(signedFacts) !== fingerprintPayload(current)) {
      throw new ConflictException({
        code: "CANCELLATION_PREVIEW_STALE",
        message:
          "После предпросмотра изменились платежи, списания, резервы или баланс.",
      });
    }
  }

  private calculateCancellation(
    context: CancellationContext,
  ): CancellationCalculation {
    const totalUnits = unitsToHundredths(context.package.unitCount);
    if (totalUnits <= 0n) {
      throw new UnprocessableEntityException({
        code: "CANCELLATION_UNITS_INVALID",
        message: "У абонемента нет корректного объёма для расчёта возврата.",
      });
    }
    const protectedUnits = minBigInt(
      totalUnits,
      unitsToHundredths(context.usedUnits) +
        unitsToHundredths(context.reservedUnits),
    );
    const unusedUnits = totalUnits - protectedUnits;
    const finalMinor = BigInt(context.finalMinor);
    const actualPaidMinor = BigInt(context.actualPaidMinor);
    const confirmedFundedMinor =
      context.fundingMode === "personal_account"
        ? finalMinor
        : minBigInt(finalMinor, maxBigInt(0n, actualPaidMinor));
    const previousRefundMinor = BigInt(context.previousRefundMinor);
    const unusedValueMinor = (finalMinor * unusedUnits) / totalUnits;
    const grossRefundMinor =
      (confirmedFundedMinor * unusedUnits) / totalUnits;
    const recommendedRefundMinor = minBigInt(
      unusedValueMinor,
      maxBigInt(0n, grossRefundMinor - previousRefundMinor),
    );
    return {
      confirmedFundedMinor,
      previousRefundMinor,
      unusedUnits,
      unusedValueMinor,
      unfundedCancellationMinor:
        unusedValueMinor - recommendedRefundMinor,
      recommendedRefundMinor,
    };
  }

  private cancellationWarnings(context: CancellationContext): LifecycleWarning[] {
    const warnings: LifecycleWarning[] = [];
    if (context.futureLessonCount > 0) {
      warnings.push({
        code: "FUTURE_LESSONS_PRESERVED",
        count: context.futureLessonCount,
        message:
          "Будущие занятия сохранятся; активные резервы абонемента будут сняты.",
      });
    }
    if (context.reservedLessonCount > 0) {
      warnings.push({
        code: "RESERVATIONS_RELEASED",
        count: context.reservedLessonCount,
        units: context.reservedUnits,
        message:
          "Резервы будут сняты без удаления или изменения самих занятий.",
      });
    }
    if (BigInt(context.actualPaidMinor) > 0n) {
      warnings.push({
        code: "ACTUAL_PAYMENTS_PRESERVED",
        message: "Фактические платежи и выручка останутся неизменными.",
      });
    }
    if (
      context.writeoffRefs.length > 0 ||
      BigInt(context.writeoffMinor) > 0n
    ) {
      warnings.push({
        code: "WRITEOFFS_PRESERVED",
        count: context.writeoffRefs.length,
        message: "Исторические списания останутся неизменными.",
      });
    }
    return warnings;
  }

}

function unitsToHundredths(value: string): bigint {
  if (!/^(0|[1-9]\d*)(\.\d{1,2})?$/.test(value)) {
    throw new TypeError(`Invalid unit value: ${value}`);
  }
  const [whole, fraction = ""] = value.split(".");
  return BigInt(whole!) * 100n + BigInt(fraction.padEnd(2, "0"));
}

function hundredthsToUnits(value: bigint): string {
  const whole = value / 100n;
  const fraction = (value % 100n).toString().padStart(2, "0");
  return fraction === "00"
    ? whole.toString()
    : `${whole}.${fraction.replace(/0$/, "")}`;
}

function absolute(value: bigint): bigint {
  return value < 0n ? -value : value;
}

function sumMinor(values: string[]): bigint {
  return values.reduce((sum, value) => sum + BigInt(value), 0n);
}

function minBigInt(left: bigint, right: bigint): bigint {
  return left < right ? left : right;
}

function maxBigInt(left: bigint, right: bigint): bigint {
  return left > right ? left : right;
}
