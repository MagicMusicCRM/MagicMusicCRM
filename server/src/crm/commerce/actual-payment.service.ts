import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "crypto";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CrmPolicy } from "../crm.policy";
import { RecordActualPaymentDto } from "../dto/record-actual-payment.dto";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import { CommerceMutationMetadata } from "./subscription-issue.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";

interface PaymentMutationResult extends Record<string, unknown> {
  entityId: string;
  version: number;
}

@Injectable()
export class ActualPaymentService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly commerce: CommerceProjectionRepository,
  ) {}

  async record(
    actor: ActorContext,
    studentId: string,
    dto: RecordActualPaymentDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const scope = await this.commerce.resolveStudentScope(actor, studentId);
    if (!scope.branchId) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_BRANCH_REQUIRED",
        field: "branchId",
        message: "Для платежа укажите филиал в карточке ученика.",
      });
    }
    if (dto.branchId !== undefined && dto.branchId !== scope.branchId) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_BRANCH_MISMATCH",
        field: "branchId",
        message: "Платёж можно провести только в филиале ученика.",
      });
    }
    const amountMinor = this.normalizeAmount(dto.amountMinor);
    const occurredAt = new Date(dto.occurredAt);
    if (Number.isNaN(occurredAt.getTime())) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_DATE_INVALID",
        field: "occurredAt",
        message: "Укажите корректную дату фактического платежа.",
      });
    }
    if (dto.method !== "cash" && dto.method !== "cashless") {
      throw new UnprocessableEntityException({
        code: "PAYMENT_METHOD_INVALID",
        field: "method",
        message: "Способ оплаты должен быть cash или cashless.",
      });
    }
    if (
      dto.currencyCode !== undefined &&
      !/^[A-Z]{3}$/.test(dto.currencyCode)
    ) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_CURRENCY_INVALID",
        field: "currencyCode",
        message: "Код валюты должен состоять из трёх заглавных букв.",
      });
    }
    const paymentId = this.deterministicId(
      actor.userId,
      metadata.idempotencyKey,
    );
    const comment = this.optionalText(dto.comment);
    const invoiceIdentifier = this.optionalText(dto.invoiceIdentifier);
    const normalizedPayload = {
      studentId,
      issuedSubscriptionId: dto.issuedSubscriptionId ?? null,
      branchId: scope.branchId,
      amountMinor,
      method: dto.method,
      occurredAt: occurredAt.toISOString(),
      currencyCode: dto.currencyCode ?? null,
      comment,
      invoiceIdentifier,
    };
    const audit: PlatformAuditInput = {
      action: "crm.actual_payment_recorded",
      entityType: "payment",
      entityId: paymentId,
      metadata: {
        studentId,
        issuedSubscriptionId: dto.issuedSubscriptionId ?? null,
        method: dto.method,
        branchId: scope.branchId,
      },
    };
    const result =
      await this.integrity.executeVersionedMutation<PaymentMutationResult>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        operation: "crm.actual-payment.record",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType: "commerce:actual-payment",
        aggregateId: paymentId,
        expectedVersion: 0,
        payload: normalizedPayload,
        audit,
        outbox: {
          type: "commerce.payment.recorded",
          payload: {
            entityId: paymentId,
            invalidates: ["student-finance", "revenue"],
          },
        },
        mutate: async (client, nextVersion) => {
          if (!(await this.repository.lockStudent(client, studentId))) {
            throw new NotFoundException("Ученик не найден.");
          }
          let currencyCode = dto.currencyCode ?? "RUB";
          if (dto.issuedSubscriptionId) {
            const target =
              await this.repository.findIssuedPaymentTargetForShare(
                client,
                dto.issuedSubscriptionId,
                studentId,
              );
            if (!target) {
              throw new NotFoundException(
                "Выданный абонемент этого ученика не найден.",
              );
            }
            if (
              dto.currencyCode !== undefined &&
              dto.currencyCode !== target.currency_code
            ) {
              throw new UnprocessableEntityException({
                code: "PAYMENT_CURRENCY_MISMATCH",
                field: "currencyCode",
                message:
                  "Валюта платежа должна совпадать с валютой выданного абонемента.",
              });
            }
            currencyCode = target.currency_code;
          }
          const payment = await this.repository.createActualPayment(client, {
            id: paymentId,
            studentId,
            issuedSubscriptionId: dto.issuedSubscriptionId ?? null,
            amountMinor,
            currencyCode,
            method: dto.method,
            occurredAt,
            actorUserId: actor.userId,
            branchId: scope.branchId,
            comment,
            invoiceIdentifier,
            idempotencyRef:
              `${actor.userId}:${metadata.idempotencyKey}`,
            requestFingerprint: fingerprintPayload({
              ...normalizedPayload,
              currencyCode,
            }),
          });
          audit.afterRef = {
            paymentId: payment.id,
            paymentVersion: nextVersion,
            studentId,
            issuedSubscriptionId: payment.issued_subscription_id,
          };
          return {
            entityId: payment.id,
            version: nextVersion,
          };
        },
      });
    return this.loadStablePayment(
      result.resultRef.entityId,
      result.resultRef.version,
    );
  }

  private async loadStablePayment(
    paymentId: string,
    paymentVersion: number,
  ) {
    const payment = await this.repository.findActualPayment(paymentId);
    if (!payment) {
      throw new ConflictException({
        code: "PAYMENT_RESULT_MISSING",
        message: "Зафиксированный фактический платёж не найден.",
        paymentId,
      });
    }
    return {
      payment: {
        id: payment.id,
        studentId: payment.student_id,
        issuedSubscriptionId: payment.issued_subscription_id,
        amountMinor: payment.amount_minor,
        currencyCode: payment.currency,
        method: payment.method,
        occurredAt: payment.payment_date,
        branchId: payment.branch_id,
        branchName: payment.branch_name,
        comment: payment.notes,
        invoiceIdentifier: payment.invoice_number,
        status: "paid",
        acceptedBy: {
          userId: payment.created_by,
          name: payment.created_by_name,
        },
        version: paymentVersion,
        createdAt: payment.created_at,
      },
    };
  }

  private normalizeAmount(raw: string): string {
    if (!/^[1-9]\d*$/.test(raw)) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_AMOUNT_INVALID",
        field: "amountMinor",
        message: "Сумма фактического платежа должна быть положительной.",
      });
    }
    const value = BigInt(raw);
    if (value > 999_999_999_999n) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_AMOUNT_OUT_OF_RANGE",
        field: "amountMinor",
        message: "Сумма платежа выходит за допустимый диапазон.",
      });
    }
    return value.toString();
  }

  private optionalText(raw: string | undefined): string | null {
    const value = raw?.trim();
    return value ? value : null;
  }

  private assertMetadata(metadata: CommerceMutationMetadata): void {
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
    idempotencyKey: string,
  ): string {
    const hex = createHash("sha256")
      .update(
        `${actorUserId}\0crm.actual-payment.record\0${idempotencyKey}`,
      )
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
