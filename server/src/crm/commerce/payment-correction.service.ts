import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import {
  CorrectPaymentDto,
  PreviewPaymentCorrectionDto,
} from "../dto/payment-lifecycle.dto";
import { ClientPaymentStatus } from "./commerce-schema.types";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import {
  PaymentLifecycleRepository,
  PaymentTargetRow,
} from "./payment-lifecycle.repository";
import {
  PaymentReversalRepository,
  PaymentReversalTargetRow,
} from "./payment-reversal.repository";
import { CommerceMutationMetadata } from "./subscription-issue.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

interface PaymentCorrectionMutationResult extends Record<string, unknown> {
  entityId: string;
  sourcePaymentRecordId: string;
  replacementPaymentRecordId: string;
  recipientStudentId: string;
  issuedSubscriptionId: string | null;
}

@Injectable()
export class PaymentCorrectionService {
  constructor(
    private readonly reversalRepository: PaymentReversalRepository,
    private readonly paymentRepository: PaymentLifecycleRepository,
    private readonly issueRepository: SubscriptionIssueRepository,
    private readonly projections: CommerceProjectionRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  async preview(
    actor: ActorContext,
    studentId: string,
    paymentRecordId: string,
    dto: PreviewPaymentCorrectionDto,
    now = new Date(),
  ) {
    this.policy.assertCanWriteCrm(actor);
    const scope = await this.projections.resolveStudentScope(actor, studentId);
    const target = await this.loadScopedTarget(
      actor,
      studentId,
      paymentRecordId,
    );
    this.assertCorrectable(target, dto.expectedVersion);
    const normalized = this.normalize(dto);
    this.assertBranch(scope.branchId, normalized.branchId, normalized.status);
    this.assertInstallmentAmount(target, normalized.amountMinor);
    this.assertChanged(target, normalized);

    const [projection] = await this.projections.loadProjection(actor, [scope]);
    const walletBalanceMinor =
      projection?.accounts.find(
        (account) => account.currencyCode === target.currency_code,
      )?.balanceMinor ?? "0";
    const walletDeltaMinor =
      target.issued_subscription_id === null
        ? (
            (normalized.status === "paid"
              ? BigInt(normalized.amountMinor)
              : 0n) -
            (target.status === "paid" ? BigInt(target.amount_minor) : 0n)
          ).toString()
        : "0";
    const resultingBalanceMinor = (
      BigInt(walletBalanceMinor) + BigInt(walletDeltaMinor)
    ).toString();
    const signed = this.previewTokens.issuePaymentCorrection(
      {
        kind: "payment.correction",
        actorUserId: actor.userId,
        studentId,
        recipientStudentId: target.recipient_student_id,
        paymentRecordId,
        expectedVersion: Number(target.record_version),
        oldStatus: target.status,
        oldActualPaymentId: target.actual_payment_id,
        issuedSubscriptionId: target.issued_subscription_id,
        installmentId: target.installment_id,
        oldAmountMinor: target.amount_minor,
        currencyCode: target.currency_code,
        amountMinor: normalized.amountMinor,
        status: normalized.status,
        dueAt: normalized.dueAt?.toISOString() ?? null,
        method: normalized.method,
        externalIdentifier: normalized.externalIdentifier,
        occurredAt: normalized.occurredAt?.toISOString() ?? null,
        branchId: normalized.branchId,
        verificationNote: normalized.verificationNote,
        walletBalanceMinor,
        resultingBalanceMinor,
      },
      now,
    );
    return {
      paymentRecordId,
      expectedVersion: Number(target.record_version),
      currencyCode: target.currency_code,
      before: {
        amountMinor: target.amount_minor,
        status: target.status,
        dueAt: dateIso(target.record_due_at),
        method:
          target.status === "paid"
            ? target.payment_method
            : target.record_method,
        externalIdentifier:
          target.status === "paid"
            ? target.payment_invoice_number
            : target.record_external_identifier,
        occurredAt:
          target.status === "paid" ? dateIso(target.payment_date) : null,
        branchId: target.status === "paid" ? target.payment_branch_id : null,
        verificationNote: target.record_verification_note,
      },
      after: {
        amountMinor: normalized.amountMinor,
        status: normalized.status,
        dueAt: normalized.dueAt?.toISOString() ?? null,
        method: normalized.method,
        externalIdentifier: normalized.externalIdentifier,
        occurredAt: normalized.occurredAt?.toISOString() ?? null,
        branchId: normalized.branchId,
        verificationNote: normalized.verificationNote,
      },
      walletDeltaMinor,
      walletBalanceMinor,
      resultingBalanceMinor,
      negativeBalanceWarning: BigInt(resultingBalanceMinor) < 0n,
      issuedSubscriptionId: target.issued_subscription_id,
      installmentId: target.installment_id,
      previewToken: signed.token,
      expiresAt: signed.expiresAt,
    };
  }

  async correct(
    actor: ActorContext,
    studentId: string,
    paymentRecordId: string,
    dto: CorrectPaymentDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const reason = dto.reason?.trim();
    if (!reason || reason.length > 500) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_CORRECTION_REASON_REQUIRED",
        field: "reason",
        message: "Укажите причину исправления оплаты.",
      });
    }
    const signed = this.previewTokens.verifyPaymentCorrection(dto.previewToken);
    if (
      dto.confirm !== true ||
      signed.actorUserId !== actor.userId ||
      signed.studentId !== studentId ||
      signed.paymentRecordId !== paymentRecordId
    ) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_CORRECTION_PREVIEW_MISMATCH",
        message: "Предпросмотр относится к другой оплате или сотруднику.",
      });
    }
    const scope = await this.projections.resolveStudentScope(actor, studentId);
    await this.projections.resolveStudentScope(
      actor,
      signed.recipientStudentId,
    );
    this.assertBranch(scope.branchId, signed.branchId, signed.status);

    const correctionId = deterministicId(
      actor.userId,
      "crm.payment-correction.fact",
      metadata.idempotencyKey,
    );
    const replacementRecordId = deterministicId(
      actor.userId,
      "crm.payment-correction.replacement",
      metadata.idempotencyKey,
    );
    const replacementPaymentId =
      signed.status === "paid"
        ? deterministicId(
            actor.userId,
            "crm.payment-correction.actual",
            metadata.idempotencyKey,
          )
        : null;
    const reversalAdjustmentId =
      signed.oldStatus === "paid"
        ? deterministicId(
            actor.userId,
            "crm.payment-correction.reversal",
            metadata.idempotencyKey,
          )
        : null;
    const auditId = randomUUID();
    const audit: PlatformAuditInput = {
      id: auditId,
      action: "crm.payment_corrected",
      entityType: "client_payment_record",
      entityId: paymentRecordId,
      reason: "payment_correction",
      reasonText: reason,
      beforeRef: {
        paymentRecordId,
        version: signed.expectedVersion,
        status: signed.oldStatus,
        amountMinor: signed.oldAmountMinor,
      },
      metadata: {
        studentId,
        recipientStudentId: signed.recipientStudentId,
        issuedSubscriptionId: signed.issuedSubscriptionId,
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<PaymentCorrectionMutationResult>(
        {
          actorKey: actor.userId,
          actorUserId: actor.userId,
          authorization: {
            actor,
            capabilityKey: "commerce.client_finance.write",
          },
          operation: "crm.payment-correction.commit",
          idempotencyKey: metadata.idempotencyKey,
          requestId: metadata.requestId,
          aggregateType: "commerce:payment-correction",
          aggregateId: paymentRecordId,
          expectedVersion: 0,
          payload: {
            studentId,
            paymentRecordId,
            previewToken: dto.previewToken,
            reason,
          },
          audit,
          outbox: {
            type: "commerce.payment-record.corrected",
            payload: {
              entityId: paymentRecordId,
              replacementPaymentRecordId: replacementRecordId,
              invalidates: ["student-finance", "revenue", "reports"],
            },
          },
          mutate: async (client) => {
            const students = await this.issueRepository.lockPurchaseStudents(
              client,
              actor,
              [studentId, signed.recipientStudentId],
            );
            if (
              students.length !==
              new Set([studentId, signed.recipientStudentId]).size
            ) {
              throw new NotFoundException("Клиент не найден.");
            }
            const target = await this.reversalRepository.lockTarget(
              client,
              paymentRecordId,
            );
            if (!target || target.payer_student_id !== studentId) {
              throw new NotFoundException("Оплата не найдена.");
            }
            this.assertSignedTarget(target, signed);
            const currentBalance =
              await this.issueRepository.readAccountBalance(
                client,
                studentId,
                signed.currencyCode,
              );
            if (currentBalance !== signed.walletBalanceMinor) {
              throw new ConflictException({
                code: "PAYMENT_CORRECTION_PREVIEW_STALE",
                message: "Баланс изменился. Обновите расчёт исправления.",
              });
            }

            if (reversalAdjustmentId) {
              await this.issueRepository.createPaymentAdjustment(client, {
                id: reversalAdjustmentId,
                studentId,
                sourcePaymentId: target.actual_payment_id!,
                kind: "adjustment",
                amountMinor: `-${target.amount_minor}`,
                currencyCode: target.currency_code,
                occurredAt: new Date(),
                reason,
                branchId: target.payment_branch_id,
                method: target.payment_method,
                invoiceNumber: target.payment_invoice_number,
                actorUserId: actor.userId,
                idempotencyRef: `${actor.userId}:correction-reversal:${metadata.idempotencyKey}`,
                requestFingerprint: fingerprintPayload({
                  paymentRecordId,
                  actualPaymentId: target.actual_payment_id,
                  amountMinor: target.amount_minor,
                  reason,
                }),
              });
            }
            await this.reversalRepository.createExclusion(client, {
              sourceKind: target.actual_payment_id
                ? "payment"
                : "payment_record",
              sourceId: target.actual_payment_id ?? target.payment_record_id,
              counterpartId: reversalAdjustmentId,
              reason,
              actorUserId: actor.userId,
              auditEventId: auditId,
            });

            const paymentTarget = await this.resolveTarget(
              client,
              studentId,
              signed.issuedSubscriptionId,
              signed.installmentId,
            );
            this.assertTarget(paymentTarget, signed);
            if (replacementPaymentId) {
              await this.issueRepository.createActualPayment(client, {
                id: replacementPaymentId,
                studentId,
                issuedSubscriptionId: signed.issuedSubscriptionId,
                amountMinor: signed.amountMinor,
                currencyCode: signed.currencyCode,
                method: signed.method!,
                occurredAt: new Date(signed.occurredAt!),
                actorUserId: actor.userId,
                branchId: signed.branchId,
                comment: signed.verificationNote,
                invoiceIdentifier: signed.externalIdentifier,
                idempotencyRef: `${actor.userId}:correction-payment:${metadata.idempotencyKey}`,
                requestFingerprint: fingerprintPayload({
                  sourcePaymentRecordId: paymentRecordId,
                  amountMinor: signed.amountMinor,
                  status: signed.status,
                  occurredAt: signed.occurredAt,
                }),
              });
            }
            const replacement = await this.paymentRepository.createRecord(
              client,
              {
                id: replacementRecordId,
                studentId,
                issuedSubscriptionId: signed.issuedSubscriptionId,
                installmentId: signed.installmentId,
                amountMinor: signed.amountMinor,
                currencyCode: signed.currencyCode,
                status: signed.status,
                dueAt: signed.dueAt ? new Date(signed.dueAt) : null,
                method: signed.method,
                externalIdentifier: signed.externalIdentifier,
                verificationNote: signed.verificationNote ?? reason,
                actualPaymentId: replacementPaymentId,
                version: 1,
                createdBy: actor.userId,
                verifiedBy: replacementPaymentId ? actor.userId : null,
                verifiedAt: replacementPaymentId ? new Date() : null,
              },
            );
            if (replacementPaymentId) {
              await this.paymentRepository.linkActualPayment(
                client,
                replacementPaymentId,
                replacement.id,
              );
            }
            await this.paymentRepository.appendStatusEvent(client, {
              paymentRecordId: replacement.id,
              beforeStatus: null,
              afterStatus: replacement.status,
              reason,
              actorUserId: actor.userId,
              aggregateVersion: 1,
              actualPaymentId: replacementPaymentId,
            });
            await this.paymentRepository.initializeRecordAggregate(
              client,
              replacement.id,
            );
            await this.reversalRepository.createCorrection(client, {
              id: correctionId,
              sourcePaymentRecordId: paymentRecordId,
              replacementPaymentRecordId: replacement.id,
              reversalAdjustmentId,
              reason,
              actorUserId: actor.userId,
              auditEventId: auditId,
            });
            audit.afterRef = {
              correctionId,
              replacementPaymentRecordId: replacement.id,
              replacementActualPaymentId: replacementPaymentId,
              status: replacement.status,
              amountMinor: replacement.amount_minor,
              resultingBalanceMinor: signed.resultingBalanceMinor,
            };
            return {
              entityId: correctionId,
              sourcePaymentRecordId: paymentRecordId,
              replacementPaymentRecordId: replacement.id,
              recipientStudentId: signed.recipientStudentId,
              issuedSubscriptionId: signed.issuedSubscriptionId,
            };
          },
        },
      );
    const correction = await this.reversalRepository.findCorrection(
      result.resultRef.sourcePaymentRecordId,
    );
    const replacement = await this.paymentRepository.findRecord(
      result.resultRef.replacementPaymentRecordId,
    );
    if (!correction || !replacement) {
      throw new ConflictException({
        code: "PAYMENT_CORRECTION_RESULT_MISSING",
        message: "Результат исправления оплаты не найден.",
      });
    }
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId: result.resultRef.recipientStudentId,
        payerStudentId: studentId,
        subscriptionId: result.resultRef.issuedSubscriptionId,
      });
    }
    return {
      correction: {
        id: correction.correction_id,
        sourcePaymentRecordId: correction.source_payment_record_id,
        replacementPaymentRecordId: correction.replacement_payment_record_id,
        reversalAdjustmentId: correction.reversal_adjustment_id,
        reason: correction.reason,
        occurredAt: new Date(correction.occurred_at).toISOString(),
      },
      replacement: {
        id: replacement.id,
        amountMinor: replacement.amount_minor,
        currencyCode: replacement.currency_code,
        status: replacement.status,
        version: Number(replacement.version),
      },
      resultingBalanceMinor: signed.resultingBalanceMinor,
      replayed: result.replayed,
      auditId: result.auditId,
      eventId: result.eventId,
    };
  }

  private async loadScopedTarget(
    actor: ActorContext,
    studentId: string,
    paymentRecordId: string,
  ): Promise<PaymentReversalTargetRow> {
    const target = await this.reversalRepository.findTarget(paymentRecordId);
    if (!target || target.payer_student_id !== studentId) {
      throw new NotFoundException("Оплата не найдена.");
    }
    await this.projections.resolveStudentScope(
      actor,
      target.recipient_student_id,
    );
    return target;
  }

  private async resolveTarget(
    client: Parameters<PaymentLifecycleRepository["lockRecord"]>[0],
    studentId: string,
    issuedSubscriptionId: string | null,
    installmentId: string | null,
  ): Promise<PaymentTargetRow | null> {
    if (installmentId) {
      return this.paymentRepository.lockInstallmentTarget(
        client,
        studentId,
        installmentId,
        issuedSubscriptionId ?? undefined,
      );
    }
    if (issuedSubscriptionId) {
      return this.paymentRepository.lockSubscriptionTarget(
        client,
        studentId,
        issuedSubscriptionId,
      );
    }
    return null;
  }

  private assertCorrectable(
    target: PaymentReversalTargetRow,
    expectedVersion: number,
  ): void {
    if (target.exclusion_id) {
      throw new ConflictException({
        code: "PAYMENT_ALREADY_REVERSED",
        message: "Оплата уже исключена из обычного учёта.",
      });
    }
    if (Number(target.record_version) !== expectedVersion) {
      throw new ConflictException({
        code: "PAYMENT_CORRECTION_VERSION_STALE",
        message: "Оплата изменилась. Обновите карточку.",
      });
    }
    if (
      target.status === "paid" &&
      (!target.actual_payment_id ||
        target.payment_student_id !== target.payer_student_id ||
        target.payment_amount_minor !== target.amount_minor ||
        target.payment_currency_code !== target.currency_code)
    ) {
      throw new ConflictException({
        code: "PAYMENT_CORRECTION_LINK_INVALID",
        message: "Связь подтверждённой оплаты повреждена.",
      });
    }
    if (Number(target.linked_adjustment_count) > 0) {
      throw new ConflictException({
        code: "PAYMENT_CORRECTION_HAS_ADJUSTMENTS",
        message:
          "У оплаты уже есть возврат или корректировка. Сначала урегулируйте связанные операции.",
      });
    }
  }

  private assertSignedTarget(
    target: PaymentReversalTargetRow,
    signed: ReturnType<
      SubscriptionPreviewTokenService["verifyPaymentCorrection"]
    >,
  ): void {
    this.assertCorrectable(target, signed.expectedVersion);
    if (
      target.recipient_student_id !== signed.recipientStudentId ||
      target.status !== signed.oldStatus ||
      target.actual_payment_id !== signed.oldActualPaymentId ||
      target.issued_subscription_id !== signed.issuedSubscriptionId ||
      target.installment_id !== signed.installmentId ||
      target.amount_minor !== signed.oldAmountMinor ||
      target.currency_code !== signed.currencyCode
    ) {
      throw new ConflictException({
        code: "PAYMENT_CORRECTION_PREVIEW_STALE",
        message: "Оплата изменилась. Обновите расчёт исправления.",
      });
    }
  }

  private assertInstallmentAmount(
    target: PaymentReversalTargetRow,
    amountMinor: string,
  ): void {
    if (target.installment_id && amountMinor !== target.amount_minor) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENT_PAYMENT_AMOUNT_MISMATCH",
        field: "amountMinor",
        message: "Сумма части рассрочки меняется через пересчёт абонемента.",
      });
    }
  }

  private assertTarget(
    target: PaymentTargetRow | null,
    signed: ReturnType<
      SubscriptionPreviewTokenService["verifyPaymentCorrection"]
    >,
  ): void {
    if ((signed.issuedSubscriptionId || signed.installmentId) && !target) {
      throw new NotFoundException("Абонемент или часть рассрочки не найдены.");
    }
    if (target && target.currency_code !== signed.currencyCode) {
      throw new ConflictException({
        code: "PAYMENT_CORRECTION_TARGET_CHANGED",
        message: "Назначение оплаты изменилось. Обновите расчёт.",
      });
    }
    if (target?.installment_id && target.amount_minor !== signed.amountMinor) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENT_PAYMENT_AMOUNT_MISMATCH",
        field: "amountMinor",
        message: "Сумма части рассрочки меняется через пересчёт абонемента.",
      });
    }
    if (target?.existing_payment_record_id) {
      throw new ConflictException({
        code: "INSTALLMENT_PAYMENT_RECORD_EXISTS",
        message: "Для этой части рассрочки уже есть другая оплата.",
      });
    }
  }

  private normalize(dto: PreviewPaymentCorrectionDto) {
    const amountMinor = positiveMinor(dto.amountMinor);
    const method = dto.method ?? null;
    const externalIdentifier = optionalText(dto.externalIdentifier);
    const verificationNote = optionalText(dto.verificationNote);
    let occurredAt: Date | null = null;
    if (dto.status === "paid") {
      if (method !== "cash" && method !== "cashless") {
        throw new UnprocessableEntityException({
          code: "PAYMENT_METHOD_REQUIRED",
          field: "method",
          message: "Для оплаченной операции укажите способ оплаты.",
        });
      }
      if (!externalIdentifier) {
        throw new UnprocessableEntityException({
          code: "PAYMENT_EXTERNAL_IDENTIFIER_REQUIRED",
          field: "externalIdentifier",
          message: "Для оплаченной операции укажите номер операции или чека.",
        });
      }
      if (!dto.occurredAt) {
        throw new UnprocessableEntityException({
          code: "PAYMENT_DATE_REQUIRED",
          field: "occurredAt",
          message: "Для оплаченной операции укажите дату поступления.",
        });
      }
      occurredAt = validDate(dto.occurredAt, "occurredAt");
    }
    return {
      amountMinor,
      status: dto.status,
      dueAt: dto.dueAt ? validDate(dto.dueAt, "dueAt") : occurredAt,
      method,
      externalIdentifier,
      occurredAt,
      branchId: dto.status === "paid" ? (dto.branchId ?? null) : null,
      verificationNote,
    };
  }

  private assertBranch(
    actualBranchId: string | null,
    requestedBranchId: string | null,
    status: ClientPaymentStatus,
  ): void {
    if (status === "paid" && !actualBranchId) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_BRANCH_REQUIRED",
        field: "branchId",
        message: "Для оплаты укажите филиал в карточке ученика.",
      });
    }
    if (status === "paid" && requestedBranchId !== actualBranchId) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_BRANCH_MISMATCH",
        field: "branchId",
        message: "Оплату можно провести только в филиале ученика.",
      });
    }
  }

  private assertChanged(
    target: PaymentReversalTargetRow,
    normalized: ReturnType<PaymentCorrectionService["normalize"]>,
  ): void {
    const oldMethod =
      target.status === "paid" ? target.payment_method : target.record_method;
    const oldExternal =
      target.status === "paid"
        ? target.payment_invoice_number
        : target.record_external_identifier;
    const oldOccurredAt =
      target.status === "paid" ? dateIso(target.payment_date) : null;
    const oldBranchId =
      target.status === "paid" ? target.payment_branch_id : null;
    if (
      target.amount_minor === normalized.amountMinor &&
      target.status === normalized.status &&
      dateIso(target.record_due_at) ===
        (normalized.dueAt?.toISOString() ?? null) &&
      oldMethod === normalized.method &&
      oldExternal === normalized.externalIdentifier &&
      oldOccurredAt === (normalized.occurredAt?.toISOString() ?? null) &&
      oldBranchId === normalized.branchId &&
      target.record_verification_note === normalized.verificationNote
    ) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_CORRECTION_NO_CHANGES",
        message: "Измените хотя бы одно поле оплаты.",
      });
    }
  }

  private assertMetadata(metadata: CommerceMutationMetadata): void {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new BadRequestException({
        code: "IDEMPOTENCY_KEY_REQUIRED",
        message: "Укажите корректный Idempotency-Key.",
      });
    }
    if (!metadata.requestId.trim() || metadata.requestId.length > 200) {
      throw new BadRequestException({
        code: "REQUEST_ID_REQUIRED",
        message: "Укажите корректный X-Request-Id.",
      });
    }
  }
}

function positiveMinor(raw: string): string {
  if (!/^[1-9]\d*$/.test(raw) || BigInt(raw) > 999_999_999_999n) {
    throw new UnprocessableEntityException({
      code: "PAYMENT_AMOUNT_INVALID",
      field: "amountMinor",
      message: "Сумма оплаты должна быть положительной.",
    });
  }
  return BigInt(raw).toString();
}

function optionalText(raw: string | undefined): string | null {
  return raw?.trim() || null;
}

function validDate(raw: string, field: string): Date {
  const value = new Date(raw);
  if (Number.isNaN(value.getTime())) {
    throw new UnprocessableEntityException({
      code: "PAYMENT_DATE_INVALID",
      field,
      message: "Укажите корректную дату оплаты.",
    });
  }
  return value;
}

function dateIso(raw: Date | string | null): string | null {
  if (raw === null) return null;
  return new Date(raw).toISOString();
}

function deterministicId(
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
