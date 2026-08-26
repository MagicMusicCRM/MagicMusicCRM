import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { ActorContext } from "../../common/security/actor-context";
import { SubscriptionCancelCommandDto } from "../dto/subscription-cancel.dto";
import { SubscriptionReplaceCommandDto } from "../dto/subscription-replace.dto";
import {
  SubscriptionCancelPreviewTokenPayload,
  SubscriptionReplacePreviewTokenPayload,
} from "./subscription-preview-token";
import { SubscriptionLifecycleMutationMetadata } from "./subscription-lifecycle.types";

@Injectable()
export class SubscriptionLifecycleCommandPolicy {
  assertReplacementCommand(
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
    if (!dto.reason?.trim() || dto.reason.trim().length > 500) {
      throw new UnprocessableEntityException({
        code: "REPLACEMENT_REASON_REQUIRED",
        message: "Укажите причину замены абонемента.",
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

  assertCancellationCommand(
    dto: SubscriptionCancelCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ): void {
    if (dto.confirm !== true) {
      throw new UnprocessableEntityException({
        code: "CANCELLATION_CONFIRMATION_REQUIRED",
        message: "Подтвердите отмену после просмотра последствий.",
      });
    }
    if (!Number.isSafeInteger(dto.expectedVersion) || dto.expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_VERSION_REQUIRED",
        message: "Передайте актуальную версию абонемента.",
      });
    }
    if (!dto.reason?.trim() || dto.reason.trim().length > 500) {
      throw new UnprocessableEntityException({
        code: "CANCELLATION_REASON_REQUIRED",
        message: "Укажите причину отмены абонемента.",
      });
    }
    if (!/^(0|[1-9]\d*)$/.test(dto.refundMinor)) {
      throw new UnprocessableEntityException({
        code: "CANCELLATION_REFUND_INVALID",
        message: "Укажите сумму возврата в минимальных денежных единицах.",
      });
    }
    if (
      typeof dto.previewToken !== "string" ||
      dto.previewToken.length === 0 ||
      dto.previewToken.length > 16_384
    ) {
      throw new UnprocessableEntityException({
        code: "PREVIEW_TOKEN_INVALID",
        message: "Передайте подписанный предпросмотр отмены.",
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

  assertReplacementTokenBinding(
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

  assertCancellationTokenBinding(
    payload: SubscriptionCancelPreviewTokenPayload,
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

  assertStudentScope(
    context: { studentId: string },
    studentId: string,
  ): void {
    if (context.studentId !== studentId) {
      throw new NotFoundException("Выданный абонемент не найден.");
    }
  }

  deterministicId(
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
