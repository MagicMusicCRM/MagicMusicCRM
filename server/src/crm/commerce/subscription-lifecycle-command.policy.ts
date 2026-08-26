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
    this.assertConfirmation(
      dto.confirm,
      "REPLACEMENT_CONFIRMATION_REQUIRED",
      "Подтвердите замену после просмотра расчёта.",
    );
    this.assertExpectedVersion(dto.expectedVersion);
    this.assertReason(
      dto.reason,
      "REPLACEMENT_REASON_REQUIRED",
      "Укажите причину замены абонемента.",
    );
    this.assertPreviewToken(
      dto.previewToken,
      "Передайте подписанный предпросмотр замены.",
    );
    this.assertMetadata(metadata);
  }

  assertCancellationCommand(
    dto: SubscriptionCancelCommandDto,
    metadata: SubscriptionLifecycleMutationMetadata,
  ): void {
    this.assertConfirmation(
      dto.confirm,
      "CANCELLATION_CONFIRMATION_REQUIRED",
      "Подтвердите отмену после просмотра последствий.",
    );
    this.assertExpectedVersion(dto.expectedVersion);
    this.assertReason(
      dto.reason,
      "CANCELLATION_REASON_REQUIRED",
      "Укажите причину отмены абонемента.",
    );
    if (!/^(0|[1-9]\d*)$/.test(dto.refundMinor)) {
      throw new UnprocessableEntityException({
        code: "CANCELLATION_REFUND_INVALID",
        message: "Укажите сумму возврата в минимальных денежных единицах.",
      });
    }
    this.assertPreviewToken(
      dto.previewToken,
      "Передайте подписанный предпросмотр отмены.",
    );
    this.assertMetadata(metadata);
  }

  private assertConfirmation(
    confirm: boolean,
    code: string,
    message: string,
  ): void {
    if (confirm !== true) {
      throw new UnprocessableEntityException({ code, message });
    }
  }

  private assertExpectedVersion(expectedVersion: number): void {
    if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 1) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_VERSION_REQUIRED",
        message: "Передайте актуальную версию абонемента.",
      });
    }
  }

  private assertReason(reason: string, code: string, message: string): void {
    if (!reason?.trim() || reason.trim().length > 500) {
      throw new UnprocessableEntityException({ code, message });
    }
  }

  private assertPreviewToken(previewToken: string, message: string): void {
    if (
      typeof previewToken !== "string" ||
      previewToken.length === 0 ||
      previewToken.length > 16_384
    ) {
      throw new UnprocessableEntityException({
        code: "PREVIEW_TOKEN_INVALID",
        message,
      });
    }
  }

  private assertMetadata(
    metadata: SubscriptionLifecycleMutationMetadata,
  ): void {
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
