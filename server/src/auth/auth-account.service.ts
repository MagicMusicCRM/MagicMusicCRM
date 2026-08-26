import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import {
  normalizeEmail,
  sha256,
  toAuthUserResponse,
} from "./auth-normalization";
import { AuthUserResponse, IdentityRecord, UserRecord } from "./auth.types";
import { PasswordService } from "./password.service";
import { SessionService } from "./session.service";

@Injectable()
export class AuthAccountService {
  constructor(
    private readonly database: DatabaseService,
    private readonly passwordService: PasswordService,
    private readonly sessions: SessionService,
    private readonly audit: AuditService,
  ) {}

  async setPassword(
    actor: ActorContext,
    password: string,
  ): Promise<{ user: AuthUserResponse }> {
    const passwordHash = await this.passwordService.hash(password);
    const passwordCiphertext =
      actor.role === "client"
        ? null
        : this.passwordService.encryptForManagedAccess(password);
    const result = await this.database.query<UserRecord>(
      `
        update app.users
        set password_hash = $2,
            managed_password_ciphertext = $3,
            password_changed_at = now(),
            updated_at = now()
        where id = $1
          and deleted_at is null
          and is_app_account = true
        returning id, email, password_hash, role, email_verified_at
      `,
      [actor.userId, passwordHash, passwordCiphertext],
    );
    const user = result.rows[0];
    if (!user) throw new UnauthorizedException("Пользователь не найден.");

    await this.sessions.revokeAll(actor);
    await this.audit.record({
      actor,
      action: "auth.password_changed",
      entityType: "user",
      entityId: user.id,
    });
    return { user: toAuthUserResponse(user) };
  }

  async changeEmail(
    actor: ActorContext,
    emailInput: string,
    currentPassword: string,
  ): Promise<{ user: AuthUserResponse }> {
    const email = normalizeEmail(emailInput);
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

    const changed = await this.updateEmail(actor.userId, email);
    const updated = changed.rows[0];
    if (!updated) throw new UnauthorizedException("Пользователь не найден.");
    await this.sessions.revokeAll(actor);
    await this.audit.record({
      actor,
      action: "auth.email_changed",
      entityType: "user",
      entityId: actor.userId,
      metadata: { emailHash: sha256(email) },
    });
    return { user: toAuthUserResponse(updated) };
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

  private async updateEmail(userId: string, email: string) {
    try {
      return await this.database.query<UserRecord>(
        `update app.users
         set email = $2,
             email_verified_at = now(),
             email_changed_at = now(),
             updated_at = now()
         where id = $1 and deleted_at is null and is_app_account = true
         returning id, email, password_hash, role, email_verified_at`,
        [userId, email],
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
  }
}
