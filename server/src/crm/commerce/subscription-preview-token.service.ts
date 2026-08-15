import {
  Injectable,
  ServiceUnavailableException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  AccountAdjustmentReversalPreviewTokenPayload,
  LessonTransitionPreviewTokenPayload,
  SchedulePlanEndPreviewTokenPayload,
  PaymentReversalPreviewTokenPayload,
  PaymentCorrectionPreviewTokenPayload,
  signAccountAdjustmentReversalPreview,
  signLessonTransitionPreview,
  signPaymentReversalPreview,
  signPaymentCorrectionPreview,
  signSchedulePlanEndPreview,
  signSubscriptionCancelPreview,
  signSubscriptionPurchasePreview,
  signSubscriptionReplacePreview,
  SubscriptionCancelPreviewTokenPayload,
  SubscriptionPurchasePreviewTokenPayload,
  SubscriptionPreviewTokenError,
  SubscriptionReplacePreviewTokenPayload,
  verifyPaymentReversalPreview,
  verifyPaymentCorrectionPreview,
  verifyAccountAdjustmentReversalPreview,
  verifySchedulePlanEndPreview,
  verifyLessonTransitionPreview,
  verifySubscriptionCancelPreview,
  verifySubscriptionPurchasePreview,
  verifySubscriptionReplacePreview,
} from "./subscription-preview-token";

export const SUBSCRIPTION_PREVIEW_TTL_SECONDS = 300;

@Injectable()
export class SubscriptionPreviewTokenService {
  constructor(private readonly config: ConfigService) {}

  issue(
    payload: Omit<
      SubscriptionReplacePreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ): {
    token: string;
    expiresAt: string;
    payload: SubscriptionReplacePreviewTokenPayload;
  } {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: SubscriptionReplacePreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signSubscriptionReplacePreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verify(
    token: string,
    now = new Date(),
  ): SubscriptionReplacePreviewTokenPayload {
    try {
      return verifySubscriptionReplacePreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр замены устарел. Обновите расчёт."
            : "Подписанный предпросмотр замены недействителен.",
      });
    }
  }

  issueCancellation(
    payload: Omit<
      SubscriptionCancelPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ): {
    token: string;
    expiresAt: string;
    payload: SubscriptionCancelPreviewTokenPayload;
  } {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: SubscriptionCancelPreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signSubscriptionCancelPreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verifyCancellation(
    token: string,
    now = new Date(),
  ): SubscriptionCancelPreviewTokenPayload {
    try {
      return verifySubscriptionCancelPreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр отмены устарел. Обновите расчёт."
            : "Подписанный предпросмотр отмены недействителен.",
      });
    }
  }

  issuePurchase(
    payload: Omit<
      SubscriptionPurchasePreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ): {
    token: string;
    expiresAt: string;
    payload: SubscriptionPurchasePreviewTokenPayload;
  } {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: SubscriptionPurchasePreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signSubscriptionPurchasePreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verifyPurchase(
    token: string,
    now = new Date(),
  ): SubscriptionPurchasePreviewTokenPayload {
    try {
      return verifySubscriptionPurchasePreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр покупки устарел. Обновите расчёт."
            : "Подписанный предпросмотр покупки недействителен.",
      });
    }
  }

  issuePaymentReversal(
    payload: Omit<
      PaymentReversalPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ): {
    token: string;
    expiresAt: string;
    payload: PaymentReversalPreviewTokenPayload;
  } {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: PaymentReversalPreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signPaymentReversalPreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verifyPaymentReversal(
    token: string,
    now = new Date(),
  ): PaymentReversalPreviewTokenPayload {
    try {
      return verifyPaymentReversalPreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр удаления оплаты устарел. Обновите расчёт."
            : "Подписанный предпросмотр удаления оплаты недействителен.",
      });
    }
  }

  issuePaymentCorrection(
    payload: Omit<
      PaymentCorrectionPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ): {
    token: string;
    expiresAt: string;
    payload: PaymentCorrectionPreviewTokenPayload;
  } {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: PaymentCorrectionPreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signPaymentCorrectionPreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verifyPaymentCorrection(
    token: string,
    now = new Date(),
  ): PaymentCorrectionPreviewTokenPayload {
    try {
      return verifyPaymentCorrectionPreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр исправления оплаты устарел. Обновите расчёт."
            : "Подписанный предпросмотр исправления оплаты недействителен.",
      });
    }
  }

  issueAccountAdjustmentReversal(
    payload: Omit<
      AccountAdjustmentReversalPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ): {
    token: string;
    expiresAt: string;
    payload: AccountAdjustmentReversalPreviewTokenPayload;
  } {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: AccountAdjustmentReversalPreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signAccountAdjustmentReversalPreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verifyAccountAdjustmentReversal(
    token: string,
    now = new Date(),
  ): AccountAdjustmentReversalPreviewTokenPayload {
    try {
      return verifyAccountAdjustmentReversalPreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр сторно корректировки устарел. Обновите расчёт."
            : "Подписанный предпросмотр сторно корректировки недействителен.",
      });
    }
  }

  issueLessonTransition(
    payload: Omit<
      LessonTransitionPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ): {
    token: string;
    expiresAt: string;
    payload: LessonTransitionPreviewTokenPayload;
  } {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: LessonTransitionPreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signLessonTransitionPreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verifyLessonTransition(
    token: string,
    now = new Date(),
  ): LessonTransitionPreviewTokenPayload {
    try {
      return verifyLessonTransitionPreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр действия с занятием устарел. Обновите расчёт."
            : "Подписанный предпросмотр действия с занятием недействителен.",
      });
    }
  }

  issueSchedulePlanEnd(
    payload: Omit<
      SchedulePlanEndPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
    now = new Date(),
  ) {
    const issuedAtSeconds = Math.floor(now.getTime() / 1000);
    const complete: SchedulePlanEndPreviewTokenPayload = {
      ...payload,
      issuedAtSeconds,
      expiresAtSeconds: issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
    };
    return {
      token: signSchedulePlanEndPreview(this.secret(), complete),
      expiresAt: new Date(complete.expiresAtSeconds * 1000).toISOString(),
      payload: complete,
    };
  }

  verifySchedulePlanEnd(token: string, now = new Date()) {
    try {
      return verifySchedulePlanEndPreview(
        this.secret(),
        token,
        Math.floor(now.getTime() / 1000),
      );
    } catch (error) {
      if (!(error instanceof SubscriptionPreviewTokenError)) throw error;
      throw new UnprocessableEntityException({
        code: error.code,
        message:
          error.code === "PREVIEW_TOKEN_EXPIRED"
            ? "Предпросмотр завершения расписания устарел. Обновите расчёт."
            : "Подписанный предпросмотр завершения расписания недействителен.",
      });
    }
  }

  private secret(): string {
    const dedicated = this.config
      .get<string>("COMMERCE_PREVIEW_SECRET", "")
      .trim();
    const fallback = this.config.get<string>("JWT_ACCESS_SECRET", "").trim();
    const secret = dedicated || fallback;
    if (Buffer.byteLength(secret, "utf8") < 32) {
      throw new ServiceUnavailableException({
        code: "COMMERCE_PREVIEW_SECRET_MISSING",
        message: "Подписание предпросмотра замены не настроено.",
      });
    }
    return secret;
  }
}
