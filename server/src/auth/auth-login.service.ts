import { Injectable, UnauthorizedException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { AuthEmailChallengeService } from "./auth-email-challenge.service";
import {
  normalizeEmail,
  sha256,
  toAuthUserResponse,
} from "./auth-normalization";
import { AuthRateLimitService } from "./auth-rate-limit.service";
import { AuthUserResponse, UserRecord } from "./auth.types";
import { LoginDto } from "./dto/login.dto";
import { PasswordService } from "./password.service";
import { SessionService, TokenPair } from "./session.service";

@Injectable()
export class AuthLoginService {
  constructor(
    private readonly database: DatabaseService,
    private readonly passwordService: PasswordService,
    private readonly sessions: SessionService,
    private readonly rateLimits: AuthRateLimitService,
    private readonly challenges: AuthEmailChallengeService,
    private readonly audit: AuditService,
  ) {}

  async login(
    dto: LoginDto,
  ): Promise<{
    user: AuthUserResponse;
    session?: TokenPair;
    emailOtpRequired?: boolean;
  }> {
    const email = normalizeEmail(dto.email);
    const emailHash = sha256(email);
    await this.rateLimits.assertLoginAllowed(emailHash);
    const user = await this.authenticatePassword(dto, email, emailHash);
    await this.assertEmailVerified(user, emailHash);
    await this.recordPasswordLogin(user, emailHash);

    const otpRequired = this.isOtpRequired(user);
    if (otpRequired && !this.isOtpBypassed(email)) {
      return this.beginOtpLogin(user, email, emailHash);
    }
    if (otpRequired) await this.recordOtpBypass(user, emailHash);
    return this.issueSession(user);
  }

  async refresh(refreshToken: string): Promise<{ session: TokenPair }> {
    return { session: await this.sessions.rotate(refreshToken) };
  }

  async logoutAll(actor: ActorContext): Promise<{ success: true }> {
    await this.sessions.revokeAll(actor);
    return { success: true };
  }

  private async authenticatePassword(
    dto: LoginDto,
    email: string,
    emailHash: string,
  ): Promise<UserRecord> {
    const result = await this.database.query<UserRecord>(
      `
        select u.id,
               u.email,
               u.password_hash,
               u.role,
               u.email_verified_at,
               coalesce(p.email_otp_2fa_enabled, false) as email_otp_2fa_enabled
        from app.users u
        left join app.profiles p on p.user_id = u.id
        where lower(u.email) = lower($1)
          and u.deleted_at is null
          and u.is_app_account = true
        limit 1
      `,
      [email],
    );
    const user = result.rows[0];
    const verified =
      user?.password_hash &&
      (await this.passwordService.verify(dto.password, user.password_hash));
    if (user && verified) return user;

    await this.audit.record({
      action: "auth.login_failed",
      entityType: "user",
      metadata: { emailHash },
    });
    throw new UnauthorizedException("Неверная почта или пароль.");
  }

  private async assertEmailVerified(
    user: UserRecord,
    emailHash: string,
  ): Promise<void> {
    if (user.email_verified_at) return;
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.login_email_unverified",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash },
    });
    throw new UnauthorizedException("Подтвердите email перед входом.");
  }

  private async recordPasswordLogin(
    user: UserRecord,
    emailHash: string,
  ): Promise<void> {
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.login_password",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash },
    });
  }

  private isOtpRequired(user: UserRecord): boolean {
    return Boolean(user.email_otp_2fa_enabled) || isManagerOrAdminRole(user.role);
  }

  private isOtpBypassed(email: string): boolean {
    const raw = process.env.AUTH_OTP_BYPASS_EMAILS;
    if (!raw) return false;
    return raw
      .split(",")
      .map((entry) => entry.trim().toLowerCase())
      .filter((entry) => entry.length > 0)
      .includes(email.toLowerCase());
  }

  private async beginOtpLogin(
    user: UserRecord,
    email: string,
    emailHash: string,
  ): Promise<{ user: AuthUserResponse; emailOtpRequired: true }> {
    await this.challenges.createOtpChallenge(user, email, {
      requireDelivery: true,
    });
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.login_email_otp_required",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash },
    });
    return { user: toAuthUserResponse(user), emailOtpRequired: true };
  }

  private async recordOtpBypass(
    user: UserRecord,
    emailHash: string,
  ): Promise<void> {
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.login_otp_bypassed",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash },
    });
  }

  private async issueSession(
    user: UserRecord,
  ): Promise<{ user: AuthUserResponse; session: TokenPair }> {
    return {
      user: toAuthUserResponse(user),
      session: await this.sessions.issueForUser({
        id: user.id,
        email: user.email,
        role: user.role,
      }),
    };
  }
}
