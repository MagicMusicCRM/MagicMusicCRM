import { HttpException, HttpStatus, Injectable } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CountRecord } from "./auth.types";

@Injectable()
export class AuthRateLimitService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
  ) {}

  async assertLoginAllowed(emailHash: string): Promise<void> {
    await this.assertAuthAttemptAllowed(
      emailHash,
      "auth.login_failed",
      10,
      "15 minutes",
      "auth.login_rate_limited",
    );
  }

  async assertOtpVerifyAllowed(emailHash: string): Promise<void> {
    await this.assertAuthAttemptAllowed(
      emailHash,
      "auth.otp_verify_failed",
      10,
      "10 minutes",
      "auth.otp_verify_rate_limited",
    );
  }

  async assertSignupAllowed(ipHash: string): Promise<void> {
    const rateLimited = await this.hasRecentCountReached(
      `
        select count(*)::text as count
        from app.audit_events
        where action = 'auth.signup'
          and metadata ->> 'ipHash' = $1
          and created_at > now() - interval '1 hour'
      `,
      [ipHash],
      10,
    );
    if (!rateLimited) return;

    await this.audit.record({
      action: "auth.signup_rate_limited",
      entityType: "user",
      metadata: { ipHash },
    });
    throw new HttpException(
      "Слишком много регистраций. Попробуйте позже.",
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  async assertResetConfirmAllowed(ipHash: string): Promise<void> {
    const rateLimited = await this.hasRecentCountReached(
      `
        select count(*)::text as count
        from app.audit_events
        where action = 'auth.password_reset_failed'
          and metadata ->> 'ipHash' = $1
          and created_at > now() - interval '15 minutes'
      `,
      [ipHash],
      10,
    );
    if (!rateLimited) return;

    await this.audit.record({
      action: "auth.password_reset_rate_limited",
      entityType: "user",
      metadata: { ipHash },
    });
    throw new HttpException(
      "Слишком много попыток. Попробуйте позже.",
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  async isOtpRequestLimited(emailHash: string): Promise<boolean> {
    return this.hasRecentCountReached(
      `
        select count(*)::text as count
        from app.otp_challenges
        where email_hash = $1
          and purpose = 'email_verification'
          and created_at > now() - interval '10 minutes'
      `,
      [emailHash],
      5,
    );
  }

  async isResetRequestLimited(userId: string): Promise<boolean> {
    return this.hasRecentCountReached(
      `
        select count(*)::text as count
        from app.password_reset_tokens
        where user_id = $1
          and created_at > now() - interval '15 minutes'
      `,
      [userId],
      3,
    );
  }

  private async assertAuthAttemptAllowed(
    emailHash: string,
    failedAction: string,
    limit: number,
    window: string,
    rateLimitedAction: string,
  ): Promise<void> {
    const rateLimited = await this.hasRecentCountReached(
      `
        select count(*)::text as count
        from app.audit_events
        where action = $1
          and metadata ->> 'emailHash' = $2
          and created_at > now() - ($3::text)::interval
      `,
      [failedAction, emailHash, window],
      limit,
    );
    if (!rateLimited) return;

    await this.audit.record({
      action: rateLimitedAction,
      entityType: "user",
      metadata: { emailHash },
    });
    throw new HttpException(
      "Слишком много попыток. Попробуйте позже.",
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  private async hasRecentCountReached(
    sql: string,
    params: unknown[],
    limit: number,
  ): Promise<boolean> {
    const result = await this.database.query<CountRecord>(sql, params);
    return Number(result.rows[0]?.count ?? "0") >= limit;
  }
}
