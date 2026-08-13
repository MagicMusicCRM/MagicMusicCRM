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
