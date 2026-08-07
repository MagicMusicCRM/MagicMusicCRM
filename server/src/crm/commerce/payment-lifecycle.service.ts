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
  CreatePaymentRecordDto,
  TransitionPaymentRecordDto,
} from "../dto/payment-lifecycle.dto";
import { ClientPaymentStatus } from "./commerce-schema.types";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import {
  PaymentLifecycleRepository,
  PaymentRecordRow,
  PaymentTargetRow,
} from "./payment-lifecycle.repository";
import { CommerceMutationMetadata } from "./subscription-issue.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionReservationService } from "./subscription-reservation.service";

interface PaymentRecordMutationResult extends Record<string, unknown> {
  entityId: string;
  version: number;
}

@Injectable()
export class PaymentLifecycleService {
  constructor(
    private readonly repository: PaymentLifecycleRepository,
    private readonly issueRepository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly commerce: CommerceProjectionRepository,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  async create(
    actor: ActorContext,
    studentId: string,
    dto: CreatePaymentRecordDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const scope = await this.commerce.resolveStudentScope(actor, studentId);
    this.assertBranch(scope.branchId, dto.branchId, dto.status);
    let recipientStudentId = studentId;
    if (dto.issuedSubscriptionId || dto.installmentId) {
      const target = await this.repository.findRecordTarget(
        studentId,
        dto.issuedSubscriptionId,
        dto.installmentId,
      );
      if (!target) throw new NotFoundException("Абонемент или платёж не найден.");
      recipientStudentId = target.recipient_student_id;
      await this.commerce.resolveStudentScope(actor, recipientStudentId);
    }
    const normalized = this.normalizeCreate(dto);
    const recordId = deterministicId(
      actor.userId,
      "crm.payment-record.create",
      metadata.idempotencyKey,
    );
    const actualPaymentId =
      dto.status === "paid"
        ? deterministicId(
            actor.userId,
            "crm.payment-record.actual",
            metadata.idempotencyKey,
          )
        : null;
    const audit: PlatformAuditInput = {
      action: "crm.payment_record_created",
      entityType: "client_payment_record",
      entityId: recordId,
      reason: "payment_record_create",
      metadata: {
        studentId,
        issuedSubscriptionId: dto.issuedSubscriptionId ?? null,
        installmentId: dto.installmentId ?? null,
        status: dto.status,
      },
      reasonText: normalized.reason,
    };
    const result =
      await this.integrity.executeVersionedMutation<PaymentRecordMutationResult>(
        {
          actorKey: actor.userId,
          actorUserId: actor.userId,
          authorization: {
            actor,
            capabilityKey: "commerce.client_finance.write",
          },
          operation: "crm.payment-record.create",
          idempotencyKey: metadata.idempotencyKey,
          requestId: metadata.requestId,
          aggregateType: "commerce:client-payment",
          aggregateId: recordId,
          expectedVersion: 0,
          payload: {
            studentId,
            ...normalized,
            issuedSubscriptionId: dto.issuedSubscriptionId ?? null,
            installmentId: dto.installmentId ?? null,
          },
          audit,
          outbox: {
            type: "commerce.payment-record.changed",
            payload: {
              entityId: recordId,
              status: dto.status,
              invalidates: ["student-finance", "revenue"],
            },
          },
          mutate: async (client, nextVersion) => {
            const students = await this.issueRepository.lockPurchaseStudents(
              client,
              actor,
              [studentId, recipientStudentId],
            );
            if (students.length !== new Set([
              studentId,
              recipientStudentId,
            ]).size) {
              throw new NotFoundException("Клиент не найден.");
            }
            const target = await this.resolveTarget(
              client,
              studentId,
              dto.issuedSubscriptionId,
              dto.installmentId,
            );
            this.assertTarget(normalized, target, dto);
            const currencyCode =
              target?.currency_code ?? normalized.currencyCode;
            if (!currencyCode) {
              throw new UnprocessableEntityException({
                code: "PAYMENT_CURRENCY_REQUIRED",
                field: "currencyCode",
                message: "Укажите валюту оплаты.",
              });
            }
            if (actualPaymentId) {
              await this.issueRepository.createActualPayment(client, {
                id: actualPaymentId,
                studentId,
                issuedSubscriptionId:
                  target?.issued_subscription_id ??
                  dto.issuedSubscriptionId ??
                  null,
                amountMinor: normalized.amountMinor,
                currencyCode,
                method: normalized.method!,
                occurredAt: normalized.occurredAt!,
                actorUserId: actor.userId,
                branchId: scope.branchId!,
                comment: normalized.verificationNote,
                invoiceIdentifier: normalized.externalIdentifier,
                idempotencyRef: `${actor.userId}:${metadata.idempotencyKey}`,
                requestFingerprint: fingerprintPayload({
                  recordId,
                  ...normalized,
                }),
              });
            }
            const record = await this.repository.createRecord(client, {
              id: recordId,
              studentId,
              issuedSubscriptionId:
                target?.issued_subscription_id ??
                dto.issuedSubscriptionId ??
                null,
              installmentId:
                target?.installment_id ?? dto.installmentId ?? null,
              amountMinor: normalized.amountMinor,
              currencyCode,
              status: dto.status,
              dueAt: normalized.dueAt,
              method: normalized.method,
              externalIdentifier: normalized.externalIdentifier,
              verificationNote: normalized.verificationNote,
              actualPaymentId,
              version: nextVersion,
              createdBy: actor.userId,
              verifiedBy: actualPaymentId ? actor.userId : null,
              verifiedAt: actualPaymentId ? new Date() : null,
            });
            if (actualPaymentId) {
              await this.repository.linkActualPayment(
                client,
                actualPaymentId,
                record.id,
              );
            }
            await this.repository.appendStatusEvent(client, {
              paymentRecordId: record.id,
              beforeStatus: null,
              afterStatus: record.status,
              reason: normalized.reason,
              actorUserId: actor.userId,
              aggregateVersion: nextVersion,
              actualPaymentId,
            });
            audit.afterRef = {
              paymentRecordId: record.id,
              version: nextVersion,
              status: record.status,
              actualPaymentId,
            };
            return { entityId: record.id, version: nextVersion };
          },
        },
      );
    const response = await this.loadStableResult(
      result.resultRef.entityId,
      result.resultRef.version,
    );
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId: recipientStudentId,
        payerStudentId: studentId,
        subscriptionId: response.paymentRecord.issuedSubscriptionId,
      });
    }
    return response;
  }

  async transition(
    actor: ActorContext,
    studentId: string,
    paymentRecordId: string,
    dto: TransitionPaymentRecordDto,
    metadata: CommerceMutationMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const scope = await this.commerce.resolveStudentScope(actor, studentId);
    this.assertBranch(scope.branchId, dto.branchId, dto.targetStatus);
    const scopedRecord = await this.repository.findRecord(paymentRecordId);
    if (!scopedRecord || scopedRecord.student_id !== studentId) {
      throw new NotFoundException("Оплата не найдена.");
    }
    this.assertNotVoided(scopedRecord);
    const recipientStudentId =
      scopedRecord.recipient_student_id ?? scopedRecord.student_id;
    await this.commerce.resolveStudentScope(actor, recipientStudentId);
    const reason = requiredText(
      dto.reason,
      "PAYMENT_TRANSITION_REASON_REQUIRED",
      "reason",
      "Укажите причину изменения статуса оплаты.",
    );
    const paid = this.normalizePaidFields(dto.targetStatus, dto);
    const actualPaymentId =
      dto.targetStatus === "paid"
        ? deterministicId(
            actor.userId,
            "crm.payment-record.transition.actual",
            metadata.idempotencyKey,
          )
        : null;
    const audit: PlatformAuditInput = {
      action: "crm.payment_record_transitioned",
      entityType: "client_payment_record",
      entityId: paymentRecordId,
      reason: "payment_record_transition",
      metadata: { studentId, targetStatus: dto.targetStatus },
      reasonText: reason,
    };
    const result =
      await this.integrity.executeVersionedMutation<PaymentRecordMutationResult>(
        {
          actorKey: actor.userId,
          actorUserId: actor.userId,
          authorization: {
            actor,
            capabilityKey: "commerce.client_finance.write",
          },
          operation: "crm.payment-record.transition",
          idempotencyKey: metadata.idempotencyKey,
          requestId: metadata.requestId,
          aggregateType: "commerce:client-payment",
          aggregateId: paymentRecordId,
          expectedVersion: dto.expectedVersion,
          payload: { studentId, paymentRecordId, ...dto, reason },
          audit,
          outbox: {
            type: "commerce.payment-record.changed",
            payload: {
              entityId: paymentRecordId,
              status: dto.targetStatus,
              invalidates: ["student-finance", "revenue"],
            },
          },
          mutate: async (client, nextVersion) => {
            const students = await this.issueRepository.lockPurchaseStudents(
              client,
              actor,
              [studentId, recipientStudentId],
            );
            if (students.length !== new Set([
              studentId,
              recipientStudentId,
            ]).size) {
              throw new NotFoundException("Клиент не найден.");
            }
            const current = await this.repository.lockRecord(
              client,
              studentId,
              paymentRecordId,
            );
            if (!current) {
              throw new NotFoundException("Оплата не найдена.");
            }
            this.assertNotVoided(current);
            this.assertTransition(current, dto);
            if (actualPaymentId) {
              await this.issueRepository.createActualPayment(client, {
                id: actualPaymentId,
                studentId,
                issuedSubscriptionId: current.issued_subscription_id,
                amountMinor: current.amount_minor,
                currencyCode: current.currency_code,
                method: paid.method!,
                occurredAt: paid.occurredAt!,
                actorUserId: actor.userId,
                branchId: scope.branchId!,
                comment: paid.verificationNote,
                invoiceIdentifier: paid.externalIdentifier,
                idempotencyRef: `${actor.userId}:${metadata.idempotencyKey}`,
                requestFingerprint: fingerprintPayload({
                  paymentRecordId,
                  expectedVersion: dto.expectedVersion,
                  ...paid,
                }),
              });
            }
            const updated = await this.repository.transitionRecord(client, {
              id: current.id,
              expectedVersion: dto.expectedVersion,
              nextVersion,
              targetStatus: dto.targetStatus,
              method: paid.method,
              externalIdentifier: paid.externalIdentifier,
              verificationNote: paid.verificationNote ?? reason,
              actualPaymentId,
              verifiedBy: actualPaymentId ? actor.userId : null,
              verifiedAt: actualPaymentId ? new Date() : null,
            });
            if (!updated) {
              throw new ConflictException({
                code: "PAYMENT_RECORD_VERSION_CONFLICT",
                message: "Статус оплаты уже изменился.",
              });
            }
            if (actualPaymentId) {
              await this.repository.linkActualPayment(
                client,
                actualPaymentId,
                updated.id,
              );
            }
            await this.repository.appendStatusEvent(client, {
              paymentRecordId: updated.id,
              beforeStatus: current.status,
              afterStatus: updated.status,
              reason,
              actorUserId: actor.userId,
              aggregateVersion: nextVersion,
              actualPaymentId,
            });
            audit.beforeRef = {
              paymentRecordId,
              version: Number(current.version),
              status: current.status,
            };
            audit.afterRef = {
              paymentRecordId,
              version: nextVersion,
              status: updated.status,
              actualPaymentId,
            };
            return { entityId: updated.id, version: nextVersion };
          },
        },
      );
    const response = await this.loadStableResult(
      result.resultRef.entityId,
      result.resultRef.version,
    );
    if (!result.replayed) {
      await this.reservations.publishPostCommit({
        studentId: recipientStudentId,
        payerStudentId: studentId,
        subscriptionId: response.paymentRecord.issuedSubscriptionId,
      });
    }
    return response;
  }

  async loadStableResult(paymentRecordId: string, version?: number) {
    const record = await this.repository.findRecord(paymentRecordId);
    if (!record) {
      throw new ConflictException({
        code: "PAYMENT_RECORD_RESULT_MISSING",
        message: "Зафиксированная оплата не найдена.",
      });
    }
    const [events, actualPayment] = await Promise.all([
      this.repository.listStatusEvents(paymentRecordId),
      record.actual_payment_id
        ? this.issueRepository.findActualPayment(record.actual_payment_id)
        : null,
    ]);
    return {
      paymentRecord: mapRecord(record, version),
      statusHistory: events.map((event) => ({
        id: event.id,
        beforeStatus: event.before_status,
        afterStatus: event.after_status,
        reason: event.reason,
        actor: {
          userId: event.actor_user_id,
          name: event.actor_name ?? null,
        },
        version: Number(event.aggregate_version),
        actualPaymentId: event.actual_payment_id,
        occurredAt: event.occurred_at,
      })),
      actualPayment: actualPayment
        ? {
            id: actualPayment.id,
            studentId: actualPayment.student_id,
            issuedSubscriptionId: actualPayment.issued_subscription_id,
            amountMinor: actualPayment.amount_minor,
            currencyCode: actualPayment.currency,
            method: actualPayment.method,
            occurredAt: actualPayment.payment_date,
            branchId: actualPayment.branch_id,
            branchName: actualPayment.branch_name,
            comment: actualPayment.notes,
            invoiceIdentifier: actualPayment.invoice_number,
            status: "paid" as const,
            acceptedBy: {
              userId: actualPayment.created_by,
              name: actualPayment.created_by_name,
            },
            version: 1,
            createdAt: actualPayment.created_at,
          }
        : null,
    };
  }

  private async resolveTarget(
    client: Parameters<PaymentLifecycleRepository["lockRecord"]>[0],
    studentId: string,
    issuedSubscriptionId?: string,
    installmentId?: string,
  ): Promise<PaymentTargetRow | null> {
    if (installmentId) {
      const target = await this.repository.lockInstallmentTarget(
        client,
        studentId,
        installmentId,
        issuedSubscriptionId,
      );
      if (!target) throw new NotFoundException("Платёж рассрочки не найден.");
      return target;
    }
    if (issuedSubscriptionId) {
      const target = await this.repository.lockSubscriptionTarget(
        client,
        studentId,
        issuedSubscriptionId,
      );
      if (!target) throw new NotFoundException("Абонемент не найден.");
      return target;
    }
    return null;
  }

  private assertTarget(
    normalized: ReturnType<PaymentLifecycleService["normalizeCreate"]>,
    target: PaymentTargetRow | null,
    dto: CreatePaymentRecordDto,
  ): void {
    if (
      target &&
      normalized.currencyCode &&
      normalized.currencyCode !== target.currency_code
    ) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_CURRENCY_MISMATCH",
        field: "currencyCode",
        message: "Валюта оплаты не совпадает с валютой абонемента.",
      });
    }
    if (
      target?.installment_id &&
      normalized.amountMinor !== target.amount_minor
    ) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENT_PAYMENT_AMOUNT_MISMATCH",
        field: "amountMinor",
        message: "Сумма оплаты должна совпадать с частью рассрочки.",
      });
    }
    if (dto.installmentId && !target?.installment_id) {
      throw new NotFoundException("Платёж рассрочки не найден.");
    }
    if (target?.existing_payment_record_id) {
      throw new ConflictException({
        code: "INSTALLMENT_PAYMENT_RECORD_EXISTS",
        message: "Для этой части рассрочки оплата уже зафиксирована.",
      });
    }
  }

  private assertTransition(
    current: PaymentRecordRow,
    dto: TransitionPaymentRecordDto,
  ): void {
    if (Number(current.version) !== dto.expectedVersion) {
      throw new ConflictException({
        code: "PAYMENT_RECORD_VERSION_CONFLICT",
        message: "Статус оплаты уже изменился.",
      });
    }
    const allowed =
      (current.status === "posted_pending" &&
        ["paid", "unpaid"].includes(dto.targetStatus)) ||
      (current.status === "unpaid" &&
        ["paid", "posted_pending"].includes(dto.targetStatus));
    if (!allowed) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_STATUS_TRANSITION_INVALID",
        field: "targetStatus",
        message: "Этот переход статуса оплаты недоступен.",
      });
    }
  }

  private normalizeCreate(dto: CreatePaymentRecordDto) {
    const amountMinor = positiveMinor(dto.amountMinor);
    if (dto.currencyCode && !/^[A-Z]{3}$/.test(dto.currencyCode)) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_CURRENCY_INVALID",
        field: "currencyCode",
        message: "Укажите трёхбуквенный код валюты.",
      });
    }
    const reason = requiredText(
      dto.reason,
      "PAYMENT_REASON_REQUIRED",
      "reason",
      "Укажите причину добавления оплаты.",
    );
    const paid = this.normalizePaidFields(dto.status, dto);
    const dueAt = dto.dueAt
      ? validDate(dto.dueAt, "dueAt")
      : paid.occurredAt;
    return {
      amountMinor,
      currencyCode: dto.currencyCode ?? null,
      status: dto.status,
      dueAt,
      method: paid.method,
      externalIdentifier: paid.externalIdentifier,
      occurredAt: paid.occurredAt,
      verificationNote: optionalText(dto.verificationNote) ?? reason,
      reason,
    };
  }

  private normalizePaidFields(
    status: ClientPaymentStatus,
    dto: Pick<
      CreatePaymentRecordDto,
      "method" | "externalIdentifier" | "occurredAt" | "verificationNote"
    >,
  ) {
    const method = dto.method ?? null;
    const externalIdentifier = optionalText(dto.externalIdentifier);
    const verificationNote = optionalText(dto.verificationNote);
    if (status !== "paid") {
      return {
        method,
        externalIdentifier,
        occurredAt: null,
        verificationNote,
      };
    }
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
    return {
      method,
      externalIdentifier,
      occurredAt: validDate(dto.occurredAt, "occurredAt"),
      verificationNote,
    };
  }

  private assertBranch(
    actualBranchId: string | null,
    requestedBranchId: string | undefined,
    status: ClientPaymentStatus,
  ): void {
    if (status === "paid" && actualBranchId === null) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_BRANCH_REQUIRED",
        field: "branchId",
        message: "Для оплаты укажите филиал в карточке ученика.",
      });
    }
    if (
      requestedBranchId !== undefined &&
      requestedBranchId !== actualBranchId
    ) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_BRANCH_MISMATCH",
        field: "branchId",
        message: "Оплату можно провести только в филиале ученика.",
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

  private assertNotVoided(record: PaymentRecordRow): void {
    if (record.exclusion_id) {
      throw new ConflictException({
        code: "PAYMENT_ALREADY_REVERSED",
        message: "Оплата уже удалена из обычного учёта.",
      });
    }
  }
}

function mapRecord(record: PaymentRecordRow, version?: number) {
  return {
    id: record.id,
    studentId: record.student_id,
    issuedSubscriptionId: record.issued_subscription_id,
    installmentId: record.installment_id,
    amountMinor: record.amount_minor,
    currencyCode: record.currency_code,
    status: record.status,
    dueAt: record.due_at,
    method: record.method,
    externalIdentifier: record.external_identifier,
    verificationNote: record.verification_note,
    actualPaymentId: record.actual_payment_id,
    version: version ?? Number(record.version),
    createdBy: {
      userId: record.created_by,
      name: record.created_by_name ?? null,
    },
    verifiedBy: {
      userId: record.verified_by,
      name: record.verified_by_name ?? null,
    },
    verifiedAt: record.verified_at,
    subscriptionName: record.subscription_name ?? null,
    recipientStudentId:
      record.recipient_student_id ?? record.student_id,
    createdAt: record.created_at,
    updatedAt: record.updated_at,
  };
}

function positiveMinor(raw: string): string {
  if (!/^[1-9]\d*$/.test(raw)) {
    throw new UnprocessableEntityException({
      code: "PAYMENT_AMOUNT_INVALID",
      field: "amountMinor",
      message: "Сумма оплаты должна быть положительной.",
    });
  }
  const amount = BigInt(raw);
  if (amount > 999_999_999_999n) {
    throw new UnprocessableEntityException({
      code: "PAYMENT_AMOUNT_OUT_OF_RANGE",
      field: "amountMinor",
      message: "Сумма оплаты выходит за допустимый диапазон.",
    });
  }
  return amount.toString();
}

function requiredText(
  raw: string,
  code: string,
  field: string,
  message: string,
): string {
  const value = raw?.trim();
  if (!value || value.length > 500) {
    throw new UnprocessableEntityException({ code, field, message });
  }
  return value;
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
