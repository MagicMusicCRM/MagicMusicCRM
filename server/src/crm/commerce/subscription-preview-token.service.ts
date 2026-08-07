import {
  Injectable,
  ServiceUnavailableException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  signSubscriptionCancelPreview,
  signSubscriptionPurchasePreview,
  signSubscriptionReplacePreview,
  SubscriptionCancelPreviewTokenPayload,
  SubscriptionPurchasePreviewTokenPayload,
  SubscriptionPreviewTokenError,
  SubscriptionReplacePreviewTokenPayload,
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
      expiresAtSeconds:
        issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
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
      expiresAtSeconds:
        issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
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
      expiresAtSeconds:
        issuedAtSeconds + SUBSCRIPTION_PREVIEW_TTL_SECONDS,
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
