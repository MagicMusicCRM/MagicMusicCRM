import { ForbiddenException, NotFoundException } from "@nestjs/common";
import { CrmPolicy } from "./crm.policy";

describe("CrmPolicy", () => {
  const policy = new CrmPolicy();

  it("allows clients to read their own student record", () => {
    expect(() =>
      policy.assertCanReadStudent(
        { userId: "client-a", role: "client" },
        { profileUserId: "client-a", teacherUserIds: [] },
      ),
    ).not.toThrow();
  });

  it("hides foreign student records from clients", () => {
    expect(() =>
      policy.assertCanReadStudent(
        { userId: "client-a", role: "client" },
        { profileUserId: "client-b", teacherUserIds: [] },
      ),
    ).toThrow(NotFoundException);
  });

  it("allows assigned teachers and hides unrelated students", () => {
    expect(() =>
      policy.assertCanReadStudent(
        { userId: "teacher-a", role: "teacher" },
        { profileUserId: "client-a", teacherUserIds: ["teacher-a"] },
      ),
    ).not.toThrow();

    expect(() =>
      policy.assertCanReadStudent(
        { userId: "teacher-b", role: "teacher" },
        { profileUserId: "client-a", teacherUserIds: ["teacher-a"] },
      ),
    ).toThrow(NotFoundException);
  });

  it("restricts CRM writes to manager and admin roles", () => {
    expect(() =>
      policy.assertCanWriteCrm({ userId: "manager-a", role: "manager" }),
    ).not.toThrow();
    expect(() =>
      policy.assertCanWriteCrm({ userId: "client-a", role: "client" }),
    ).toThrow(ForbiddenException);
  });

  it("allows operational reference data for staff only", () => {
    expect(() =>
      policy.assertCanReadOperationalData({
        userId: "teacher-a",
        role: "teacher",
      }),
    ).not.toThrow();
    expect(() =>
      policy.assertCanReadOperationalData({
        userId: "manager-a",
        role: "manager",
      }),
    ).not.toThrow();
    expect(() =>
      policy.assertCanReadOperationalData({
        userId: "client-a",
        role: "client",
      }),
    ).toThrow(ForbiddenException);
  });

  it("hides foreign finance records from clients", () => {
    expect(() =>
      policy.assertCanReadFinance(
        { userId: "client-a", role: "client" },
        "client-b",
      ),
    ).toThrow(NotFoundException);
  });
});
