import {
  ConflictException,
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { createHash, randomBytes, randomInt } from "node:crypto";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
  UserRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { LoginDto } from "./dto/login.dto";
import { SignupDto } from "./dto/signup.dto";
import { PasswordService } from "./password.service";
import { SessionService, TokenPair } from "./session.service";

interface UserRecord {
  id: string;
  email: string;
  password_hash: string | null;
  role: UserRole;
  email_verified_at: Date | string | null;
  email_otp_2fa_enabled?: boolean;
  is_app_account?: boolean;
}

interface CountRecord {
  count: string;
}

interface IdentityRecord {
  provider: string;
}

export interface AuthUserResponse {
  id: string;
  email: string;
  role: UserRole;
  emailVerified: boolean;
}

export interface SignupResponse {
  user: AuthUserResponse;
  emailVerificationRequired: boolean;
}

export interface AcceptedResponse {
  accepted: true;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly passwordService: PasswordService,
    private readonly sessions: SessionService,
    private readonly audit: AuditService,
    private readonly notifications: NotificationsService,
  ) {}

  async signup(dto: SignupDto, clientIp?: string): Promise<SignupResponse> {
    // Throttle mass account creation per client IP (KVA): prevents spam signups
    // and outbound-email-quota abuse.
    const ipHash = this.tokenHash(clientIp ?? "unknown");
    await this.assertSignupAllowed(ipHash);
    const email = this.normalizeEmail(dto.email);
    const existing = await this.database.query<{
      id: string;
      is_app_account: boolean;
      protected_person: boolean;
    }>(
      `select account.id, account.is_app_account,
         exists (
           select 1 from app.user_crm_links link
           where link.user_id = account.id
             and link.entity_type in ('teacher', 'staff')
             and link.deleted_at is null
         ) as protected_person
       from app.users account
       where lower(account.email) = lower($1)
         and account.deleted_at is null
       limit 1`,
      [email],
    );

    if (
      existing.rows[0]?.is_app_account ||
      existing.rows[0]?.protected_person
    ) {
      throw new ConflictException(
        existing.rows[0]?.protected_person
          ? "Доступ к карточке сотрудника выдаёт директор."
          : "Пользователь с такой почтой уже существует.",
      );
    }

    const passwordHash = await this.passwordService.hash(dto.password);
    const created = existing.rows[0]
      ? await this.database.query<UserRecord>(
          `
            update app.users
            set password_hash = $2,
                password_changed_at = now(),
                full_name = $3,
                role = 'client'::app.user_role,
                is_app_account = true,
                profile_completed = false,
                updated_at = now()
            where id = $1
              and deleted_at is null
            returning id, email, password_hash, role, email_verified_at, is_app_account
          `,
          [existing.rows[0].id, passwordHash, dto.fullName.trim()],
        )
      : await this.database.query<UserRecord>(
          `
            insert into app.users (
              email, password_hash, full_name, role, is_app_account,
              password_changed_at
            )
            values ($1, $2, $3, 'client', true, now())
            returning id, email, password_hash, role, email_verified_at, is_app_account
          `,
          [email, passwordHash, dto.fullName.trim()],
        );

    const user = created.rows[0];
    const [firstName, lastName] = this.splitFullName(dto.fullName);
    const phone = this.normalizePhone(dto.phone);
    await this.database.query(
      `
        insert into app.profiles (user_id, first_name, last_name, phone)
        values ($1, $2, $3, $4)
        on conflict (user_id) do update
        set first_name = excluded.first_name,
            last_name = excluded.last_name,
            phone = coalesce(excluded.phone, app.profiles.phone),
            updated_at = now()
      `,
      [user.id, firstName, lastName, phone],
    );

    await this.createEmailVerificationChallenge(user.id, email);
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.signup",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash: this.emailHash(email), ipHash },
    });

    return { user: this.toResponse(user), emailVerificationRequired: true };
  }

  async login(
    dto: LoginDto,
  ): Promise<{
    user: AuthUserResponse;
    session?: TokenPair;
    emailOtpRequired?: boolean;
  }> {
    const email = this.normalizeEmail(dto.email);
    const emailHash = this.emailHash(email);
    await this.assertAuthAttemptAllowed(
      emailHash,
      "auth.login_failed",
      10,
      "15 minutes",
      "auth.login_rate_limited",
    );

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

    if (!user || !verified) {
      await this.audit.record({
        action: "auth.login_failed",
        entityType: "user",
        metadata: { emailHash },
      });
      throw new UnauthorizedException("Неверная почта или пароль.");
    }

    if (!user.email_verified_at) {
      await this.audit.record({
        actor: { userId: user.id, role: user.role },
        action: "auth.login_email_unverified",
        entityType: "user",
        entityId: user.id,
        metadata: { emailHash },
      });
      throw new UnauthorizedException("Подтвердите email перед входом.");
    }

    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.login_password",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash },
    });
    // MFA обязательна для привилегированных ролей (Администратор/Управляющий/
    // Администратор системы) независимо от пользовательского флага (KVA-218):
    // компрометация одного пароля не должна давать полный доступ.
    //
    // Исключение — заранее заданный список тестовых аккаунтов
    // (AUTH_OTP_BYPASS_EMAILS): их почта не существует, поэтому код подтверждения
    // доставить невозможно. Пароль и подтверждение почты у них по-прежнему
    // проверяются, а сам обход фиксируется в аудите. Список временный — эти
    // небезопасные аккаунты удаляются после этапа тестирования.
    const otpRequired =
      Boolean(user.email_otp_2fa_enabled) || isManagerOrAdminRole(user.role);
    if (otpRequired && !this.isOtpBypassed(email)) {
      await this.createOtpChallenge(user, email);
      await this.audit.record({
        actor: { userId: user.id, role: user.role },
        action: "auth.login_email_otp_required",
        entityType: "user",
        entityId: user.id,
        metadata: { emailHash },
      });
      return { user: this.toResponse(user), emailOtpRequired: true };
    }

    if (otpRequired) {
      await this.audit.record({
        actor: { userId: user.id, role: user.role },
        action: "auth.login_otp_bypassed",
        entityType: "user",
        entityId: user.id,
        metadata: { emailHash },
      });
    }

    return {
      user: this.toResponse(user),
      session: await this.sessions.issueForUser({
        id: user.id,
        email: user.email,
        role: user.role,
      }),
    };
  }

  async refresh(refreshToken: string): Promise<{ session: TokenPair }> {
    return { session: await this.sessions.rotate(refreshToken) };
  }

  async logoutAll(actor: ActorContext): Promise<{ success: true }> {
    await this.sessions.revokeAll(actor);
    return { success: true };
  }

  async requestOtp(emailInput: string): Promise<AcceptedResponse> {
    const email = this.normalizeEmail(emailInput);
    const emailHash = this.emailHash(email);
    const user = await this.findUserByEmail(email);
    if (!user) return { accepted: true };

    const rateLimited = await this.hasRecentCountReached(
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

    if (rateLimited) {
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

    await this.createOtpChallenge(user, email);

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
    const email = this.normalizeEmail(emailInput);
    const emailHash = this.emailHash(email);
    await this.assertAuthAttemptAllowed(
      emailHash,
      "auth.otp_verify_failed",
      10,
      "10 minutes",
      "auth.otp_verify_rate_limited",
    );

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
      [emailHash, this.otpHash(email, code), email],
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

    if (user.email_otp_2fa_enabled) {
      return {
        user: this.toResponse(user),
        session: await this.sessions.issueForUser({
          id: user.id,
          email: user.email,
          role: user.role,
        }),
      };
    }

    return { user: this.toResponse(user) };
  }

  async requestPasswordReset(emailInput: string): Promise<AcceptedResponse> {
    const email = this.normalizeEmail(emailInput);
    const user = await this.findUserByEmail(email);
    if (!user) return { accepted: true };

    const rateLimited = await this.hasRecentCountReached(
      `
        select count(*)::text as count
        from app.password_reset_tokens
        where user_id = $1
          and created_at > now() - interval '15 minutes'
      `,
      [user.id],
      3,
    );

    if (rateLimited) {
      await this.audit.record({
        actor: { userId: user.id, role: user.role },
        action: "auth.password_reset_rate_limited",
        entityType: "user",
        entityId: user.id,
        metadata: { emailHash: this.emailHash(email) },
      });
      return { accepted: true };
    }

    const token = randomInt(100000, 1000000).toString();
    await this.database.query(
      `
        insert into app.password_reset_tokens (user_id, token_hash, expires_at)
        values ($1, $2, now() + interval '30 minutes')
      `,
      [user.id, this.tokenHash(token)],
    );

    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.password_reset_requested",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash: this.emailHash(email) },
    });
    await this.safeEmail(
      user.id,
      "auth_password_reset",
      "Сброс пароля Magic Music",
      `Код для сброса пароля действует 30 минут: ${token}`,
    );

    return { accepted: true };
  }

  async resetPassword(
    token: string,
    password: string,
    clientIp?: string,
  ): Promise<{ user: AuthUserResponse }> {
    // Защита от перебора 6-значного кода: ограничиваем попытки подтверждения по
    // IP клиента (req.ip корректен за reverse-proxy благодаря trust proxy).
    const ipHash = this.tokenHash(clientIp ?? "unknown");
    await this.assertResetConfirmAllowed(ipHash);

    const passwordHash = await this.passwordService.hash(password);
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
      [this.tokenHash(token), passwordHash],
    );

    const user = result.rows[0];
    if (!user) {
      // Неверный/просроченный код — фиксируем для троттлинга по IP.
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

    return { user: this.toResponse(user) };
  }

  async setPassword(
    actor: ActorContext,
    password: string,
  ): Promise<{ user: AuthUserResponse }> {
    const passwordHash = await this.passwordService.hash(password);
    const result = await this.database.query<UserRecord>(
      `
        update app.users
        set password_hash = $2,
            password_changed_at = now(),
            updated_at = now()
        where id = $1
          and deleted_at is null
          and is_app_account = true
        returning id, email, password_hash, role, email_verified_at
      `,
      [actor.userId, passwordHash],
    );

    const user = result.rows[0];
    if (!user) {
      throw new UnauthorizedException("Пользователь не найден.");
    }

    // Смена пароля инвалидирует все активные сессии/refresh-токены (High #2):
    // украденная сессия не должна пережить смену пароля.
    await this.sessions.revokeAll(actor);
    await this.audit.record({
      actor,
      action: "auth.password_changed",
      entityType: "user",
      entityId: user.id,
    });

    return { user: this.toResponse(user) };
  }

  async changeEmail(
    actor: ActorContext,
    emailInput: string,
    currentPassword: string,
  ): Promise<{ user: AuthUserResponse }> {
    const email = this.normalizeEmail(emailInput);
    const current = await this.database.query<UserRecord>(
      `select id, email, password_hash, role, email_verified_at
       from app.users
       where id = $1 and deleted_at is null and is_app_account = true
       limit 1`,
      [actor.userId],
    );
    const user = current.rows[0];
    const passwordValid =
      user?.password_hash &&
      (await this.passwordService.verify(currentPassword, user.password_hash));
    if (!user || !passwordValid) {
      throw new UnauthorizedException("Текущий пароль указан неверно.");
    }
    if (user.email.toLowerCase() === email) {
      throw new BadRequestException("Новая почта совпадает с текущей.");
    }

    let changed;
    try {
      changed = await this.database.query<UserRecord>(
        `update app.users
         set email = $2,
             email_verified_at = now(),
             email_changed_at = now(),
             updated_at = now()
         where id = $1 and deleted_at is null and is_app_account = true
         returning id, email, password_hash, role, email_verified_at`,
        [actor.userId, email],
      );
    } catch (error) {
      if (
        typeof error === "object" &&
        error !== null &&
        "code" in error &&
        (error as { code?: string }).code === "23505"
      ) {
        throw new ConflictException(
          "Пользователь с такой почтой уже существует.",
        );
      }
      throw error;
    }
    const updated = changed.rows[0];
    if (!updated) throw new UnauthorizedException("Пользователь не найден.");
    await this.sessions.revokeAll(actor);
    await this.audit.record({
      actor,
      action: "auth.email_changed",
      entityType: "user",
      entityId: actor.userId,
      metadata: { emailHash: this.emailHash(email) },
    });
    return { user: this.toResponse(updated) };
  }

  async listIdentities(
    actor: ActorContext,
  ): Promise<{ items: Array<{ provider: string }> }> {
    const result = await this.database.query<IdentityRecord>(
      `
        select provider
        from (
          select 'email'::text as provider
          from app.users
          where id = $1
            and password_hash is not null
            and deleted_at is null
            and is_app_account = true
          union
          select ui.provider
          from app.user_identities ui
          join app.users u on u.id = ui.user_id and u.deleted_at is null
          where ui.user_id = $1
        ) identities
        order by provider
      `,
      [actor.userId],
    );

    return { items: result.rows.map((row) => ({ provider: row.provider })) };
  }

  async verifyEmail(token: string): Promise<{ user: AuthUserResponse }> {
    const tokenHash = this.tokenHash(token);
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
      [tokenHash],
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

    return { user: this.toResponse(user) };
  }

  private normalizeEmail(email: string): string {
    return email.trim().toLowerCase();
  }

  private normalizePhone(phone?: string | null): string | null {
    const digits = (phone ?? "").replace(/\D/g, "");
    if (!digits) return null;
    if (digits.length === 11 && digits.startsWith("8")) return `7${digits.slice(1)}`;
    return digits;
  }

  // Test-only OTP bypass: emails in AUTH_OTP_BYPASS_EMAILS (comma-separated) skip
  // the forced email-OTP step because their addresses don't exist and the code
  // can't be delivered. Password + email verification are still enforced; the
  // bypass is audited. Temporary — these throwaway accounts are deleted after
  // the test phase, after which the env var is removed.
  private isOtpBypassed(email: string): boolean {
    const raw = process.env.AUTH_OTP_BYPASS_EMAILS;
    if (!raw) return false;
    return raw
      .split(",")
      .map((entry) => entry.trim().toLowerCase())
      .filter((entry) => entry.length > 0)
      .includes(email.toLowerCase());
  }

  private emailHash(email: string): string {
    return createHash("sha256").update(email).digest("hex");
  }

  private splitFullName(fullName: string): [string, string | null] {
    const [firstName, ...rest] = fullName.trim().split(/\s+/);
    return [firstName, rest.length > 0 ? rest.join(" ") : null];
  }

  private tokenHash(token: string): string {
    return createHash("sha256").update(token).digest("hex");
  }

  private async createEmailVerificationChallenge(
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

  private async createOtpChallenge(
    user: UserRecord,
    email: string,
  ): Promise<void> {
    const code = this.createOtpCode();
    const emailHash = this.emailHash(email);
    await this.database.query(
      `
        insert into app.otp_challenges (
          user_id,
          email_hash,
          purpose,
          code_hash,
          expires_at
        )
        values ($1, $2, 'email_verification', $3, now() + interval '10 minutes')
      `,
      [user.id, emailHash, this.otpHash(email, code)],
    );
    await this.safeEmail(
      user.id,
      "auth_otp",
      "Код подтверждения Magic Music",
      `Ваш код подтверждения: ${code}`,
    );
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

  private async hasRecentCountReached(
    sql: string,
    params: unknown[],
    limit: number,
  ): Promise<boolean> {
    const result = await this.database.query<CountRecord>(sql, params);
    const count = Number(result.rows[0]?.count ?? "0");
    return count >= limit;
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

  private async assertSignupAllowed(ipHash: string): Promise<void> {
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

  private async assertResetConfirmAllowed(ipHash: string): Promise<void> {
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

  private createOtpCode(): string {
    return randomInt(100000, 1000000).toString();
  }

  private otpHash(email: string, code: string): string {
    return this.tokenHash(`${email}:${code}`);
  }

  private toResponse(user: UserRecord): AuthUserResponse {
    return {
      id: user.id,
      email: user.email,
      role: user.role,
      emailVerified: Boolean(user.email_verified_at),
    };
  }

  private async safeEmail(
    userId: string,
    template: string,
    title: string,
    body: string,
  ): Promise<void> {
    try {
      await this.notifications.sendEmail({ userId, template, title, body });
    } catch {
      await this.audit.record({
        actor: { userId, role: "client" },
        action: "notifications.email_enqueue_failed",
        entityType: "user",
        entityId: userId,
        metadata: { template },
      });
    }
  }
}
