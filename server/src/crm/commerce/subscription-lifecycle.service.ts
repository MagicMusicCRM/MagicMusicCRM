import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import {
  SubscriptionReplaceCommandDto,
  SubscriptionReplacePreviewDto,
} from "../dto/subscription-replace.dto";
import { IssuedCommercialSnapshot } from "./commerce-schema.types";
import {
  ReplacementContext,
  ReplacementPackageRow,
  SubscriptionLifecycleRepository,
} from "./subscription-lifecycle.repository";
import {
  SubscriptionReplacePreviewTokenPayload,
} from "./subscription-preview-token";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";

export interface SubscriptionLifecycleMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface ReplacementResultRef extends Record<string, unknown> {
  sourceId: string;
  sourceVersion: number;
  resultId: string;
  resultVersion: number;
  newPackageId: string;
  newPackageVersion: number;
  usedUnits: string;
  transferredReservationCount: number;
  transferredReservationUnits: string;
  releasedReservationCount: number;
  releasedReservationUnits: string;
  deltaMinor: string;
  positionKind: "debt" | "overpayment" | "settled";
  positionMinor: string;
  ccy: string;
  obligationFactId: string | null;
}

interface ReplacementCalculation {
  deltaMinor: bigint;
  positionMinor: bigint;
  positionKind: "debt" | "overpayment" | "settled";
}

interface ReplacementReservationPlan {
  transferReservationIds: string[];
  releaseReservationIds: string[];
  transferredUnits: string;
  releasedUnits: string;
}

@Injectable()
export class SubscriptionLifecycleService {
  constructor(
    private readonly repository: SubscriptionLifecycleRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
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
    this.assertReplaceableContext(context);
    this.assertStudentScope(context, studentId);
    const tokenPayload = this.createTokenPayload(actor, context);
    const signed = this.previewTokens.issue(tokenPayload);
    const calculation = this.calculate(context);
    const reservationPlan = this.planReservations(context);
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
      warnings: this.replacementWarnings(context),
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
    this.assertCommand(dto, metadata);
    const newSubscriptionId = this.deterministicId(
      actor.userId,
      "crm.subscription.replace",
      metadata.idempotencyKey,
    );
    const audit: PlatformAuditInput = {
      action: "crm.subscription_replaced",
      entityType: "subscription",
      entityId: issuedSubscriptionId,
      reason: dto.reason,
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
          reason: dto.reason,
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

          // Verification deliberately lives inside the mutation callback:
          // completed idempotent replays do not fail merely because the
          // originally valid short-lived preview has since expired.
          const signedPayload = this.previewTokens.verify(dto.previewToken);
          this.assertTokenBinding(
            signedPayload,
            actor,
            studentId,
            issuedSubscriptionId,
            dto.expectedVersion,
          );
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
          this.assertReplaceableContext(context);
          this.assertStudentScope(context, studentId);
          this.assertPreviewStillCurrent(
            signedPayload,
            this.createTokenPayload(actor, context),
          );

          const calculation = this.calculate(context);
          const reservationPlan = this.planReservations(context);
          const snapshot = this.createReplacementSnapshot(
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
              studentId: context.studentId,
              issuedSubscriptionId: replacement.id,
              deltaMinor: calculation.deltaMinor,
              currencyCode: context.oldCurrencyCode,
            });
          await this.repository.createReplaceLifecycle(client, {
            oldIssuedSubscriptionId: issuedSubscriptionId,
            newIssuedSubscriptionId: replacement.id,
            actorUserId: actor.userId,
            reason: dto.reason,
          });
          const resultRef: ReplacementResultRef = {
            sourceId: issuedSubscriptionId,
            sourceVersion: nextVersion,
            resultId: replacement.id,
            resultVersion: 1,
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
    return {
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
  }

  private createTokenPayload(
    actor: ActorContext,
    context: ReplacementContext,
  ): Omit<
    SubscriptionReplacePreviewTokenPayload,
    "issuedAtSeconds" | "expiresAtSeconds"
  > {
    const calculation = this.calculate(context);
    const reservationPlan = this.planReservations(context);
    return {
      kind: "subscription.replace",
      actorUserId: actor.userId,
      studentId: context.studentId,
      issuedSubscriptionId: context.issuedSubscriptionId,
      expectedVersion: context.oldVersion,
      newPackageId: context.newPackage!.id,
      newPackageVersion: context.newPackage!.version,
      currencyCode: context.oldCurrencyCode,
      usedUnits: context.usedUnits,
      reservedLessonCount: context.reservedLessonCount,
      reservedUnits: context.reservedUnits,
      transferableReservationCount:
        reservationPlan.transferReservationIds.length,
      transferableReservationUnits: reservationPlan.transferredUnits,
      releasedReservationCount: reservationPlan.releaseReservationIds.length,
      releasedReservationUnits: reservationPlan.releasedUnits,
      reservationPlanFingerprint: fingerprintPayload({
        transfer: reservationPlan.transferReservationIds,
        release: reservationPlan.releaseReservationIds,
      }),
      futureLessonCount: context.futureLessonCount,
      futureUnits: context.futureUnits,
      oldFinalMinor: context.oldFinalPriceMinor,
      newFinalMinor: context.newPackage!.basePriceMinor,
      actualPaidMinor: context.actualPaidMinor,
      deltaMinor: calculation.deltaMinor.toString(),
      positionKind: calculation.positionKind,
      positionMinor: absolute(calculation.positionMinor).toString(),
    };
  }

  private assertReplaceableContext(
    context: ReplacementContext | null,
  ): asserts context is ReplacementContext & {
    newPackage: NonNullable<ReplacementContext["newPackage"]>;
  } {
    if (!context) {
      throw new NotFoundException("Выданный абонемент не найден.");
    }
    if (context.oldStatus !== "active") {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_NOT_ACTIVE",
        message: "Заменить можно только активный абонемент.",
        status: context.oldStatus,
      });
    }
    if (
      !context.newPackage ||
      !context.newPackage.active ||
      context.newPackage.deletedAt !== null
    ) {
      throw new NotFoundException(
        "Новый пакет не найден или находится в архиве.",
      );
    }
    if (context.oldCurrencyCode !== context.newPackage.currencyCode) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_CURRENCY_MISMATCH",
        message: "Замена между разными валютами не поддерживается.",
        oldCurrencyCode: context.oldCurrencyCode,
        newCurrencyCode: context.newPackage.currencyCode,
      });
    }
    if (
      unitsToHundredths(context.newPackage.unitCount) <
      unitsToHundredths(context.usedUnits)
    ) {
      throw new UnprocessableEntityException({
        code: "REPLACEMENT_VOLUME_BELOW_USED",
        message:
          "Объём нового пакета не может быть меньше уже использованного.",
        usedUnits: context.usedUnits,
        newUnitCount: context.newPackage.unitCount,
      });
    }
  }

  private calculate(context: ReplacementContext): ReplacementCalculation {
    const oldFinal = BigInt(context.oldFinalPriceMinor);
    const newFinal = BigInt(context.newPackage!.basePriceMinor);
    const paid = BigInt(context.actualPaidMinor);
    const positionMinor = newFinal - paid;
    return {
      deltaMinor: newFinal - oldFinal,
      positionMinor,
      positionKind:
        positionMinor > 0n
          ? "debt"
          : positionMinor < 0n
            ? "overpayment"
            : "settled",
    };
  }

  private planReservations(
    context: ReplacementContext,
  ): ReplacementReservationPlan {
    let remaining =
      unitsToHundredths(context.newPackage!.unitCount) -
      unitsToHundredths(context.usedUnits);
    let exhausted = false;
    let transferred = 0n;
    let released = 0n;
    const transferReservationIds: string[] = [];
    const releaseReservationIds: string[] = [];
    for (const reservation of context.reservedRows) {
      const units = unitsToHundredths(reservation.units);
      if (!exhausted && units <= remaining) {
        transferReservationIds.push(reservation.reservationId);
        transferred += units;
        remaining -= units;
      } else {
        exhausted = true;
        releaseReservationIds.push(reservation.reservationId);
        released += units;
      }
    }
    return {
      transferReservationIds,
      releaseReservationIds,
      transferredUnits: hundredthsToUnits(transferred),
      releasedUnits: hundredthsToUnits(released),
    };
  }

  private createReplacementSnapshot(
    oldIssuedSubscriptionId: string,
    context: ReplacementContext,
    packageRow: ReplacementPackageRow,
  ): IssuedCommercialSnapshot {
    return {
      snapshotVersion: 1,
      packageVersion: Number(packageRow.version),
      displayName: packageRow.name,
      unitCount: packageRow.lessons_total,
      validityDays: packageRow.validity_days,
      basePriceMinor: packageRow.base_price_minor,
      currencyCode: packageRow.currency_code,
      discount: { type: "none" },
      finalPriceMinor: packageRow.base_price_minor,
      installments: [],
      paymentMethod: null,
      commercialRules: {
        carriedUsedUnits: context.usedUnits,
        replacedFromSubscriptionId: oldIssuedSubscriptionId,
      },
    };
  }

  private assertTokenBinding(
    payload: SubscriptionReplacePreviewTokenPayload,
    actor: ActorContext,
    studentId: string,
    issuedSubscriptionId: string,
    expectedVersion: number,
  ): void {
    if (
      payload.actorUserId !== actor.userId ||
      payload.studentId !== studentId ||
      payload.issuedSubscriptionId !== issuedSubscriptionId ||
      payload.expectedVersion !== expectedVersion
    ) {
      throw new UnprocessableEntityException({
        code: "PREVIEW_TOKEN_SCOPE_MISMATCH",
        message: "Предпросмотр создан для другой операции или пользователя.",
      });
    }
  }

  private assertStudentScope(
    context: ReplacementContext,
    studentId: string,
  ): void {
    if (context.studentId !== studentId) {
      throw new NotFoundException("Выданный абонемент не найден.");
    }
  }

  private assertPreviewStillCurrent(
    signed: SubscriptionReplacePreviewTokenPayload,
    current: Omit<
      SubscriptionReplacePreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
  ): void {
    const {
      issuedAtSeconds: _issuedAtSeconds,
      expiresAtSeconds: _expiresAtSeconds,
      ...signedFacts
    } = signed;
    if (
      fingerprintPayload(signedFacts) !== fingerprintPayload(current)
    ) {
      throw new ConflictException({
        code: "REPLACEMENT_PREVIEW_STALE",
        message:
          "После предпросмотра изменились платежи, использование, резервы или пакет.",
      });
    }
  }

  private replacementWarnings(context: ReplacementContext) {
    const warnings: {
      code: string;
      count?: number;
      units?: string;
      message: string;
    }[] = [];
    if (unitsToHundredths(context.usedUnits) > 0n) {
      warnings.push({
        code: "USED_UNITS_TRANSFERRED",
        units: context.usedUnits,
        message: "Использованные единицы будут перенесены в новый абонемент.",
      });
    }
    if (context.futureLessonCount > 0) {
      warnings.push({
        code: "FUTURE_LESSONS_PRESERVED",
        count: context.futureLessonCount,
        units: context.futureUnits,
        message:
          "Будущие занятия сохранятся; существующие резервы будут перенесены.",
      });
    }
    const reservationPlan = this.planReservations(context);
    if (reservationPlan.releaseReservationIds.length > 0) {
      warnings.push({
        code: "RESERVATIONS_RELEASED_FOR_CAPACITY",
        count: reservationPlan.releaseReservationIds.length,
        units: reservationPlan.releasedUnits,
        message:
          "Не помещающиеся в новый объём резервы будут сняты; занятия сохранятся.",
      });
    }
    if (BigInt(context.actualPaidMinor) > 0n) {
      warnings.push({
        code: "ACTUAL_PAYMENTS_PRESERVED",
        message: "Фактические платежи останутся неизменными.",
      });
    }
    return warnings;
  }

  private assertCommand(
    dto: SubscriptionReplaceCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ): void {
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "REPLACEMENT_CONFIRMATION_REQUIRED",
        message: "Подтвердите замену после просмотра расчёта.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_VERSION_REQUIRED",
        message: "Передайте актуальную версию абонемента.",
      });
    }
    if (!/^[A-Za-z0-9._:-]{1,120}$/.test(dto.reason)) {
      throw new UnprocessableEntityException({
        code: "REPLACEMENT_REASON_REQUIRED",
        message: "Передайте безопасный код причины замены.",
      });
    }
    if (
      typeof dto.previewToken !== "string" ||
      dto.previewToken.length === 0 ||
      dto.previewToken.length > 16_384
    ) {
      throw new UnprocessableEntityException({
        code: "PREVIEW_TOKEN_INVALID",
        message: "Передайте подписанный предпросмотр замены.",
      });
    }
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new BadRequestException({
        code: "INVALID_IDEMPOTENCY_KEY",
        message: "Idempotency-Key должен содержать 8–160 безопасных символов.",
      });
    }
    if (
      !metadata.requestId ||
      metadata.requestId.length > 128 ||
      /[\r\n]/.test(metadata.requestId)
    ) {
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
