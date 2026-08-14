import { AuditService } from "../audit/audit.service";
import { PasswordService } from "../auth/password.service";
import { DatabaseService } from "../db/database.service";
import { PersonAccountService } from "./person-account.service";

describe("PersonAccountService initial roles", () => {
  const service = new PersonAccountService(
    {} as DatabaseService,
    {} as PasswordService,
    {} as AuditService,
  );

  it("allows a director to select a lower staff or teacher access role", () => {
    const actor = { userId: "director-a", role: "director" as const };

    expect(service.resolveInitialRole(actor, "staff", "manager")).toBe(
      "manager",
    );
    expect(service.resolveInitialRole(actor, "teacher", "admin")).toBe("admin");
  });

  it("keeps safe defaults when the role is omitted", () => {
    const actor = { userId: "director-a", role: "director" as const };

    expect(service.resolveInitialRole(actor, "staff")).toBe("admin");
    expect(service.resolveInitialRole(actor, "teacher")).toBe("teacher");
  });

  it("rejects equal, higher, root and cross-entity roles", () => {
    const actor = { userId: "director-a", role: "director" as const };

    expect(() =>
      service.resolveInitialRole(actor, "staff", "director"),
    ).toThrow("ниже собственной");
    expect(() =>
      service.resolveInitialRole(actor, "teacher", "system_admin"),
    ).toThrow("недопустимая роль");
    expect(() => service.resolveInitialRole(actor, "staff", "teacher")).toThrow(
      "недопустимая роль",
    );
  });

  it("allows system_admin to create a director card but not another root card", () => {
    const actor = { userId: "root-a", role: "system_admin" as const };

    expect(service.resolveInitialRole(actor, "staff", "director")).toBe(
      "director",
    );
    expect(() =>
      service.resolveInitialRole(actor, "staff", "system_admin"),
    ).toThrow("недопустимая роль");
  });
});

describe("PersonAccountService credential reveal", () => {
  const actor = { userId: "director-a", role: "director" as const };

  const createService = (role = "teacher") => {
    const database = {
      query: jest.fn().mockResolvedValue({
        rows: [
          {
            entity_id: "teacher-a",
            profile_id: "profile-a",
            user_id: "teacher-user-a",
            current_email: "teacher@example.com",
            current_password_hash: "scrypt$hash",
            current_password_ciphertext: "v1:encrypted",
            current_role: role,
            is_app_account: true,
            first_name: "Мария",
            last_name: "Петрова",
            phone: null,
            account_role: role,
            lifecycle_state: "active",
            password_changed_at: "2026-08-14T10:00:00.000Z",
            email_changed_at: "2026-08-14T09:00:00.000Z",
          },
        ],
      }),
    };
    const passwords = {
      decryptForManagedAccess: jest.fn().mockReturnValue("current-password"),
    };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    return {
      service: new PersonAccountService(
        database as unknown as DatabaseService,
        passwords as unknown as PasswordService,
        audit as unknown as AuditService,
      ),
      audit,
    };
  };

  it("returns the current managed credentials to Director and audits reveal", async () => {
    const { service, audit } = createService();

    await expect(
      service.readAccess(actor, "teacher", "teacher-a"),
    ).resolves.toMatchObject({
      email: "teacher@example.com",
      password: "current-password",
      passwordRecoverable: true,
    });
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.teacher_credentials_viewed",
        metadata: { passwordRecoverable: true },
      }),
    );
  });

  it("denies reveal to non-privileged roles and equal Director targets", async () => {
    const { service } = createService();
    await expect(
      service.readAccess(
        { userId: "manager-a", role: "manager" },
        "teacher",
        "teacher-a",
      ),
    ).rejects.toThrow("только директору");

    const equal = createService("director").service;
    await expect(
      equal.readAccess(actor, "teacher", "teacher-a"),
    ).rejects.toThrow("только более низкой роли");
  });
});
