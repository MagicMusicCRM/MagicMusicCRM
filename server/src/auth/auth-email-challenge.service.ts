import { Injectable, ServiceUnavailableException } from "@nestjs/common";
import { randomInt } from "node:crypto";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { otpHash, sha256 } from "./auth-normalization";
import { UserRecord } from "./auth.types";

@Injectable()
export class AuthEmailChallengeService {
  constructor(
    private readonly database: DatabaseService,
    private readonly notifications: NotificationsService,
    private readonly audit: AuditService,
  ) {}

  async createEmailVerificationChallenge(
    userId: string,
    email: string,
  ): Promise<void> {
    await this.createOtpChallenge(
      {
        id: userId,
        email,
        role: "client",
        password_hash: null,
        email_verified_at: null,
      },
      email,
    );
  }

  async createOtpChallenge(
    user: UserRecord,
    email: string,
    options: { requireDelivery?: boolean } = {},
  ): Promise<void> {
    const code = randomInt(100000, 1000000).toString();
    const challenge = await this.database.query<{ id: string }>(
      `
        insert into app.otp_challenges (
          user_id,
          email_hash,
          purpose,
          code_hash,
          expires_at
        )
        values ($1, $2, 'email_verification', $3, now() + interval '10 minutes')
        returning id
      `,
      [user.id, sha256(email), otpHash(email, code)],
    );
    const delivered = await this.safeEmail(
      user.id,
      "auth_otp",
      "Код подтверждения Magic Music",
      `Ваш код подтверждения: ${code}`,
      options.requireDelivery === true,
    );
    if (!options.requireDelivery || delivered) return;

    const challengeId = challenge.rows[0]?.id;
    if (challengeId) {
      await this.database.query(
        `update app.otp_challenges set consumed_at = now() where id = $1`,
        [challengeId],
      );
    }
    throw new ServiceUnavailableException({
      code: "OTP_DELIVERY_UNAVAILABLE",
      message:
        "Не удалось отправить код подтверждения. Попробуйте ещё раз через несколько минут.",
    });
  }

  async sendPasswordReset(user: UserRecord, token: string): Promise<void> {
    await this.safeEmail(
      user.id,
      "auth_password_reset",
      "Сброс пароля Magic Music",
      `Код для сброса пароля действует 30 минут: ${token}`,
    );
  }

  private async safeEmail(
    userId: string,
    template: string,
    title: string,
    body: string,
    requireDelivery = false,
  ): Promise<boolean> {
    try {
      const result = await this.notifications.sendEmail({
        userId,
        template,
        title,
        body,
        deliveryMode: requireDelivery ? "required" : "queued",
      });
      return result.queued && (!requireDelivery || result.delivered);
    } catch {
      await this.audit.record({
        actor: { userId, role: "client" },
        action: "notifications.email_enqueue_failed",
        entityType: "user",
        entityId: userId,
        metadata: { template },
      });
      return false;
    }
  }
}
