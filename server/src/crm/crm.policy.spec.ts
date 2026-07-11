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

  it("allows admin to perform operational CRM work but still blocks non-staff", () => {
    expect(() =>
      policy.assertManagerOnly({ userId: "m", role: "manager" }),
    ).not.toThrow();
    expect(() =>
      policy.assertManagerOnly({ userId: "s", role: "system_admin" }),
    ).not.toThrow();
    expect(() =>
      policy.assertManagerOnly({ userId: "a", role: "admin" }),
    ).not.toThrow();
    expect(() =>
      policy.assertManagerOnly({ userId: "t", role: "teacher" }),
    ).toThrow(ForbiddenException);
  });

  it("allows admin to read operational finance records", () => {
    expect(() =>
      policy.assertCanReadFinance({ userId: "m", role: "manager" }, "client-b"),
    ).not.toThrow();
    expect(() =>
      policy.assertCanReadFinance({ userId: "a", role: "admin" }, "client-b"),
    ).not.toThrow();
  });

  // KVA-238 + KVA-239: зарплатный модуль — часть общешкольных финансов,
  // доступ унифицирован: только director/system_admin (manager отрезан
  // решением заказчика 2026-07-10).
  it("restricts payroll to director and system_admin only", () => {
    expect(() =>
      policy.assertCanReadPayroll({ userId: "s", role: "system_admin" }),
    ).not.toThrow();
    expect(() =>
      policy.assertCanReadPayroll({ userId: "d", role: "director" }),
    ).not.toThrow();
    for (const role of ["manager", "admin", "teacher", "client"] as const) {
      expect(() =>
        policy.assertCanReadPayroll({ userId: "u", role }),
      ).toThrow(ForbiddenException);
    }
  });

  // KVA-239: общешкольные финансы — только director/system_admin.
  describe("assertCanReadSchoolFinance — общешкольные финансы", () => {
    it("allows director and system_admin", () => {
      expect(() =>
        policy.assertCanReadSchoolFinance({ userId: "d", role: "director" }),
      ).not.toThrow();
      expect(() =>
        policy.assertCanReadSchoolFinance({
          userId: "s",
          role: "system_admin",
        }),
      ).not.toThrow();
    });

    it("forbids manager, admin, teacher and client", () => {
      for (const role of ["manager", "admin", "teacher", "client"] as const) {
        expect(() =>
          policy.assertCanReadSchoolFinance({ userId: "u", role }),
        ).toThrow(ForbiddenException);
      }
    });

    it("director keeps manager-tier card finance access (director >= manager)", () => {
      expect(() =>
        policy.assertCanReadStudentFinance({ userId: "d", role: "director" }),
      ).not.toThrow();
      expect(() => policy.assertManagerOnly({ userId: "d", role: "director" }))
        .not.toThrow();
      expect(() => policy.assertCanWriteCrm({ userId: "d", role: "director" }))
        .not.toThrow();
    });

    it("manager keeps card finance access (карточные финансы не отрезаны)", () => {
      expect(() =>
        policy.assertCanReadStudentFinance({ userId: "m", role: "manager" }),
      ).not.toThrow();
      expect(() =>
        policy.assertCanReadFinance({ userId: "m", role: "manager" }, "x"),
      ).not.toThrow();
    });
  });
});
