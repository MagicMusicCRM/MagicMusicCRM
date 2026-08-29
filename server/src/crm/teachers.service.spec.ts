import { AuditService } from "../audit/audit.service";
import { ForbiddenException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { PersonAccountService } from "./person-account.service";
import { TeachersService } from "./teachers.service";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";

describe("TeachersService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (
    rows: Record<string, unknown>[] = [],
    policyOverride?: CrmPolicy,
    authoritativeRole: "manager" | "director" | "system_admin" = "director",
  ) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const transactionQuery = jest.fn(
      (sql: string, params?: unknown[]) => {
        if (sql.includes("select id from app.users")) {
          return Promise.resolve({ rows: [{ id: params?.[0] }] });
        }
        if (sql.includes("from app.role_packages package")) {
          return Promise.resolve({ rows: [{ id: "package-director" }] });
        }
        if (sql.includes("select\n        user_account.role")) {
          return Promise.resolve({
            rows: [
              {
                role: authoritativeRole,
                active: true,
                definition_active: true,
                role_effect: "allow",
                override_effect: null,
              },
            ],
          });
        }
        return query(sql, params);
      },
    );
    const transaction = jest.fn(
      (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: transactionQuery }),
    );
    const database = { query, transaction };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy =
      policyOverride ??
      ({
        assertCanWriteCrm: jest.fn(),
        assertCanReadPayroll: jest.fn(),
        assertCanManagePayrollHistory: jest.fn(),
        assertCanManageSystemSettings: jest.fn(),
      } as unknown as CrmPolicy);
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
    return {
      service,
      query,
      transaction,
      transactionQuery,
      audit,
      policy,
      accounts,
      integrity,
    };
  };

  describe("teacher DTO composition", () => {
    const credentialRow = {
      id: "teacher-credentials",
      status: "active",
      specialization: "Вокал",
      profile_id: "profile-credentials",
      profile_user_id: "user-credentials",
      first_name: "Ирина",
      last_name: "Петрова",
      phone: "+79991111111",
      email: "teacher@example.com",
      password_configured: true,
      password_changed_at: "2026-08-14T10:00:00.000Z",
      email_changed_at: "2026-08-14T09:00:00.000Z",
    };
    const expectedCredentials = {
      email: "teacher@example.com",
      passwordConfigured: true,
      passwordChangedAt: "2026-08-14T10:00:00.000Z",
      emailChangedAt: "2026-08-14T09:00:00.000Z",
    };
    const credentialKeys = Object.keys(expectedCredentials);

    it.each([
      ["client", {}],
      ["teacher", {}],
      ["admin", {}],
      ["manager", {}],
      ["director", expectedCredentials],
      ["system_admin", expectedCredentials],
    ] as const)("exposes credential keys only to the exact allowed role=%s", async (role, expected) => {
      const { service } = createService([credentialRow]);

      const { items } = await service.listTeachers(
        { userId: `${role}-a`, role },
        { limit: 1 },
      );
      const teacher = items[0]!;
      const credentials = Object.fromEntries(
        credentialKeys
          .filter((key) => Object.prototype.hasOwnProperty.call(teacher, key))
          .map((key) => [key, teacher[key]]),
      );

      expect(credentials).toEqual(expected);
    });

    it("preserves the full DTO values, insertion order, coercions, and references", async () => {
      const customData = { level: "advanced" };
      const branches = [{ id: "branch-a", name: "Центр" }];
      const disciplines = [
        { id: "discipline-a", name: "Вокал", lifecycleState: "active" },
      ];
      const assignedBranches = [{ id: "branch-b", name: "Север" }];
      const passwordChangedAt = new Date("2026-08-14T10:00:00.000Z");
      const emailChangedAt = new Date("2026-08-14T09:00:00.000Z");
      const offboardedAt = new Date("2026-08-15T11:00:00.000Z");
      const createdAt = new Date("2026-06-15T00:00:00.000Z");
      const row = {
        id: "teacher-full",
        status: "archived",
        specialization: "Вокал",
        profile_id: "profile-full",
        profile_user_id: "user-full",
        first_name: "Мария",
        last_name: "Петрова",
        phone: "+79992222222",
        email: " Teacher@Example.com ",
        password_configured: true,
        password_changed_at: passwordChangedAt,
        email_changed_at: emailChangedAt,
        custom_data: customData,
        app_role: "teacher",
        is_app_account: true,
        lifecycle_state: "archived",
        version: "7",
        offboarded_at: offboardedAt,
        offboard_reason: "contract-ended",
        branches,
        students_count: "12.5",
        lessons_count: "-0",
        rating: "not-a-number",
        created_at: createdAt,
        salary: "not-a-number",
        current_rate: "-0",
        disciplines,
        assigned_branches: assignedBranches,
      };
      const { service } = createService([row]);

      const { items } = await service.listTeachers(
        { userId: "director-a", role: "director" },
        { limit: 1 },
      );
      const teacher = items[0]!;

      expect(teacher).toStrictEqual({
        id: "teacher-full",
        status: "archived",
        specialization: "Вокал",
        profileId: "profile-full",
        profileUserId: "user-full",
        firstName: "Мария",
        lastName: "Петрова",
        phone: "+79992222222",
        email: " Teacher@Example.com ",
        passwordConfigured: true,
        passwordChangedAt,
        emailChangedAt,
        customData,
        appRole: "teacher",
        isAppAccount: true,
        lifecycleState: "archived",
        version: 7,
        offboardedAt,
        offboardReason: "contract-ended",
        branches,
        studentsCount: 12.5,
        lessonsCount: -0,
        rating: 0,
        createdAt,
        salary: NaN,
        currentRate: -0,
        disciplines,
        assignedBranches,
      });
      expect(Object.keys(teacher)).toEqual([
        "id",
        "status",
        "specialization",
        "profileId",
        "profileUserId",
        "firstName",
        "lastName",
        "phone",
        "email",
        "passwordConfigured",
        "passwordChangedAt",
        "emailChangedAt",
        "customData",
        "appRole",
        "isAppAccount",
        "lifecycleState",
        "version",
        "offboardedAt",
        "offboardReason",
        "branches",
        "studentsCount",
        "lessonsCount",
        "rating",
        "createdAt",
        "salary",
        "currentRate",
        "disciplines",
        "assignedBranches",
      ]);
      expect(teacher.customData).toBe(customData);
      expect(teacher.branches).toBe(branches);
      expect(teacher.disciplines).toBe(disciplines);
      expect(teacher.assignedBranches).toBe(assignedBranches);
      expect(teacher.passwordChangedAt).toBe(passwordChangedAt);
      expect(teacher.emailChangedAt).toBe(emailChangedAt);
      expect(teacher.offboardedAt).toBe(offboardedAt);
      expect(teacher.createdAt).toBe(createdAt);
      expect(teacher.lessonsCount).toBe(-0);
      expect(teacher.salary).toBeNaN();
      expect(teacher.currentRate).toBe(-0);
    });

    it("preserves sparse and null omission/default distinctions", async () => {
      const { service } = createService([
        {
          id: undefined,
          status: null,
          specialization: null,
          profile_id: undefined,
          profile_user_id: null,
          first_name: undefined,
          last_name: null,
          phone: undefined,
          email: null,
          password_configured: null,
          password_changed_at: undefined,
          email_changed_at: null,
          custom_data: null,
          app_role: null,
          is_app_account: null,
          lifecycle_state: undefined,
          version: null,
          offboarded_at: undefined,
          offboard_reason: null,
          branches: null,
          students_count: null,
          lessons_count: undefined,
          rating: null,
          created_at: undefined,
          salary: null,
          current_rate: null,
          disciplines: null,
          assigned_branches: null,
        },
      ]);

      const { items } = await service.listTeachers(
        { userId: "director-a", role: "director" },
        { limit: 1 },
      );

      expect(items[0]).toStrictEqual({
        id: undefined,
        status: null,
        specialization: null,
        profileId: undefined,
        profileUserId: null,
        firstName: undefined,
        lastName: null,
        phone: undefined,
        email: null,
        passwordConfigured: false,
        passwordChangedAt: null,
        emailChangedAt: null,
        customData: {},
        appRole: null,
        isAppAccount: false,
        lifecycleState: "active",
        version: 1,
        offboardedAt: null,
        offboardReason: null,
        branches: [],
        studentsCount: 0,
        rating: null,
        salary: null,
        currentRate: null,
        disciplines: [],
        assignedBranches: [],
      });
      expect(items[0]).not.toHaveProperty("lessonsCount");
      expect(items[0]).not.toHaveProperty("createdAt");
    });

    it("omits every undefined guarded field and retains inverse null fields", async () => {
      const { service } = createService([
        {
          id: "teacher-inverse-sparse",
          status: "active",
          specialization: null,
          profile_id: null,
          profile_user_id: null,
          first_name: null,
          last_name: null,
          phone: null,
          custom_data: undefined,
          app_role: undefined,
          is_app_account: undefined,
          branches: undefined,
          students_count: undefined,
          lessons_count: null,
          rating: undefined,
          created_at: null,
          salary: undefined,
          current_rate: undefined,
          disciplines: undefined,
          assigned_branches: undefined,
        },
      ]);

      const { items } = await service.listTeachers(actor, { limit: 1 });
      const teacher = items[0]!;
      const guardedKeys = [
        "customData",
        "appRole",
        "isAppAccount",
        "branches",
        "studentsCount",
        "lessonsCount",
        "rating",
        "createdAt",
        "salary",
        "currentRate",
        "disciplines",
        "assignedBranches",
      ];

      expect(Object.keys(teacher).filter((key) => guardedKeys.includes(key))).toEqual([
        "lessonsCount",
        "createdAt",
      ]);
      expect({
        lessonsCount: teacher.lessonsCount,
        createdAt: teacher.createdAt,
      }).toStrictEqual({ lessonsCount: 0, createdAt: null });
    });

    it.each([
      ["invalid numeric string", "not-a-number", NaN],
      ["negative-zero string", "-0", -0],
    ] as const)("coerces version from %s through Number", async (_label, version, expected) => {
      const { service } = createService([
        {
          id: "teacher-version",
          status: "active",
          specialization: null,
          profile_id: null,
          profile_user_id: null,
          first_name: null,
          last_name: null,
          phone: null,
          version,
        },
      ]);

      const { items } = await service.listTeachers(actor, { limit: 1 });

      expect(items[0]?.version).toBe(expected);
    });
  });

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
    const { service, query, transaction, transactionQuery, audit, policy } =
      createService([
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
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(transactionQuery).toHaveBeenCalledWith(
      expect.stringContaining("personal_override.user_id"),
      ["director-a", "config.commerce.manage", 1],
    );
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
          capabilityKey: "config.commerce.manage",
        }),
      }),
    );
  });

  it.each([
    ["client", false],
    ["teacher", false],
    ["admin", false],
    ["manager", false],
    ["director", true],
    ["system_admin", true],
  ] as const)(
    "accepts a base-rate profile mutation only for the owner roles: %s",
    async (role, allowed) => {
      const { service, query, integrity } = createService(
        [
          {
            id: "teacher-a",
            status: "active",
            specialization: null,
            custom_data: {},
            salary: null,
            current_rate: "900",
            assigned_branches: [],
            disciplines: [],
          },
        ],
        new CrmPolicy(),
      );
      const mutation = service.updateTeacher(
        { userId: `${role}-a`, role },
        "teacher-a",
        {
          rate: 900,
          rateEffectiveFrom: "2026-08-10",
          payrollExpectedVersion: 0,
          payrollReasonText: "Плановое изменение ставки",
        },
        {
          idempotencyKey: "teacher-rate-001",
          requestId: "request-teacher-rate-001",
        },
      );

      if (allowed) {
        await expect(mutation).resolves.toMatchObject({
          id: "teacher-a",
          currentRate: 900,
        });
        expect(query).toHaveBeenCalledTimes(1);
        expect(integrity.executeVersionedMutation).toHaveBeenCalledTimes(1);
      } else {
        await expect(mutation).rejects.toBeInstanceOf(ForbiddenException);
        expect(query).not.toHaveBeenCalled();
        expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
      }
    },
  );

  it.each(["admin", "manager"] as const)(
    "keeps salary-only profile mutations available to payroll staff: %s",
    async (role) => {
      const { service, integrity } = createService(
        [
          {
            id: "teacher-a",
            status: "active",
            specialization: null,
            custom_data: {},
            salary: "20000",
            current_rate: null,
            assigned_branches: [],
            disciplines: [],
          },
        ],
        new CrmPolicy(),
      );

      await expect(
        service.updateTeacher(
          { userId: `${role}-a`, role },
          "teacher-a",
          {
            salary: 20000,
            payrollExpectedVersion: 0,
            payrollReasonText: "Плановое изменение оклада",
          },
          {
            idempotencyKey: "teacher-salary-001",
            requestId: "request-teacher-salary-001",
          },
        ),
      ).resolves.toMatchObject({ id: "teacher-a", salary: 20000 });
      expect(integrity.executeVersionedMutation).toHaveBeenCalledTimes(1);
    },
  );

  it.each(["admin", "manager"] as const)(
    "rejects an initial base rate from non-owner staff: %s",
    async (role) => {
      const { service, query } = createService([], new CrmPolicy());

      await expect(
        service.createTeacher(
          { userId: `${role}-a`, role },
          {
            firstName: "Мария",
            branchIds: [],
            rate: 900,
          },
        ),
      ).rejects.toBeInstanceOf(ForbiddenException);
      expect(query).not.toHaveBeenCalled();
    },
  );

  it("rejects initial rate creation atomically after a Director is demoted in the database", async () => {
    const { service, query, transaction } = createService(
      [],
      new CrmPolicy(),
      "manager",
    );

    await expect(
      service.createTeacher(
        { userId: "director-a", role: "director" },
        {
          firstName: "Мария",
          branchIds: [],
          rate: 900,
        },
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CAPABILITY_DENIED",
        capabilityKey: "config.commerce.manage",
        source: "hard-invariant",
      }),
    });
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(query).not.toHaveBeenCalled();
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
