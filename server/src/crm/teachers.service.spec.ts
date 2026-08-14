import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { PersonAccountService } from "./person-account.service";
import { TeachersService } from "./teachers.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";

describe("TeachersService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanWriteCrm: jest.fn(),
      assertCanReadPayroll: jest.fn(),
      assertCanManageSystemSettings: jest.fn(),
    };
    const accounts = {
      resolveInitialRole: jest
        .fn()
        .mockImplementation(
          (_actor, type, role) =>
            role ?? (type === "teacher" ? "teacher" : "admin"),
        ),
      prepareCreate: jest.fn().mockImplementation((email?: string) =>
        Promise.resolve({
          email: email?.trim().toLowerCase() ?? null,
          passwordHash: email ? "hashed-password" : null,
          passwordCiphertext: email ? "encrypted-password" : null,
          isAppAccount: Boolean(email),
        }),
      ),
      manageAccess: jest.fn().mockResolvedValue({}),
    };
    const integrity = {
      executeVersionedMutation: jest.fn(async (command: any) => ({
        resultRef: await command.mutate({ query } as any, 1),
        version: 1,
        replayed: false,
        auditId: "audit-a",
        eventId: "event-a",
      })),
    };
    const service = new TeachersService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      accounts as unknown as PersonAccountService,
      integrity as unknown as PlatformIntegrityService,
    );
    return { service, query, audit, policy, accounts, integrity };
  };

  describe("getTeacher", () => {
    it("narrows the shared list query to one id", async () => {
      const { service, query } = createService([
        {
          id: "teacher-a",
          status: "active",
          specialization: "Вокал",
          custom_data: {},
          first_name: "Иван",
          last_name: "Петров",
        },
      ]);

      const teacher = await service.getTeacher(actor, "teacher-a");

      expect(teacher.id).toBe("teacher-a");
      // Reuses listTeachers so the role visibility clause stays single-source.
      expect(String(query.mock.calls[0][0])).toContain("t.id = $15");
      expect(query.mock.calls[0][1]).toContain("teacher-a");
    });

    it("throws when the teacher is absent or invisible to the actor", async () => {
      const { service } = createService([]);

      await expect(service.getTeacher(actor, "missing")).rejects.toThrow(
        "Преподаватель не найден.",
      );
    });
  });

  it("creates teachers through v3 identity/profile contract and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
        custom_data: { levels: ["Начальный"] },
        salary: "15000.00",
        current_rate: "750.00",
      },
    ]);

    await expect(
      service.createTeacher(
        { userId: "director-a", role: "director" },
        {
          firstName: " Мария ",
          lastName: " Петрова ",
          email: "Teacher@Example.com",
          password: "password-123",
          accessRole: "admin",
          phone: "+79991111111",
          branchIds: ["branch-a"],
          disciplineIds: ["discipline-a"],
          customDataPatch: { levels: ["Начальный"] },
          salary: 15000,
          rate: 750,
          rateEffectiveFrom: "2026-08-01",
        },
      ),
    ).resolves.toMatchObject({
      id: "teacher-a",
      firstName: "Мария",
      specialization: "Вокал",
    });

    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledWith({
      userId: "director-a",
      role: "director",
    });
    expect(query.mock.calls[0][1]).toEqual([
      "Мария",
      "Петрова",
      "teacher@example.com",
      "Мария Петрова",
      "+79991111111",
      "active",
      "hashed-password",
      ["branch-a"],
      ["discipline-a"],
      "director-a",
      '{"levels":["Начальный"]}',
      15000,
      750,
      "2026-08-01",
      true,
      "admin",
      "encrypted-password",
    ]);
    expect(String(query.mock.calls[0][0])).toContain("inserted_rate as");
    expect(String(query.mock.calls[0][0])).toContain("references_valid");
    expect(String(query.mock.calls[0][0])).not.toContain(
      "app.branch_disciplines",
    );
    expect(policy.assertCanReadPayroll).toHaveBeenCalledWith({
      userId: "director-a",
      role: "director",
    });
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.teacher_created",
        entityType: "teacher",
        entityId: "teacher-a",
      }),
    );
  });

  it("redacts login email and password metadata outside Director/system_admin", async () => {
    const { service } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        first_name: "Иван",
        last_name: "Петров",
        email: "teacher@example.com",
        password_configured: true,
        password_changed_at: "2026-08-14T10:00:00.000Z",
        email_changed_at: "2026-08-14T09:00:00.000Z",
      },
    ]);

    const teacher = await service.getTeacher(actor, "teacher-a");

    expect(teacher).not.toHaveProperty("email");
    expect(teacher).not.toHaveProperty("passwordConfigured");
    expect(teacher).not.toHaveProperty("passwordChangedAt");
  });

  it("creates a teacher without informational disciplines", async () => {
    const { service, query } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: null,
        profile_id: "profile-a",
        profile_user_id: null,
        first_name: "Мария",
        last_name: "Петрова",
      },
    ]);

    await expect(
      service.createTeacher(
        { userId: "director-a", role: "director" },
        {
          firstName: "Мария",
          lastName: "Петрова",
          branchIds: ["branch-a"],
        },
      ),
    ).resolves.toMatchObject({ id: "teacher-a", specialization: null });

    expect(query.mock.calls[0][1][8]).toEqual([]);
    expect(query.mock.calls[0][1][15]).toBe("teacher");
  });

  it("lists teachers for clients through individual or group relationships", async () => {
    const clientActor = { userId: "client-a", role: "client" as const };
    const { service, query } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Фортепиано",
        profile_id: "profile-teacher-a",
        profile_user_id: "teacher-user-a",
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
      },
    ]);

    await expect(
      service.listTeachers(clientActor, { limit: 10 }),
    ).resolves.toMatchObject({
      items: [
        {
          id: "teacher-a",
          status: "active",
          specialization: "Фортепиано",
          profileId: "profile-teacher-a",
          profileUserId: "teacher-user-a",
          firstName: "Мария",
          lastName: "Петрова",
          phone: "+79991111111",
        },
      ],
    });

    // Client visibility now via EXISTS (individual lessons OR group membership),
    // replacing the former cartesian LEFT JOINs + DISTINCT.
    expect(query.mock.calls[0][0]).toContain("csp.user_id = $2");
    expect(query.mock.calls[0][0]).toContain("cgsp.user_id = $2");
    expect(query.mock.calls[0][0]).not.toContain("select distinct");
    expect(query.mock.calls[0][1]).toEqual([
      "client",
      "client-a",
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      10,
      // teacherId: null for a list scan, set only by getTeacher.
      null,
    ]);
  });

  it("lists teachers with HolliHop staff filters and aggregate metadata", async () => {
    const { service, query } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        custom_data: {
          disciplines: ["Вокал"],
          levels: ["Начальный"],
          categories: ["Взрослые"],
          rating: 4.8,
        },
        profile_id: "profile-teacher-a",
        profile_user_id: "teacher-user-a",
        app_role: "teacher",
        is_app_account: false,
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
        branches: [{ id: "branch-a", name: "Центр" }],
        students_count: "12",
        lessons_count: "34",
        rating: "4.8",
        created_at: "2026-06-15T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listTeachers(actor, {
        q: "мария",
        status: "active",
        branchId: "branch-a",
        discipline: "Вокал",
        level: "Начальный",
        category: "Взрослые",
        appRole: "teacher",
        authorization: "technical",
        ratingFrom: 4,
        ratingTo: 5,
        birthdayMonth: 6,
        limit: 20,
      }),
    ).resolves.toMatchObject({
      items: [
        {
          id: "teacher-a",
          status: "active",
          specialization: "Вокал",
          customData: {
            disciplines: ["Вокал"],
            levels: ["Начальный"],
            categories: ["Взрослые"],
            rating: 4.8,
          },
          profileId: "profile-teacher-a",
          profileUserId: "teacher-user-a",
          appRole: "teacher",
          isAppAccount: false,
          firstName: "Мария",
          lastName: "Петрова",
          phone: "+79991111111",
          branches: [{ id: "branch-a", name: "Центр" }],
          studentsCount: 12,
          lessonsCount: 34,
          rating: 4.8,
          createdAt: "2026-06-15T00:00:00.000Z",
        },
      ],
    });

    expect(query.mock.calls[0][0]).toContain("app.user_crm_links link");
    expect(query.mock.calls[0][0]).toContain("app.teacher_branches assignment");
    expect(query.mock.calls[0][0]).toContain(
      "assignment.active_from <= current_date",
    );
    expect(query.mock.calls[0][1]).toEqual([
      "manager",
      "manager-a",
      "мария",
      "active",
      "branch-a",
      "Вокал",
      "Начальный",
      "Взрослые",
      "teacher",
      "technical",
      4,
      5,
      6,
      20,
      // teacherId: null for a list scan, set only by getTeacher.
      null,
    ]);
  });

  it("updates teachers through CRM write policy and audit", async () => {
    const { service, query, audit, policy, integrity } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111111",
        salary: "20000.00",
        current_rate: "900.00",
      },
    ]);

    await expect(
      service.updateTeacher(
        actor,
        "teacher-a",
        {
          firstName: " Мария ",
          lastName: " Петрова ",
          email: "Teacher@Example.com",
          phone: "+79991111111",
          customDataPatch: { categories: ["Дети"] },
          salary: 20000,
          rate: 900,
          rateEffectiveFrom: "2026-08-10",
          payrollExpectedVersion: 0,
          payrollReasonText: "Плановое изменение условий",
        },
        {
          idempotencyKey: "teacher-update-001",
          requestId: "request-teacher-update-001",
        },
      ),
    ).resolves.toMatchObject({
      id: "teacher-a",
      firstName: "Мария",
      specialization: "Вокал",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "teacher-a",
      "Мария",
      "Петрова",
      "+79991111111",
      "teacher@example.com",
      null,
      '{"categories":["Дети"]}',
      20000,
      null, // disciplineIds
      null, // branchIds
      900,
      "2026-08-10",
      "manager-a",
    ]);
    expect(String(query.mock.calls[0][0])).toContain("inserted_rate as");
    expect(policy.assertCanReadPayroll).toHaveBeenCalledWith(actor);
    expect(audit.record).not.toHaveBeenCalled();
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.teacher.update-with-payroll",
        aggregateType: "teacher:payroll",
        aggregateId: "teacher-a",
        expectedVersion: 0,
        authorization: expect.objectContaining({
          capabilityKey: "commerce.teacher_payroll.write",
        }),
      }),
    );
  });

  it("rejects a payroll edit without version and audit reason", async () => {
    const { service, query, integrity } = createService([]);

    await expect(
      service.updateTeacher(actor, "teacher-a", { rate: 900 }),
    ).rejects.toThrow("версия расчётов преподавателя не указана");
    expect(query).not.toHaveBeenCalled();
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("keeps ordinary profile updates on the CRM audit path", async () => {
    const { service, audit, integrity } = createService([
      {
        id: "teacher-a",
        status: "active",
        specialization: "Вокал",
        profile_id: "profile-a",
        profile_user_id: "user-a",
        first_name: "Мария",
        last_name: "Петрова",
        email: "teacher@example.com",
        phone: "+79991111112",
      },
    ]);

    await service.updateTeacher(actor, "teacher-a", {
      phone: "+79991111112",
    });

    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.teacher_updated",
        entityType: "teacher",
        entityId: "teacher-a",
      }),
    );
  });
});
