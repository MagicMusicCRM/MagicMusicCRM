import { ForbiddenException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { CapabilityRequestAuthorizer } from "./capability-request-authorizer";

describe("CapabilityRequestAuthorizer", () => {
  const actor = { userId: "actor-a", role: "teacher" as const };

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
});
