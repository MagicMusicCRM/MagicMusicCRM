import { ForbiddenException, NotFoundException } from "@nestjs/common";
import { LegalPolicy } from "./legal.policy";

describe("LegalPolicy", () => {
  const policy = new LegalPolicy();
  const client = { userId: "client-a", role: "client" as const };
  const manager = { userId: "manager-a", role: "manager" as const };
  const admin = { userId: "admin-a", role: "admin" as const };
  const director = { userId: "director-a", role: "director" as const };
  const systemAdmin = { userId: "root-a", role: "system_admin" as const };
  const request = {
    id: "request-a",
    user_id: "client-a",
    status: "pending" as const,
  };

  it("allows owner, manager and admin to read deletion request status", () => {
    expect(() =>
      policy.assertCanReadDeletionRequest(client, request),
    ).not.toThrow();
    expect(() =>
      policy.assertCanReadDeletionRequest(manager, request),
    ).not.toThrow();
    expect(() =>
      policy.assertCanReadDeletionRequest(admin, request),
    ).not.toThrow();
  });

  it("hides deletion request status from foreign client", () => {
    expect(() =>
      policy.assertCanReadDeletionRequest(
        { userId: "client-b", role: "client" },
        request,
      ),
    ).toThrow(NotFoundException);
  });

  it("allows Admin, Director and system_admin to update deletion lifecycle", () => {
    expect(() => policy.assertCanUpdateDeletionRequest(admin)).not.toThrow();
    expect(() => policy.assertCanUpdateDeletionRequest(director)).not.toThrow();
    expect(() =>
      policy.assertCanUpdateDeletionRequest(systemAdmin),
    ).not.toThrow();
    expect(() => policy.assertCanUpdateDeletionRequest(manager)).toThrow(
      ForbiddenException,
    );
    expect(() => policy.assertCanUpdateDeletionRequest(client)).toThrow(
      ForbiddenException,
    );
  });

  it("enforces deletion lifecycle transitions", () => {
    expect(() =>
      policy.assertValidTransition("pending", "processing"),
    ).not.toThrow();
    expect(() =>
      policy.assertValidTransition("pending", "cancelled"),
    ).not.toThrow();
    expect(() =>
      policy.assertValidTransition("processing", "completed"),
    ).not.toThrow();
    expect(() =>
      policy.assertValidTransition("processing", "rejected"),
    ).not.toThrow();
    expect(() => policy.assertValidTransition("pending", "completed")).toThrow(
      ForbiddenException,
    );
    expect(() =>
      policy.assertValidTransition("completed", "processing"),
    ).toThrow(ForbiddenException);
  });
});
