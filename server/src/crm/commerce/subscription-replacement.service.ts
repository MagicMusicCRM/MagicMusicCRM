import {
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  PlatformAuditInput,
  VersionedMutationResult,
} from "../../platform/platform-integrity.types";
import { CrmPolicy } from "../crm.policy";
import {
  SubscriptionReplaceCommandDto,
  SubscriptionReplacePreviewDto,
} from "../dto/subscription-replace.dto";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";
import {
  ReplacementIssuedRow,
  SubscriptionLifecycleRepository,
} from "./subscription-lifecycle.repository";
import {
  ReplacementResultRef,
  SubscriptionLifecycleMutationMetadata,
} from "./subscription-lifecycle.types";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import {
  ReplacementCalculation,
  ReplacementReadyContext,
  ReplacementReservationPlan,
  SubscriptionReplacementPolicy,
} from "./subscription-replacement.policy";
import { SubscriptionReservationService } from "./subscription-reservation.service";

/** Owns replacement preview and the complete versioned mutation boundary. */
@Injectable()
export class SubscriptionReplacementService {
  constructor(
    private readonly repository: SubscriptionLifecycleRepository,
    private readonly issueRepository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly reservations: SubscriptionReservationService,
    private readonly commands: SubscriptionLifecycleCommandPolicy,
    private readonly replacementPolicy: SubscriptionReplacementPolicy,
  ) {}

  async preview(
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
    this.replacementPolicy.assertContext(context);
    this.commands.assertStudentScope(context, studentId);
    await this.issueRepository.assertStudentsInScope(actor, [
      context.studentId,
      context.payerStudentId,
    ]);
    const tokenPayload = this.replacementPolicy.createTokenPayload(
      actor,
      context,
    );
    const signed = this.previewTokens.issue(tokenPayload);
    const calculation = this.replacementPolicy.calculate(context);
    const reservationPlan = this.replacementPolicy.planReservations(context);
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
        releasedReservationCount: reservationPlan.releaseReservationIds.length,
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
      warnings: this.replacementPolicy.warnings(context),
      previewToken: signed.token,
      expiresAt: signed.expiresAt,
    };
  }

  async execute(
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
    const audit = createReplacementAudit(
      issuedSubscriptionId,
      dto.expectedVersion,
      reason,
    );
    const payload = createReplacementMutationPayload(
      issuedSubscriptionId,
      studentId,
      dto,
      reason,
    );
    const outbox = createReplacementOutbox(issuedSubscriptionId);
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
        payload,
        audit,
        outbox,
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
            (
              await this.issueRepository.lockPurchaseStudents(client, actor, [
                ...scopedStudents,
              ])
            ).length !== scopedStudents.size
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
          if (!isCurrentActiveSubscription(issued, dto.expectedVersion)) {
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
          await this.repository.lockReservedRows(client, issuedSubscriptionId);
          const context =
            await this.repository.readReplacementContextInTransaction(
              client,
              issuedSubscriptionId,
              signedPayload.newPackageId,
            );
          this.replacementPolicy.assertContext(context);
          this.commands.assertStudentScope(context, studentId);
          this.replacementPolicy.assertPreviewCurrent(
            signedPayload,
            this.replacementPolicy.createTokenPayload(actor, context),
          );

          const calculation = this.replacementPolicy.calculate(context);
          const reservationPlan =
            this.replacementPolicy.planReservations(context);
          const snapshot = this.replacementPolicy.createSnapshot(
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
          const reservationResult = await this.repository.applyReservationPlan(
            client,
            {
              oldIssuedSubscriptionId: issuedSubscriptionId,
              newIssuedSubscriptionId: replacement.id,
              transferReservationIds: reservationPlan.transferReservationIds,
              releaseReservationIds: reservationPlan.releaseReservationIds,
            },
          );
          if (!reservationPlanWasApplied(reservationResult, reservationPlan)) {
            throw new ConflictException({
              code: "SUBSCRIPTION_RESERVATION_CONFLICT",
              message: "Резервы занятий изменились во время замены абонемента.",
            });
          }
          const obligation = await this.repository.createReplacementObligation(
            client,
            {
              studentId: context.payerStudentId,
              issuedSubscriptionId: replacement.id,
              deltaMinor: calculation.deltaMinor,
              currencyCode: context.oldCurrencyCode,
            },
          );
          await this.repository.createReplaceLifecycle(client, {
            oldIssuedSubscriptionId: issuedSubscriptionId,
            newIssuedSubscriptionId: replacement.id,
            actorUserId: actor.userId,
            reason,
          });
          const resultRef = createReplacementResultRef({
            issuedSubscriptionId,
            nextVersion,
            replacementId: replacement.id,
            context,
            reservationResult,
            reservationPlan,
            calculation,
            obligationFactId: replacementObligationFactId(obligation),
          });
          const auditResult = createReplacementAuditResult({
            issuedSubscriptionId,
            nextVersion,
            replacementId: replacement.id,
            context,
            reservationResult,
            calculation,
          });
          audit.afterRef = auditResult.afterRef;
          audit.metadata = auditResult.metadata;
          return resultRef;
        },
      });
    const response = mapReplacementResponse(result);
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId,
        payerStudentId: result.resultRef.payerStudentId,
        subscriptionId: result.resultRef.resultId,
      });
    }
    return response;
  }
}

function createReplacementAudit(
  issuedSubscriptionId: string,
  expectedVersion: number,
  reason: string,
): PlatformAuditInput {
  return {
    action: "crm.subscription_replaced",
    entityType: "subscription",
    entityId: issuedSubscriptionId,
    reason: "subscription_replace",
    reasonText: reason,
    beforeRef: {
      subscriptionId: issuedSubscriptionId,
      version: expectedVersion,
      lifecycle: "active",
    },
    metadata: {
      lifecycle: "replaced",
    },
  };
}

function createReplacementMutationPayload(
  issuedSubscriptionId: string,
  studentId: string,
  dto: SubscriptionReplaceCommandDto,
  reason: string,
) {
  return {
    issuedSubscriptionId,
    studentId,
    expectedVersion: dto.expectedVersion,
    previewToken: dto.previewToken,
    confirm: dto.confirm,
    reason,
  };
}

function createReplacementOutbox(issuedSubscriptionId: string) {
  return {
    type: "commerce.subscription.changed",
    payload: {
      entityId: issuedSubscriptionId,
      state: "replaced",
      invalidates: ["student-finance", "subscription", "schedule"],
    },
  };
}

function createReplacementResultRef(input: {
  issuedSubscriptionId: string;
  nextVersion: number;
  replacementId: string;
  context: ReplacementReadyContext;
  reservationResult: ReplacementReservationResult;
  reservationPlan: ReplacementReservationPlan;
  calculation: ReplacementCalculation;
  obligationFactId: string | null;
}): ReplacementResultRef {
  return {
    sourceId: input.issuedSubscriptionId,
    sourceVersion: input.nextVersion,
    resultId: input.replacementId,
    resultVersion: 1,
    payerStudentId: input.context.payerStudentId,
    newPackageId: input.context.newPackage.id,
    newPackageVersion: input.context.newPackage.version,
    usedUnits: input.context.usedUnits,
    transferredReservationCount: input.reservationResult.transferred,
    transferredReservationUnits: input.reservationPlan.transferredUnits,
    releasedReservationCount: input.reservationResult.released,
    releasedReservationUnits: input.reservationPlan.releasedUnits,
    deltaMinor: input.calculation.deltaMinor.toString(),
    positionKind: input.calculation.positionKind,
    positionMinor: absolute(input.calculation.positionMinor).toString(),
    ccy: input.context.oldCurrencyCode,
    obligationFactId: input.obligationFactId,
  };
}

function createReplacementAuditResult(input: {
  issuedSubscriptionId: string;
  nextVersion: number;
  replacementId: string;
  context: ReplacementReadyContext;
  reservationResult: ReplacementReservationResult;
  calculation: ReplacementCalculation;
}): Pick<PlatformAuditInput, "afterRef" | "metadata"> {
  return {
    afterRef: {
      oldSubscriptionId: input.issuedSubscriptionId,
      oldSubscriptionVersion: input.nextVersion,
      newSubscriptionId: input.replacementId,
      newSubscriptionVersion: 1,
      lifecycle: "active",
    },
    metadata: {
      lifecycle: "replaced",
      newPackageId: input.context.newPackage.id,
      newPackageVersion: input.context.newPackage.version,
      usedUnits: input.context.usedUnits,
      transferredReservationCount: input.reservationResult.transferred,
      releasedReservationCount: input.reservationResult.released,
      positionKind: input.calculation.positionKind,
    },
  };
}

function mapReplacementResponse(
  result: VersionedMutationResult<ReplacementResultRef>,
) {
  return {
    replacement: {
      oldSubscriptionId: result.resultRef.sourceId,
      oldSubscriptionVersion: result.resultRef.sourceVersion,
      newSubscriptionId: result.resultRef.resultId,
      newSubscriptionVersion: result.resultRef.resultVersion,
      newPackageId: result.resultRef.newPackageId,
      newPackageVersion: result.resultRef.newPackageVersion,
      usedUnits: result.resultRef.usedUnits,
      transferredReservationCount: result.resultRef.transferredReservationCount,
      transferredReservationUnits: result.resultRef.transferredReservationUnits,
      releasedReservationCount: result.resultRef.releasedReservationCount,
      releasedReservationUnits: result.resultRef.releasedReservationUnits,
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
}

interface ReplacementReservationResult {
  transferred: number;
  released: number;
  remaining: number;
}

function isCurrentActiveSubscription(
  issued: ReplacementIssuedRow,
  expectedVersion: number,
): boolean {
  return (
    issued.status === "active" && Number(issued.version) === expectedVersion
  );
}

function replacementObligationFactId(
  obligation: { id: string } | null,
): string | null {
  return obligation ? obligation.id : null;
}

function absolute(value: bigint): bigint {
  return value < 0n ? -value : value;
}

function reservationPlanWasApplied(
  result: ReplacementReservationResult,
  plan: {
    transferReservationIds: string[];
    releaseReservationIds: string[];
  },
): boolean {
  return (
    result.transferred === plan.transferReservationIds.length &&
    result.released === plan.releaseReservationIds.length &&
    result.remaining === 0
  );
}
