import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { StaffService } from "./staff.service";

describe("StaffService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertManagerOnly: jest.fn(),
    };
    const service = new StaffService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, audit, policy };
  };

  it("enforces manager/admin role-creation limits", async () => {
    const { service } = createService();

    // Администратор (ниже Управляющего) не управляет ролями вовсе.
    await expect(
      service.createStaff(
        { userId: "admin-a", role: "admin" as const },
        {
          firstName: "Ольга",
          lastName: "Смирнова",
          email: "staff-admin@example.com",
          role: "manager",
        },
      ),
    ).rejects.toThrow("Недостаточно прав");

    // Управляющий не может создать manager или system_admin (роль >= своей).
    await expect(
      service.createStaff(actor, {
        firstName: "Ольга",
        lastName: "Смирнова",
        email: "staff@example.com",
        role: "system_admin",
      }),
    ).rejects.toThrow("Недостаточно прав");

  });

  it("creates staff profiles for privileged roles (system_admin)", async () => {
    const adminActor = { userId: "sys-a", role: "system_admin" as const };
    const { service, query, audit } = createService([
      {
        id: "profile-a",
        userId: "user-a",
        email: "staff@example.com",
        role: "system_admin",
        firstName: "Ольга",
        lastName: "Смирнова",
        phone: "+79992222222",
        avatarFileId: null,
        emailOtp2faEnabled: false,
        createdAt: "2026-06-13T00:00:00.000Z",
        updatedAt: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createStaff(adminActor, {
        firstName: " Ольга ",
        lastName: " Смирнова ",
        email: "Staff@Example.com",
        phone: "+79992222222",
        role: "system_admin",
      }),
    ).resolves.toMatchObject({
      id: "profile-a",
      email: "staff@example.com",
      role: "system_admin",
    });

    expect(query.mock.calls[0][1]).toEqual([
      "staff@example.com",
      "Ольга Смирнова",
      "+79992222222",
      "system_admin",
      "Ольга",
      "Смирнова",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.staff_created",
        entityType: "profile",
        entityId: "profile-a",
      }),
    );
  });

  it("rejects staff edits from roles below admin", async () => {
    const { service } = createService();

    await expect(
      service.updateStaff({ userId: "teacher-a", role: "teacher" }, "staff-a", {
        firstName: "Ольга",
      }),
    ).rejects.toThrow("Недостаточно прав");
  });

  it("updates staff profile and CRM fields, changing the role as system_admin", async () => {
    const sysActor = { userId: "sys-a", role: "system_admin" as const };
    const { service, query, audit } = createService([
      {
        id: "staff-a",
        role: "manager",
        position: "Операционный управляющий",
        status: "working",
        custom_data: { birthday: "1990-06-01", telegram: "@staff" },
        profile_id: "profile-a",
        profile_user_id: "user-a",
        app_role: "manager",
        is_app_account: true,
        first_name: "Ольга",
        last_name: "Смирнова",
        email: "staff@example.com",
        phone: "+79992222222",
        branches: [{ id: "branch-a", name: "Центр" }],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.updateStaff(sysActor, "staff-a", {
        firstName: " Ольга ",
        lastName: " Смирнова ",
        phone: "+79992222222",
        email: "Staff@Example.com",
        role: "manager",
        position: " Операционный управляющий ",
        status: "working",
        customDataPatch: { telegram: "@staff" },
      }),
    ).resolves.toMatchObject({
      id: "staff-a",
      role: "manager",
      position: "Операционный управляющий",
      status: "working",
      customData: { birthday: "1990-06-01", telegram: "@staff" },
      firstName: "Ольга",
      lastName: "Смирнова",
      email: "staff@example.com",
      phone: "+79992222222",
      branches: [{ id: "branch-a", name: "Центр" }],
    });

    // A role change first reads the subject's current role (the canAssignRole
    // guard), so the UPDATE is the SECOND query.
    expect(query.mock.calls[1][1]).toEqual([
      "staff-a",
      "Ольга",
      "Смирнова",
      "+79992222222",
      null,
      "Операционный управляющий",
      "working",
      JSON.stringify({ telegram: "@staff" }),
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.staff_updated",
        entityType: "staff",
        entityId: "staff-a",
      }),
    );
  });

  it("lets an admin edit a strictly lower teacher record", async () => {
    const adminActor = { userId: "admin-a", role: "admin" as const };
    const { service, query } = createService([
      {
        id: "staff-a",
        role: "teacher",
        position: "Педагог",
        status: "working",
        custom_data: {},
        profile_id: "profile-a",
        profile_user_id: "user-a",
        app_role: "teacher",
        is_app_account: true,
        first_name: "Пётр",
        last_name: "Ким",
        email: "teacher@example.com",
        phone: "+79990000000",
        branches: [],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.updateStaff(adminActor, "staff-a", { phone: "+79991112233" }),
    ).resolves.toMatchObject({ id: "staff-a" });

    expect(query).toHaveBeenCalledTimes(2);
  });

  it("keeps an unchanged imported display role as a no-op", async () => {
    const adminActor = { userId: "admin-a", role: "admin" as const };
    const { service, query } = createService([
      {
        id: "staff-a",
        role: "Ответственный",
        position: null,
        status: "Работает",
        custom_data: {},
        profile_id: null,
        profile_user_id: null,
        app_role: null,
        is_app_account: false,
        first_name: "Иван",
        last_name: null,
        email: null,
        phone: null,
        branches: [],
        created_at: "2026-07-18T00:00:00.000Z",
      },
    ]);

    await expect(
      service.updateStaff(adminActor, "staff-a", {
        role: "Ответственный",
        phone: "+79990000000",
      }),
    ).resolves.toMatchObject({
      id: "staff-a",
      role: "Ответственный",
      status: "Работает",
    });

    expect(query).toHaveBeenCalledTimes(2);
    expect(query.mock.calls[1][1][4]).toBeNull();
  });

  it.each([
    ["admin", "admin"],
    ["admin", "manager"],
    ["manager", "manager"],
    ["manager", "director"],
    ["director", "director"],
  ] as const)(
    "forbids %s from mutating non-lower %s staff",
    async (actorRole, targetRole) => {
      const { service, query } = createService([
        { role: targetRole, app_role: targetRole, email: "staff@example.com" },
      ]);

      await expect(
        service.updateStaff(
          { userId: `${actorRole}-a`, role: actorRole },
          "staff-a",
          { phone: "+79990000000" },
        ),
      ).rejects.toThrow("Недостаточно прав");
      expect(query).toHaveBeenCalledTimes(1);
    },
  );

  it.each([
    ["manager", "admin"],
    ["director", "manager"],
    ["system_admin", "director"],
    ["system_admin", "system_admin"],
  ] as const)(
    "lets %s mutate an authorized %s staff target",
    async (actorRole, targetRole) => {
      const row = {
        id: "staff-a",
        role: targetRole,
        position: null,
        status: "working",
        custom_data: {},
        profile_id: "profile-a",
        profile_user_id: "user-a",
        app_role: targetRole,
        is_app_account: true,
        first_name: "Иван",
        last_name: null,
        email: "staff@example.com",
        phone: "+79990000000",
        branches: [],
        created_at: "2026-07-18T00:00:00.000Z",
      };
      const { service, query } = createService([row]);

      await expect(
        service.updateStaff(
          { userId: `${actorRole}-a`, role: actorRole },
          "staff-a",
          { position: "Новая должность" },
        ),
      ).resolves.toMatchObject({ id: "staff-a" });
      expect(query).toHaveBeenCalledTimes(2);
    },
  );

  it("never changes the auth email through a staff-card save", async () => {
    const { service, query } = createService([
      {
        role: "manager",
        app_role: "manager",
        profile_user_id: "user-a",
        email: "owner@example.com",
      },
    ]);

    await expect(
      service.updateStaff(
        { userId: "sys-a", role: "system_admin" },
        "staff-a",
        { email: "attacker@example.com" },
      ),
    ).rejects.toThrow("Email для входа нельзя изменить");
    expect(query).toHaveBeenCalledTimes(1);
  });

  it.each(["working", "active", "Работает", "работает", "активен"])(
    "preserves active staff status spelling: %s",
    async (status) => {
      const row = {
        id: "staff-a",
        role: "admin",
        position: null,
        status,
        custom_data: {},
        profile_id: "profile-a",
        profile_user_id: "user-a",
        app_role: "admin",
        is_app_account: true,
        first_name: "Иван",
        last_name: null,
        email: "staff@example.com",
        phone: null,
        branches: [],
        created_at: "2026-07-18T00:00:00.000Z",
      };
      const { service, query } = createService([row]);

      await expect(
        service.updateStaff(
          { userId: "manager-a", role: "manager" },
          "staff-a",
          { status },
        ),
      ).resolves.toMatchObject({ status });
      expect(query.mock.calls[1][1][6]).toBe(status);
    },
  );

  it("rejects changing an imported display role to an arbitrary label", async () => {
    const { service } = createService([{ role: "Ответственный" }]);

    await expect(
      service.updateStaff(
        { userId: "sys-a", role: "system_admin" },
        "staff-a",
        { role: "Главный ответственный" },
      ),
    ).rejects.toThrow("Недостаточно прав");
  });

  it("blocks an admin from changing a staff member's role (admin manages no roles)", async () => {
    const adminActor = { userId: "admin-a", role: "admin" as const };
    const { service } = createService([{ role: "teacher" }]);

    await expect(
      service.updateStaff(adminActor, "staff-a", { role: "manager" }),
    ).rejects.toThrow("Недостаточно прав");
  });

  it("limits the responsible picker to linked active admin/manager/director users", async () => {
    const { service, query, policy } = createService([
      { id: "admin-a", display_name: "Анна", role: "admin" },
    ]);

    await expect(
      service.listStaffPicker(actor, {
        search: " анна ",
        roles: "admin,system_admin,director",
      }),
    ).resolves.toEqual([
      { id: "admin-a", displayName: "Анна", role: "admin" },
    ]);

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("join app.profiles p");
    expect(query.mock.calls[0][0]).toContain("join app.staff_members sm");
    expect(query.mock.calls[0][0]).toContain(
      "lower(btrim(sm.status)) = any($2::text[])",
    );
    expect(query.mock.calls[0][1]).toEqual([
      ["admin", "director"],
      ["working", "active", "работает", "активен"],
      "анна",
    ]);
  });

  it("lists staff with role status authorization and birthday filters", async () => {
    const { service, query, policy } = createService([
      {
        id: "staff-a",
        role: "manager",
        position: "Управляющий",
        status: "working",
        custom_data: { birthday: "1990-06-01" },
        profile_id: "profile-a",
        profile_user_id: "user-a",
        app_role: "manager",
        is_app_account: true,
        first_name: "Ольга",
        last_name: "Смирнова",
        email: "staff@example.com",
        phone: "+79992222222",
        branches: [{ id: "branch-a", name: "Центр" }],
        created_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listStaff(actor, {
        branchId: "branch-a",
        q: "ольга",
        role: "manager",
        status: "working",
        appRole: "manager",
        authorization: "app",
        birthdayMonth: 6,
        limit: 15,
      }),
    ).resolves.toEqual({
      items: [
        {
          id: "staff-a",
          role: "manager",
          position: "Управляющий",
          status: "working",
          customData: { birthday: "1990-06-01" },
          profileId: "profile-a",
          profileUserId: "user-a",
          appRole: "manager",
          isAppAccount: true,
          firstName: "Ольга",
          lastName: "Смирнова",
          email: "staff@example.com",
          phone: "+79992222222",
          branches: [{ id: "branch-a", name: "Центр" }],
          createdAt: "2026-06-13T00:00:00.000Z",
        },
      ],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "branch-a",
      "ольга",
      "manager",
      "working",
      "manager",
      "app",
      6,
      15,
    ]);
  });
});
