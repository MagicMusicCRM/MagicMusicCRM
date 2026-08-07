import {
  BadRequestException,
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
  PreviewPaymentReversalDto,
  ReversePaymentDto,
} from "../dto/payment-lifecycle.dto";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import {
  PaymentReversalRepository,
  PaymentReversalTargetRow,
} from "./payment-reversal.repository";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { CommerceMutationMetadata } from "./subscription-issue.service";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

interface PaymentReversalMutationResult extends Record<string, unknown> {
  entityId: string;
  paymentRecordId: string;
  version: number;
}

@Injectable()
export class PaymentReversalService {
  constructor(
    private readonly repository: PaymentReversalRepository,
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
    dto: PreviewPaymentReversalDto,
    now = new Date(),
  ) {
    this.policy.assertCanWriteCrm(actor);
    const scope = await this.projections.resolveStudentScope(actor, studentId);
    const target = await this.loadScopedTarget(
      actor,
      studentId,
      paymentRecordId,
    );
    this.assertReversible(target, dto.expectedVersion);
    const [source] = await this.projections.loadProjection(actor, [scope]);
    const walletBalanceMinor =
      source?.accounts.find(
        (account) => account.currencyCode === target.currency_code,
      )?.balanceMinor ?? "0";
    const walletDeltaMinor =
      target.status === "paid" ? `-${target.amount_minor}` : "0";
    const resultingBalanceMinor = (
      BigInt(walletBalanceMinor) + BigInt(walletDeltaMinor)
    ).toString();
    const signed = this.previewTokens.issuePaymentReversal(
      {
        kind: "payment.reversal",
        actorUserId: actor.userId,
        studentId,
        recipientStudentId: target.recipient_student_id,
        paymentRecordId,
        expectedVersion: Number(target.record_version),
        status: target.status,
        actualPaymentId: target.actual_payment_id,
        issuedSubscriptionId: target.issued_subscription_id,
        amountMinor: target.amount_minor,
        currencyCode: target.currency_code,
        walletBalanceMinor,
        resultingBalanceMinor,
      },
      now,
    );
    return {
      paymentRecordId,
      status: target.status,
      amountMinor: target.amount_minor,
      currencyCode: target.currency_code,
      walletDeltaMinor,
      walletBalanceMinor,
      resultingBalanceMinor,
      negativeBalanceWarning: BigInt(resultingBalanceMinor) < 0n,
      issuedSubscriptionId: target.issued_subscription_id,
      installmentId: target.installment_id,
      operation:
        target.status === "paid" ? "monetary_reversal" : "technical_void",
      previewToken: signed.token,
      expiresAt: signed.expiresAt,
    };
  }

  async reverse(
    actor: ActorContext,
    studentId: string,
    paymentRecordId: string,
    dto: ReversePaymentDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_REVERSAL_CONFIRMATION_REQUIRED",
        field: "confirm",
        message: "Подтвердите необратимое техническое удаление оплаты.",
      });
    }
    const reason = dto.reason.trim();
    if (!reason) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_REVERSAL_REASON_REQUIRED",
        field: "reason",
        message: "Укажите причину удаления оплаты.",
      });
    }
    const signed = this.previewTokens.verifyPaymentReversal(dto.previewToken);
    if (
      signed.actorUserId !== actor.userId ||
      signed.studentId !== studentId ||
      signed.paymentRecordId !== paymentRecordId
    ) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_REVERSAL_PREVIEW_MISMATCH",
        message: "Предпросмотр относится к другой оплате или сотруднику.",
      });
    }
    await this.projections.resolveStudentScope(actor, studentId);
    await this.projections.resolveStudentScope(
      actor,
      signed.recipientStudentId,
    );
    const auditId = randomUUID();
    const adjustmentId = randomUUID();
    const audit: PlatformAuditInput = {
      id: auditId,
      action: "crm.payment_reversed",
      entityType: "client_payment_record",
      entityId: paymentRecordId,
      reason: "payment_reversal",
      beforeRef: {
        status: signed.status,
        actualPaymentId: signed.actualPaymentId,
        amountMinor: signed.amountMinor,
        currencyCode: signed.currencyCode,
        walletBalanceMinor: signed.walletBalanceMinor,
      },
      metadata: {
        studentId,
        recipientStudentId: signed.recipientStudentId,
        issuedSubscriptionId: signed.issuedSubscriptionId,
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<PaymentReversalMutationResult>(
        {
          actorKey: actor.userId,
          actorUserId: actor.userId,
          operation: "crm.payment-reversal.commit",
          idempotencyKey: metadata.idempotencyKey,
          requestId: metadata.requestId,
          aggregateType: "commerce:payment-reversal",
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
            type: "commerce.payment.reversed",
            payload: {
              entityId: paymentRecordId,
              studentId,
              invalidates: ["student-finance", "revenue", "reports"],
            },
          },
          mutate: async (client, nextVersion) => {
            const students = await this.issueRepository.lockPurchaseStudents(
              client,
              actor,
              [studentId, signed.recipientStudentId],
            );
            if (students.length !== new Set([
              studentId,
              signed.recipientStudentId,
            ]).size) {
              throw new NotFoundException("Клиент не найден.");
            }
            const target = await this.repository.lockTarget(
              client,
              paymentRecordId,
            );
            if (!target || target.payer_student_id !== studentId) {
              throw new NotFoundException("Оплата не найдена.");
            }
            this.assertSignedTarget(target, signed);
            const currentBalance = await this.issueRepository.readAccountBalance(
              client,
              studentId,
              signed.currencyCode,
            );
            if (currentBalance !== signed.walletBalanceMinor) {
              throw new ConflictException({
                code: "PAYMENT_REVERSAL_PREVIEW_STALE",
                message: "Баланс изменился. Обновите предпросмотр удаления.",
              });
            }
            let counterpartId: string | null = null;
            if (target.status === "paid") {
              const adjustment =
                await this.issueRepository.createPaymentAdjustment(client, {
                  id: adjustmentId,
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
                  idempotencyRef:
                    `${actor.userId}:reversal:${metadata.idempotencyKey}`,
                  requestFingerprint: fingerprintPayload({
                    paymentRecordId,
                    actualPaymentId: target.actual_payment_id,
                    amountMinor: target.amount_minor,
                    reason,
                  }),
                });
              counterpartId = adjustment.id;
            }
            const sourceKind = target.actual_payment_id
              ? "payment" as const
              : "payment_record" as const;
            const sourceId = target.actual_payment_id ?? target.payment_record_id;
            const exclusionId = await this.repository.createExclusion(client, {
              sourceKind,
              sourceId,
              counterpartId,
              reason,
              actorUserId: actor.userId,
              auditEventId: auditId,
            });
            audit.afterRef = {
              exclusionId,
              sourceKind,
              sourceId,
              counterpartId,
              resultingBalanceMinor: signed.resultingBalanceMinor,
            };
            return {
              entityId: exclusionId,
              paymentRecordId,
              version: nextVersion,
            };
          },
        },
      );
    const reversal = await this.repository.findResult(paymentRecordId);
    if (!reversal) {
      throw new ConflictException({
        code: "PAYMENT_REVERSAL_RESULT_MISSING",
        message: "Результат удаления оплаты не найден.",
      });
    }
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId: signed.recipientStudentId,
        payerStudentId: studentId,
        subscriptionId: signed.issuedSubscriptionId,
      });
    }
    return {
      paymentRecordId,
      operation:
        reversal.status === "paid" ? "monetary_reversal" : "technical_void",
      exclusion: {
        id: reversal.exclusion_id,
        sourceKind: reversal.source_kind,
        sourceId: reversal.source_id,
        counterpartKind: reversal.counterpart_kind,
        counterpartId: reversal.counterpart_id,
        reason: reversal.reason,
        actorUserId: reversal.actor_user_id,
        actorName: reversal.actor_name,
        auditEventId: reversal.audit_event_id,
        occurredAt: new Date(reversal.occurred_at).toISOString(),
      },
      replayed: result.replayed,
    };
  }

  private async loadScopedTarget(
    actor: ActorContext,
    studentId: string,
    paymentRecordId: string,
  ): Promise<PaymentReversalTargetRow> {
    await this.projections.resolveStudentScope(actor, studentId);
    const target = await this.repository.findTarget(paymentRecordId);
    if (!target || target.payer_student_id !== studentId) {
      throw new NotFoundException("Оплата не найдена.");
    }
    await this.projections.resolveStudentScope(
      actor,
      target.recipient_student_id,
    );
    return target;
  }

  private assertReversible(
    target: PaymentReversalTargetRow,
    expectedVersion: number,
  ): void {
    if (target.exclusion_id) {
      throw new ConflictException({
        code: "PAYMENT_ALREADY_REVERSED",
        message: "Оплата уже удалена из обычного учёта.",
      });
    }
    if (Number(target.record_version) !== expectedVersion) {
      throw new ConflictException({
        code: "PAYMENT_REVERSAL_VERSION_STALE",
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
        code: "PAYMENT_REVERSAL_LINK_INVALID",
        message: "Связь подтверждённой оплаты повреждена.",
      });
    }
    if (Number(target.linked_adjustment_count) > 0) {
      throw new ConflictException({
        code: "PAYMENT_REVERSAL_HAS_ADJUSTMENTS",
        message:
          "У оплаты уже есть возврат или корректировка. Сначала урегулируйте связанные операции.",
      });
    }
  }

  private assertSignedTarget(
    target: PaymentReversalTargetRow,
    signed: ReturnType<SubscriptionPreviewTokenService["verifyPaymentReversal"]>,
  ): void {
    this.assertReversible(target, signed.expectedVersion);
    if (
      target.recipient_student_id !== signed.recipientStudentId ||
      target.status !== signed.status ||
      target.actual_payment_id !== signed.actualPaymentId ||
      target.issued_subscription_id !== signed.issuedSubscriptionId ||
      target.amount_minor !== signed.amountMinor ||
      target.currency_code !== signed.currencyCode
    ) {
      throw new ConflictException({
        code: "PAYMENT_REVERSAL_PREVIEW_STALE",
        message: "Оплата изменилась. Обновите предпросмотр удаления.",
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
