import { BadRequestException, HttpException, HttpStatus, Injectable } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { isManagerOrAdminRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { AuthEmailChallengeService } from "./auth-email-challenge.service";
import {
  normalizeEmail,
  otpHash,
  sha256,
  toAuthUserResponse,
} from "./auth-normalization";
import { AuthRateLimitService } from "./auth-rate-limit.service";
import { AcceptedResponse, AuthUserResponse, UserRecord } from "./auth.types";
import { SessionService, TokenPair } from "./session.service";

@Injectable()
export class AuthVerificationService {
  constructor(
    private readonly database: DatabaseService,
    private readonly sessions: SessionService,
    private readonly rateLimits: AuthRateLimitService,
    private readonly challenges: AuthEmailChallengeService,
    private readonly audit: AuditService,
  ) {}

  async requestOtp(emailInput: string): Promise<AcceptedResponse> {
    const email = normalizeEmail(emailInput);
    const emailHash = sha256(email);
    const user = await this.findUserByEmail(email);
    if (!user) return { accepted: true };

    if (await this.rateLimits.isOtpRequestLimited(emailHash)) {
      await this.audit.record({
        actor: { userId: user.id, role: user.role },
        action: "auth.otp_rate_limited",
        entityType: "user",
        entityId: user.id,
        metadata: { emailHash },
      });
      throw new HttpException(
        "Слишком много попыток. Попробуйте позже.",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    await this.challenges.createOtpChallenge(user, email);
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.otp_requested",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash },
    });
    return { accepted: true };
  }

  async verifyOtp(
    emailInput: string,
    code: string,
  ): Promise<{ user: AuthUserResponse; session?: TokenPair }> {
    const email = normalizeEmail(emailInput);
    const emailHash = sha256(email);
    await this.rateLimits.assertOtpVerifyAllowed(emailHash);
    const result = await this.database.query<UserRecord>(
      `
        with challenge as (
          update app.otp_challenges
          set consumed_at = now()
          where email_hash = $1
            and purpose = 'email_verification'
            and code_hash = $2
            and consumed_at is null
            and expires_at > now()
          returning user_id
        ),
        updated as (
          update app.users
          set email_verified_at = coalesce(email_verified_at, now()),
              is_app_account = true,
              updated_at = now()
          from challenge
          where app.users.id = challenge.user_id
            and lower(app.users.email) = lower($3)
            and app.users.deleted_at is null
            and app.users.is_app_account = true
          returning app.users.id,
                    app.users.email,
                    app.users.password_hash,
                    app.users.role,
                    app.users.email_verified_at
        )
        select updated.id,
               updated.email,
               updated.password_hash,
               updated.role,
               updated.email_verified_at,
               coalesce(p.email_otp_2fa_enabled, false) as email_otp_2fa_enabled
        from updated
        left join app.profiles p on p.user_id = updated.id
      `,
      [emailHash, otpHash(email, code), email],
    );
    const user = result.rows[0];
    if (!user) {
      await this.audit.record({
        action: "auth.otp_verify_failed",
        entityType: "user",
        metadata: { emailHash },
      });
      throw new BadRequestException(
        "Код подтверждения недействителен или истек.",
      );
    }

    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.otp_verified",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash },
    });
    if (
      Boolean(user.email_otp_2fa_enabled) ||
      isManagerOrAdminRole(user.role)
    ) {
      return {
        user: toAuthUserResponse(user),
        session: await this.sessions.issueForUser({
          id: user.id,
          email: user.email,
          role: user.role,
        }),
      };
    }
    return { user: toAuthUserResponse(user) };
  }

  async verifyEmail(token: string): Promise<{ user: AuthUserResponse }> {
    const result = await this.database.query<UserRecord>(
      `
        with token_row as (
          update app.email_verification_tokens
          set consumed_at = now()
          where token_hash = $1
            and consumed_at is null
            and expires_at > now()
          returning user_id
        )
        update app.users
        set email_verified_at = coalesce(email_verified_at, now()),
            updated_at = now()
        from token_row
        where app.users.id = token_row.user_id
          and app.users.is_app_account = true
        returning app.users.id,
                  app.users.email,
                  app.users.password_hash,
                  app.users.role,
                  app.users.email_verified_at
      `,
      [sha256(token)],
    );
    const user = result.rows[0];
    if (!user) {
      throw new BadRequestException(
        "Код подтверждения недействителен или истек.",
      );
    }

    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.email_verified",
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
