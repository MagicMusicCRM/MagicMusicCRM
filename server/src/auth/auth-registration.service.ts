import { ConflictException, Injectable } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import {
  normalizeEmail,
  normalizePhone,
  sha256,
  splitFullName,
  toAuthUserResponse,
} from "./auth-normalization";
import { AuthEmailChallengeService } from "./auth-email-challenge.service";
import { AuthRateLimitService } from "./auth-rate-limit.service";
import { SignupResponse, UserRecord } from "./auth.types";
import { SignupDto } from "./dto/signup.dto";
import { PasswordService } from "./password.service";

@Injectable()
export class AuthRegistrationService {
  constructor(
    private readonly database: DatabaseService,
    private readonly passwordService: PasswordService,
    private readonly rateLimits: AuthRateLimitService,
    private readonly challenges: AuthEmailChallengeService,
    private readonly audit: AuditService,
  ) {}

  async signup(dto: SignupDto, clientIp?: string): Promise<SignupResponse> {
    const ipHash = sha256(clientIp ?? "unknown");
    await this.rateLimits.assertSignupAllowed(ipHash);
    const email = normalizeEmail(dto.email);
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
                managed_password_ciphertext = null,
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
    const [firstName, lastName] = splitFullName(dto.fullName);
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
      [user.id, firstName, lastName, normalizePhone(dto.phone)],
    );

    await this.challenges.createEmailVerificationChallenge(user.id, email);
    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.signup",
      entityType: "user",
      entityId: user.id,
      metadata: { emailHash: sha256(email), ipHash },
    });

    return {
      user: toAuthUserResponse(user),
      emailVerificationRequired: true,
    };
  }
}
