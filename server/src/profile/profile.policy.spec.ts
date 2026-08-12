import { ForbiddenException, NotFoundException } from "@nestjs/common";
import { ProfilePolicy } from "./profile.policy";

describe("ProfilePolicy", () => {
  const policy = new ProfilePolicy();
  const sys = { userId: "sys-a", role: "system_admin" as const };
  const manager = { userId: "mgr-a", role: "manager" as const };
  const admin = { userId: "adm-a", role: "admin" as const };
  const teacher = { userId: "tch-a", role: "teacher" as const };
  const client = { userId: "cli-a", role: "client" as const };

  it("allows users to read their own profile", () => {
    expect(() => policy.assertCanReadProfile(client, "cli-a")).not.toThrow();
  });

  it("hides foreign profiles from clients", () => {
    expect(() => policy.assertCanReadProfile(client, "user-b")).toThrow(
      NotFoundException,
    );
  });

  it("allows operational staff to list profiles, forbids non-staff", () => {
    expect(() => policy.assertCanListProfiles(manager)).not.toThrow();
    expect(() => policy.assertCanListProfiles(admin)).not.toThrow();
    expect(() => policy.assertCanListProfiles(sys)).not.toThrow();
    expect(() => policy.assertCanListProfiles(teacher)).toThrow(
      ForbiddenException,
    );
    expect(() => policy.assertCanListProfiles(client)).toThrow(
      ForbiddenException,
    );
  });
});
