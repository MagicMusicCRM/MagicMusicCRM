import { BadRequestException, Injectable } from "@nestjs/common";
import { randomInt } from "node:crypto";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { AuthEmailChallengeService } from "./auth-email-challenge.service";
import {
  normalizeEmail,
  sha256,
  toAuthUserResponse,
} from "./auth-normalization";
import { AuthRateLimitService } from "./auth-rate-limit.service";
import { AcceptedResponse, AuthUserResponse, UserRecord } from "./auth.types";
import { PasswordService } from "./password.service";
import { SessionService } from "./session.service";

@Injectable()
export class AuthPasswordRecoveryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly passwordService: PasswordService,
    private readonly sessions: SessionService,
    private readonly rateLimits: AuthRateLimitService,
    private readonly challenges: AuthEmailChallengeService,
    private readonly audit: AuditService,
  ) {}

  async requestPasswordReset(emailInput: string): Promise<AcceptedResponse> {
    const email = normalizeEmail(emailInput);
    const user = await this.findUserByEmail(email);
    if (!user) return { accepted: true };

    if (await this.rateLimits.isResetRequestLimited(user.id)) {
      await this.audit.record({
        actor: { userId: user.id, role: user.role },
        action: "auth.password_reset_rate_limited",
        entityType: "user",
        entityId: user.id,
        metadata: { emailHash: sha256(email) },
      });
      return { accepted: true };
    }

    const token = randomInt(100000, 1000000).toString();
    await this.database.query(
      `
        insert into app.password_reset_tokens (user_id, token_hash, expires_at)
        values ($1, $2, now() + interval '30 minutes')
      `,
      [user.id, sha256(token)],
    );
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.password_reset_requested",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash: sha256(email) },
    });
    await this.challenges.sendPasswordReset(user, token);
    return { accepted: true };
  }

  async resetPassword(
    token: string,
    password: string,
    clientIp?: string,
  ): Promise<{ user: AuthUserResponse }> {
    const ipHash = sha256(clientIp ?? "unknown");
    await this.rateLimits.assertResetConfirmAllowed(ipHash);
    const passwordHash = await this.passwordService.hash(password);
    const passwordCiphertext =
      this.passwordService.encryptForManagedAccess(password);
    const result = await this.database.query<UserRecord>(
      `
        with reset_token as (
          update app.password_reset_tokens
          set consumed_at = now()
          where token_hash = $1
            and consumed_at is null
            and expires_at > now()
          returning user_id
        )
        update app.users
        set password_hash = $2,
            managed_password_ciphertext = case
              when app.users.role <> 'client'::app.user_role then $3
              else null end,
            password_changed_at = now(),
            updated_at = now()
        from reset_token
        where app.users.id = reset_token.user_id
          and app.users.deleted_at is null
          and app.users.is_app_account = true
        returning app.users.id,
                  app.users.email,
                  app.users.password_hash,
                  app.users.role,
                  app.users.email_verified_at
      `,
      [sha256(token), passwordHash, passwordCiphertext],
    );
    const user = result.rows[0];
    if (!user) {
      await this.audit.record({
        action: "auth.password_reset_failed",
        entityType: "user",
        metadata: { ipHash },
      });
      throw new BadRequestException(
        "Ссылка для сброса пароля недействительна или истекла.",
      );
    }

    await this.sessions.revokeAll({ userId: user.id, role: user.role });
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.password_reset_completed",
      entityType: "user",
      entityId: user.id,
    });
    return { user: toAuthUserResponse(user) };
  }

  private async findUserByEmail(
    email: string,
  ): Promise<UserRecord | undefined> {
    const result = await this.database.query<UserRecord>(
      `
        select id, email, password_hash, role, email_verified_at
        from app.users
        where lower(email) = lower($1)
          and deleted_at is null
          and is_app_account = true
        limit 1
      `,
      [email],
    );
    return result.rows[0];
  }
}
