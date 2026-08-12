import {
  ConflictException,
  HttpException,
  UnauthorizedException,
} from "@nestjs/common";
import { AuthService } from "./auth.service";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { PasswordService } from "./password.service";
import { SessionService } from "./session.service";
import { NotificationsService } from "../notifications/notifications.service";

describe("AuthService", () => {
  let query: jest.Mock;
  let audit: { record: jest.Mock };
  let sessions: {
    issueForUser: jest.Mock;
    rotate: jest.Mock;
    revokeAll: jest.Mock;
  };
  let service: AuthService;
  let notifications: { sendEmail: jest.Mock };
  const passwordService = new PasswordService();

  beforeEach(() => {
    query = jest.fn();
    audit = { record: jest.fn().mockResolvedValue(undefined) };
    sessions = {
      issueForUser: jest.fn().mockResolvedValue({
        accessToken: "access-token",
        refreshToken: "refresh-token",
        tokenType: "Bearer",
        expiresIn: 900,
      }),
      rotate: jest.fn().mockResolvedValue({
        accessToken: "next-access-token",
        refreshToken: "next-refresh-token",
        tokenType: "Bearer",
        expiresIn: 900,
      }),
      revokeAll: jest.fn().mockResolvedValue(undefined),
    };
    notifications = {
      sendEmail: jest.fn().mockResolvedValue({ queued: true }),
    };
    service = new AuthService(
      { query } as unknown as DatabaseService,
      passwordService,
      sessions as unknown as SessionService,
      audit as unknown as AuditService,
      notifications as unknown as NotificationsService,
    );
  });

  it("creates users with client role and normalized email", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] }) // signup rate-limit
      .mockResolvedValueOnce({ rows: [] }) // existing-email check
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "hash",
            role: "client",
            email_verified_at: null,
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] });

    const result = await service.signup({
      email: " USER@EXAMPLE.COM ",
      password: "strong-password-123",
      fullName: "User Example",
    });

    expect(query.mock.calls[2][1][0]).toBe("user@example.com");
    expect(query.mock.calls[2][1][2]).toBe("User Example");
    expect(result.user.role).toBe("client");
    expect(result.emailVerificationRequired).toBe(true);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.signup" }),
    );
    expect(notifications.sendEmail).toHaveBeenCalledWith(
      expect.objectContaining({ template: "auth_otp" }),
    );
  });

  it("rejects duplicate signup", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] }) // signup rate-limit
      .mockResolvedValueOnce({
        rows: [{ id: "existing-user", is_app_account: true }],
      });

    await expect(
      service.signup({
        email: "user@example.com",
        password: "strong-password-123",
        fullName: "User Example",
      }),
    ).rejects.toThrow(ConflictException);
  });

  it("rate limits signups per IP", async () => {
    query.mockResolvedValueOnce({ rows: [{ count: "10" }] }); // limit reached

    await expect(
      service.signup(
        {
          email: "flood@example.com",
          password: "strong-password-123",
          fullName: "Flood User",
        },
        "9.9.9.9",
      ),
    ).rejects.toThrow(HttpException);

    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.signup_rate_limited" }),
    );
  });

  it("logs in with valid credentials", async () => {
    const passwordHash = await passwordService.hash("strong-password-123");
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: passwordHash,
            role: "client",
            email_verified_at: new Date(),
          },
        ],
      });

    const result = await service.login({
      email: "user@example.com",
      password: "strong-password-123",
    });

    expect(result.user.id).toBe("user-a");
    expect(result.user.emailVerified).toBe(true);
    expect(result.session?.refreshToken).toBe("refresh-token");
    expect(query.mock.calls[1][0]).toContain("u.is_app_account = true");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.login_password" }),
    );
  });

  it("rejects login until email is verified", async () => {
    const passwordHash = await passwordService.hash("strong-password-123");
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: passwordHash,
            role: "client",
            email_verified_at: null,
          },
        ],
      });

    await expect(
      service.login({
        email: "user@example.com",
        password: "strong-password-123",
      }),
    ).rejects.toThrow("Подтвердите email перед входом.");

    expect(sessions.issueForUser).not.toHaveBeenCalled();
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.login_email_unverified" }),
    );
  });

  it("requires email OTP without issuing a session when 2FA is enabled", async () => {
    const passwordHash = await passwordService.hash("strong-password-123");
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: passwordHash,
            role: "client",
            email_verified_at: new Date(),
            email_otp_2fa_enabled: true,
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] });

    const result = await service.login({
      email: "user@example.com",
      password: "strong-password-123",
    });

    expect(result.emailOtpRequired).toBe(true);
    expect(result.session).toBeUndefined();
    expect(sessions.issueForUser).not.toHaveBeenCalled();
    expect(query.mock.calls[2][0]).toContain("insert into app.otp_challenges");
    expect(notifications.sendEmail).toHaveBeenCalledWith(
      expect.objectContaining({ template: "auth_otp" }),
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.login_email_otp_required" }),
    );
  });

  it("requires email OTP for privileged roles even without the 2FA flag", async () => {
    const passwordHash = await passwordService.hash("strong-password-123");
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "admin-a",
            email: "admin@example.com",
            password_hash: passwordHash,
            role: "admin",
            email_verified_at: new Date(),
            email_otp_2fa_enabled: false,
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });

    const result = await service.login({
      email: "admin@example.com",
      password: "strong-password-123",
    });

    expect(result.emailOtpRequired).toBe(true);
    expect(result.session).toBeUndefined();
    expect(sessions.issueForUser).not.toHaveBeenCalled();
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.login_email_otp_required" }),
    );
  });

  it("bypasses the forced OTP for allow-listed test accounts", async () => {
    const previous = process.env.AUTH_OTP_BYPASS_EMAILS;
    process.env.AUTH_OTP_BYPASS_EMAILS = "admin@example.com, other@example.com";
    try {
      const passwordHash = await passwordService.hash("strong-password-123");
      query
        .mockResolvedValueOnce({ rows: [{ count: "0" }] }) // login rate-limit
        .mockResolvedValueOnce({
          rows: [
            {
              id: "admin-a",
              email: "admin@example.com",
              password_hash: passwordHash,
              role: "admin",
              email_verified_at: new Date(),
              email_otp_2fa_enabled: false,
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] }); // is_app_account touch-up

      const result = await service.login({
        email: "ADMIN@example.com", // case-insensitive match
        password: "strong-password-123",
      });

      expect(result.emailOtpRequired).toBeUndefined();
      expect(result.session?.refreshToken).toBe("refresh-token");
      expect(sessions.issueForUser).toHaveBeenCalled();
      // No OTP challenge was created or emailed.
      expect(notifications.sendEmail).not.toHaveBeenCalled();
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({ action: "auth.login_otp_bypassed" }),
      );
      expect(audit.record).not.toHaveBeenCalledWith(
        expect.objectContaining({ action: "auth.login_email_otp_required" }),
      );
    } finally {
      if (previous === undefined) {
        delete process.env.AUTH_OTP_BYPASS_EMAILS;
      } else {
        process.env.AUTH_OTP_BYPASS_EMAILS = previous;
      }
    }
  });

  it("still forces OTP for privileged roles not on the bypass list", async () => {
    const previous = process.env.AUTH_OTP_BYPASS_EMAILS;
    process.env.AUTH_OTP_BYPASS_EMAILS = "someone-else@example.com";
    try {
      const passwordHash = await passwordService.hash("strong-password-123");
      query
        .mockResolvedValueOnce({ rows: [{ count: "0" }] })
        .mockResolvedValueOnce({
          rows: [
            {
              id: "manager-a",
              email: "manager@example.com",
              password_hash: passwordHash,
              role: "manager",
              email_verified_at: new Date(),
              email_otp_2fa_enabled: false,
            },
          ],
        })
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({ rows: [] });

      const result = await service.login({
        email: "manager@example.com",
        password: "strong-password-123",
      });

      expect(result.emailOtpRequired).toBe(true);
      expect(result.session).toBeUndefined();
      expect(sessions.issueForUser).not.toHaveBeenCalled();
    } finally {
      if (previous === undefined) {
        delete process.env.AUTH_OTP_BYPASS_EMAILS;
      } else {
        process.env.AUTH_OTP_BYPASS_EMAILS = previous;
      }
    }
  });

  it("rate limits repeated login failures before password verification", async () => {
    query.mockResolvedValueOnce({ rows: [{ count: "10" }] });

    await expect(
      service.login({ email: "user@example.com", password: "bad" }),
    ).rejects.toThrow(HttpException);

    expect(query).toHaveBeenCalledTimes(1);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.login_rate_limited" }),
    );
    expect(sessions.issueForUser).not.toHaveBeenCalled();
  });

  it("refreshes sessions through SessionService", async () => {
    const result = await service.refresh("refresh-token");

    expect(sessions.rotate).toHaveBeenCalledWith("refresh-token");
    expect(result.session.accessToken).toBe("next-access-token");
  });

  it("logs out all sessions for the current actor", async () => {
    const result = await service.logoutAll({
      userId: "user-a",
      role: "client",
    });

    expect(sessions.revokeAll).toHaveBeenCalledWith({
      userId: "user-a",
      role: "client",
    });
    expect(result.success).toBe(true);
  });

  it("creates OTP challenge for an existing user", async () => {
    query
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "hash",
            role: "client",
            email_verified_at: null,
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({ rows: [] });

    const result = await service.requestOtp("USER@example.com");

    expect(result.accepted).toBe(true);
    expect(query).toHaveBeenCalledTimes(3);
    expect(query.mock.calls[2][0]).toContain("insert into app.otp_challenges");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.otp_requested" }),
    );
    expect(notifications.sendEmail).toHaveBeenCalledWith(
      expect.objectContaining({ template: "auth_otp" }),
    );
  });

  it("rate limits OTP challenges", async () => {
    query
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "hash",
            role: "client",
            email_verified_at: null,
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [{ count: "5" }] });

    await expect(service.requestOtp("user@example.com")).rejects.toThrow(
      HttpException,
    );
    expect(query).toHaveBeenCalledTimes(2);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.otp_rate_limited" }),
    );
  });

  it("verifies a valid OTP and marks email verified", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "hash",
            role: "client",
            email_verified_at: new Date(),
          },
        ],
      });

    const result = await service.verifyOtp("user@example.com", "123456");

    expect(result.user.emailVerified).toBe(true);
    expect(query.mock.calls[1][0]).toContain("update app.otp_challenges");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.otp_verified" }),
    );
  });

  it("issues a session after valid OTP when email 2FA is enabled", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "hash",
            role: "client",
            email_verified_at: new Date(),
            email_otp_2fa_enabled: true,
          },
        ],
      });

    const result = await service.verifyOtp("user@example.com", "123456");

    expect(result.user.emailVerified).toBe(true);
    expect(result.session?.accessToken).toBe("access-token");
    expect(sessions.issueForUser).toHaveBeenCalledWith({
      id: "user-a",
      email: "user@example.com",
      role: "client",
    });
  });

  it("records invalid OTP attempts and rate limits verification", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({ rows: [] });

    await expect(
      service.verifyOtp("user@example.com", "000000"),
    ).rejects.toThrow("Код подтверждения недействителен или истек.");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.otp_verify_failed" }),
    );

    query.mockClear();
    audit.record.mockClear();
    query.mockResolvedValueOnce({ rows: [{ count: "10" }] });

    await expect(
      service.verifyOtp("user@example.com", "123456"),
    ).rejects.toThrow(HttpException);
    expect(query).toHaveBeenCalledTimes(1);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.otp_verify_rate_limited" }),
    );
  });

  it("accepts password reset request without leaking unknown email", async () => {
    query.mockResolvedValueOnce({ rows: [] });

    const result = await service.requestPasswordReset("missing@example.com");

    expect(result.accepted).toBe(true);
    expect(query).toHaveBeenCalledTimes(1);
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("creates one-time password reset token for existing user", async () => {
    query
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "hash",
            role: "client",
            email_verified_at: new Date(),
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({ rows: [] });

    const result = await service.requestPasswordReset("user@example.com");

    expect(result.accepted).toBe(true);
    expect(query.mock.calls[2][0]).toContain(
      "insert into app.password_reset_tokens",
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.password_reset_requested" }),
    );
    expect(notifications.sendEmail).toHaveBeenCalledWith(
      expect.objectContaining({
        template: "auth_password_reset",
        body: expect.stringMatching(
          /Код для сброса пароля действует 30 минут: \d{6}/,
        ),
      }),
    );
  });

  it("keeps password reset request safe when rate limited", async () => {
    query
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "hash",
            role: "client",
            email_verified_at: new Date(),
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [{ count: "3" }] });

    const result = await service.requestPasswordReset("user@example.com");

    expect(result.accepted).toBe(true);
    expect(query).toHaveBeenCalledTimes(2);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.password_reset_rate_limited" }),
    );
  });

  it("resets password and revokes existing sessions", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] }) // confirm rate-limit ok
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: "new-hash",
            role: "client",
            email_verified_at: new Date(),
          },
        ],
      });

    const result = await service.resetPassword(
      "abcdefghijklmnopqrstuvwxyz0123456789",
      "new-strong-password-123",
      "1.2.3.4",
    );

    expect(result.user.id).toBe("user-a");
    expect(query.mock.calls[1][0]).toContain(
      "update app.password_reset_tokens",
    );
    expect(sessions.revokeAll).toHaveBeenCalledWith({
      userId: "user-a",
      role: "client",
    });
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.password_reset_completed" }),
    );
  });

  it("rate limits repeated password reset confirmations by IP", async () => {
    query.mockResolvedValueOnce({ rows: [{ count: "10" }] }); // limit reached

    await expect(
      service.resetPassword("000000", "new-strong-password-123", "9.9.9.9"),
    ).rejects.toThrow(HttpException);

    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.password_reset_rate_limited" }),
    );
    // Must not even attempt to consume a token once rate limited.
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("records failed password reset confirmations for abuse detection", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] }) // rate-limit ok
      .mockResolvedValueOnce({ rows: [] }); // wrong/expired token -> no row

    await expect(
      service.resetPassword("123456", "new-strong-password-123", "9.9.9.9"),
    ).rejects.toThrow("недействительна");

    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.password_reset_failed" }),
    );
  });

  it("sets password for the current authenticated user", async () => {
    query.mockResolvedValueOnce({
      rows: [
        {
          id: "user-a",
          email: "user@example.com",
          password_hash: "new-hash",
          role: "client",
          email_verified_at: new Date(),
        },
      ],
    });

    const result = await service.setPassword(
      { userId: "user-a", role: "client" },
      "new-strong-password-123",
    );

    expect(result.user.id).toBe("user-a");
    expect(query.mock.calls[0][0]).toContain("update app.users");
    expect(query.mock.calls[0][1][0]).toBe("user-a");
    expect(query.mock.calls[0][1][1]).not.toBe("new-strong-password-123");
    // Changing the password must invalidate every existing session (High #2).
    expect(sessions.revokeAll).toHaveBeenCalledWith({
      userId: "user-a",
      role: "client",
    });
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "auth.password_changed",
        actor: { userId: "user-a", role: "client" },
      }),
    );
  });

  it("never lets public signup claim a linked staff or teacher identity", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "technical-teacher-a",
            is_app_account: false,
            protected_person: true,
          },
        ],
      });

    await expect(
      service.signup({
        email: "teacher@example.com",
        password: "strong-password-123",
        fullName: "Teacher Account",
      }),
    ).rejects.toThrow("выдаёт директор");
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("changes the current email, timestamps it and revokes all sessions", async () => {
    const passwordHash = await passwordService.hash("current-password-123");
    query
      .mockResolvedValueOnce({
        rows: [
          {
            id: "teacher-user-a",
            email: "old@example.com",
            password_hash: passwordHash,
            role: "teacher",
            email_verified_at: new Date(),
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "teacher-user-a",
            email: "new@example.com",
            password_hash: passwordHash,
            role: "teacher",
            email_verified_at: new Date(),
          },
        ],
      });
    const actor = { userId: "teacher-user-a", role: "teacher" as const };

    await expect(
      service.changeEmail(
        actor,
        " NEW@EXAMPLE.COM ",
        "current-password-123",
      ),
    ).resolves.toMatchObject({ user: { email: "new@example.com" } });

    expect(query.mock.calls[1][0]).toContain("email_changed_at = now()");
    expect(query.mock.calls[1][1]).toEqual([
      "teacher-user-a",
      "new@example.com",
    ]);
    expect(sessions.revokeAll).toHaveBeenCalledWith(actor);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.email_changed" }),
    );
  });

  it("lists email and external identities for current user", async () => {
    query.mockResolvedValueOnce({
      rows: [{ provider: "email" }, { provider: "google" }],
    });

    const result = await service.listIdentities({
      userId: "user-a",
      role: "client",
    });

    expect(result.items).toEqual([
      { provider: "email" },
      { provider: "google" },
    ]);
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("from app.user_identities"),
      ["user-a"],
    );
  });

  it("verifies email with a valid token", async () => {
    query.mockResolvedValueOnce({
      rows: [
        {
          id: "user-a",
          email: "user@example.com",
          password_hash: "hash",
          role: "client",
          email_verified_at: new Date(),
        },
      ],
    });

    const result = await service.verifyEmail(
      "abcdefghijklmnopqrstuvwxyz0123456789",
    );

    expect(result.user.emailVerified).toBe(true);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.email_verified" }),
    );
  });

  it("rejects invalid email verification token", async () => {
    query.mockResolvedValueOnce({ rows: [] });

    await expect(
      service.verifyEmail("abcdefghijklmnopqrstuvwxyz0123456789"),
    ).rejects.toThrow("Код подтверждения недействителен или истек.");
  });

  it("stores a normalized phone on the profile at signup", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] }) // signup rate-limit
      .mockResolvedValueOnce({ rows: [] }) // existing-email check
      .mockResolvedValueOnce({
        rows: [
          {
            id: "u1",
            email: "a@b.c",
            role: "client",
            email_verified_at: null,
            is_app_account: true,
          },
        ],
      }) // insert into app.users
      .mockResolvedValueOnce({ rows: [] }) // insert into app.profiles
      .mockResolvedValueOnce({ rows: [] }); // insert into app.otp_challenges

    await service.signup({
      email: "a@b.c",
      password: "x".repeat(12),
      fullName: "Иван Петров",
      phone: "+79991234567",
    } as never);

    const profileInsert = query.mock.calls.find(
      (c) => typeof c[0] === "string" && c[0].includes("insert into app.profiles"),
    );
    expect(profileInsert).toBeTruthy();
    // phone param is the normalized '79991234567'
    expect(profileInsert![1]).toContain("79991234567");
  });

  it("uses same safe error for missing user and invalid password", async () => {
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({ rows: [] });

    await expect(
      service.login({ email: "missing@example.com", password: "bad" }),
    ).rejects.toThrow(UnauthorizedException);

    const passwordHash = await passwordService.hash("strong-password-123");
    query
      .mockResolvedValueOnce({ rows: [{ count: "0" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "user-a",
            email: "user@example.com",
            password_hash: passwordHash,
            role: "client",
            email_verified_at: null,
          },
        ],
      });

    await expect(
      service.login({ email: "user@example.com", password: "bad" }),
    ).rejects.toThrow(UnauthorizedException);
  });
});
