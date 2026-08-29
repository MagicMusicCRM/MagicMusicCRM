import { ForbiddenException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { CapabilityRequestAuthorizer } from "./capability-request-authorizer";

describe("CapabilityRequestAuthorizer", () => {
  const actor = { userId: "actor-a", role: "teacher" as const };

  const activeAllowRow = (
    role: "admin" | "manager" | "director" | "system_admin",
  ) => ({
    role,
    active: true,
    definition_active: true,
    role_effect: "allow",
    override_effect: null,
  });

  function authorizerWith(row: Record<string, unknown> | undefined) {
    const query = jest.fn().mockResolvedValue({
      rows: row ? [row] : [],
    });
    return {
      authorizer: new CapabilityRequestAuthorizer({
        query,
      } as unknown as DatabaseService),
      query,
    };
  }

  it("allows the current database role package and returns the route scope", async () => {
    const { authorizer, query } = authorizerWith({
      role: "teacher",
      active: true,
      definition_active: true,
      role_effect: "allow",
      override_effect: null,
    });

    await expect(
      authorizer.authorize(actor, "GET", "/api/crm/students"),
    ).resolves.toMatchObject({
      policy: {
        capabilityKey: "crm.client.read.basic",
        scope: "resource",
      },
      source: "role-package",
    });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("personal_override.user_id"),
      ["actor-a", "crm.client.read.basic", 1],
    );
  });

  it("keeps the actor's own access snapshot available after authentication", async () => {
    const { authorizer, query } = authorizerWith({
      role: "teacher",
      active: true,
      definition_active: true,
      role_effect: "deny",
      override_effect: "deny",
    });

    await expect(
      authorizer.authorize(actor, "GET", "/api/access/me"),
    ).resolves.toMatchObject({
      policy: {
        scope: "self",
        authenticatedOnly: true,
      },
      source: "actor",
      reason: "authenticated_self_snapshot",
    });
    expect(query).not.toHaveBeenCalled();
  });

  it("fails closed for a denied package or personal deny", async () => {
    const packageDenied = authorizerWith({
      role: "teacher",
      active: true,
      definition_active: true,
      role_effect: "deny",
      override_effect: null,
    }).authorizer;
    await expect(
      packageDenied.authorize(actor, "PATCH", "/crm/students/id"),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const overrideDenied = authorizerWith({
      role: "teacher",
      active: true,
      definition_active: true,
      role_effect: "allow",
      override_effect: "deny",
    }).authorizer;
    await expect(
      overrideDenied.authorize(actor, "GET", "/crm/students/id"),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CAPABILITY_DENIED",
        source: "override",
      }),
    });
  });

  it("uses the current database role and denies missing/inactive actors", async () => {
    const currentRole = authorizerWith({
      role: "manager",
      active: true,
      definition_active: true,
      role_effect: "allow",
      override_effect: null,
    }).authorizer;
    await expect(
      currentRole.authorize(actor, "GET", "/analytics/status"),
    ).resolves.toMatchObject({ source: "role-package" });

    const missing = authorizerWith(undefined).authorizer;
    await expect(
      missing.authorize(actor, "GET", "/crm/students"),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CAPABILITY_DENIED",
        source: "actor",
      }),
    });
  });

  it("keeps hard invariants ahead of an accidental Teacher allow", async () => {
    const { authorizer } = authorizerWith({
      role: "teacher",
      active: true,
      definition_active: true,
      role_effect: "allow",
      override_effect: "allow",
    });

    await expect(
      authorizer.authorize(actor, "PATCH", "/crm/lessons/id"),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CAPABILITY_DENIED",
        source: "hard-invariant",
        reason: "teacher_hard_deny",
      }),
    });
  });

  it("fails closed when the database registry contract drifts", async () => {
    const { authorizer } = authorizerWith({
      role: "manager",
      active: true,
      definition_active: true,
      definition_override_mode: "locked",
      role_effect: "allow",
      override_effect: null,
    });

    await expect(
      authorizer.authorize(
        { userId: "actor-a", role: "manager" },
        "GET",
        "/crm/students",
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        source: "capability-registry",
        reason: "capability_contract_mismatch",
      }),
    });
  });

  describe("payroll owner-only route invariant", () => {
    it.each([
      ["manager", "POST", "/crm/teachers/id/rates"],
      ["manager", "PATCH", "/crm/teachers/id/rates/entry"],
      ["manager", "DELETE", "/crm/teachers/id/rates/entry"],
      ["manager", "PATCH", "/crm/lessons/teacher-rate"],
      ["manager", "PATCH", "/crm/teachers/id/payouts/entry"],
      ["manager", "DELETE", "/crm/teachers/id/payouts/entry"],
      ["admin", "POST", "/crm/teachers/id/rates"],
      ["admin", "PATCH", "/crm/teachers/id/rates/entry"],
      ["admin", "DELETE", "/crm/teachers/id/rates/entry"],
      ["admin", "PATCH", "/crm/lessons/teacher-rate"],
      ["admin", "PATCH", "/crm/teachers/id/payouts/entry"],
      ["admin", "DELETE", "/crm/teachers/id/payouts/entry"],
    ] as const)(
      "denies %s on %s %s before DTO validation even when the role package allows payroll write",
      async (role, method, path) => {
        const { authorizer } = authorizerWith(activeAllowRow(role));

        await expect(
          authorizer.authorize({ userId: `${role}-a`, role }, method, path),
        ).rejects.toMatchObject({
          status: 403,
          response: expect.objectContaining({
            code: "CAPABILITY_DENIED",
            capabilityKey: "config.commerce.manage",
            source: "hard-invariant",
            reason:
              role === "admin"
                ? "config_role_hard_deny"
                : "director_or_system_admin_required",
          }),
        });
      },
    );

    it.each([
      ["director", "POST", "/crm/teachers/id/rates", "role-package"],
      [
        "director",
        "PATCH",
        "/crm/teachers/id/rates/entry",
        "role-package",
      ],
      [
        "director",
        "DELETE",
        "/crm/teachers/id/rates/entry",
        "role-package",
      ],
      ["director", "PATCH", "/crm/lessons/teacher-rate", "role-package"],
      ["system_admin", "POST", "/crm/teachers/id/rates", "root"],
      ["system_admin", "PATCH", "/crm/teachers/id/rates/entry", "root"],
      ["system_admin", "DELETE", "/crm/teachers/id/rates/entry", "root"],
      ["system_admin", "PATCH", "/crm/lessons/teacher-rate", "root"],
    ] as const)(
      "allows owner role %s through v4 authorization on %s %s so DTO validation remains authoritative",
      async (role, method, path, source) => {
        const { authorizer } = authorizerWith(activeAllowRow(role));

        await expect(
          authorizer.authorize({ userId: `${role}-a`, role }, method, path),
        ).resolves.toMatchObject({
          policy: { capabilityKey: "config.commerce.manage" },
          source,
        });
      },
    );

    it.each([
      [
        "manager",
        "POST",
        "/crm/teachers/id/payouts",
        "commerce.teacher_payroll.write",
      ],
      [
        "manager",
        "GET",
        "/crm/teachers/id/payroll",
        "commerce.teacher_payroll.read",
      ],
      [
        "admin",
        "POST",
        "/crm/teachers/id/payouts",
        "commerce.teacher_payroll.write",
      ],
      [
        "admin",
        "GET",
        "/crm/teachers/id/payroll",
        "commerce.teacher_payroll.read",
      ],
    ] as const)(
      "preserves staff role %s access to %s %s",
      async (role, method, path, capabilityKey) => {
        const { authorizer } = authorizerWith(activeAllowRow(role));

        await expect(
          authorizer.authorize({ userId: `${role}-a`, role }, method, path),
        ).resolves.toMatchObject({
          policy: { capabilityKey },
          source: "role-package",
        });
      },
    );

    it("denies a stale Director token when the authoritative database role is Manager", async () => {
      const { authorizer } = authorizerWith(activeAllowRow("manager"));

      await expect(
        authorizer.authorize(
          { userId: "actor-a", role: "director" },
          "POST",
          "/crm/teachers/id/rates",
        ),
      ).rejects.toMatchObject({
        status: 403,
        response: expect.objectContaining({
          code: "CAPABILITY_DENIED",
          capabilityKey: "config.commerce.manage",
          source: "hard-invariant",
          reason: "director_or_system_admin_required",
        }),
      });
    });

    it("allows a stale Manager token when the authoritative database role is Director", async () => {
      const { authorizer } = authorizerWith(activeAllowRow("director"));

      await expect(
        authorizer.authorize(
          { userId: "actor-a", role: "manager" },
          "POST",
          "/crm/teachers/id/rates",
        ),
      ).resolves.toMatchObject({
        policy: { capabilityKey: "config.commerce.manage" },
        source: "role-package",
      });
    });
  });
});
