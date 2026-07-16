import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { TeachersService } from "./teachers.service";

describe("TeachersService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanWriteCrm: jest.fn(),
      assertCanReadPayroll: jest.fn(),
    };
    const service = new TeachersService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, audit, policy };
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
      },
    ]);

    await expect(
      service.createTeacher(actor, {
        firstName: " Мария ",
        lastName: " Петрова ",
        email: "Teacher@Example.com",
        phone: "+79991111111",
        specialization: " Вокал ",
      }),
    ).resolves.toMatchObject({
      id: "teacher-a",
      firstName: "Мария",
      specialization: "Вокал",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "Мария",
      "Петрова",
      "teacher@example.com",
      "Мария Петрова",
      "+79991111111",
      "active",
      "Вокал",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.teacher_created",
        entityType: "teacher",
        entityId: "teacher-a",
      }),
    );
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
    ).resolves.toEqual({
      items: [
        {
          id: "teacher-a",
          status: "active",
          specialization: "Фортепиано",
          profileId: "profile-teacher-a",
          profileUserId: "teacher-user-a",
          firstName: "Мария",
          lastName: "Петрова",
          email: "teacher@example.com",
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
    ).resolves.toEqual({
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
          email: "teacher@example.com",
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
      },
    ]);

    await expect(
      service.updateTeacher(actor, "teacher-a", {
        firstName: " Мария ",
        lastName: " Петрова ",
        email: "Teacher@Example.com",
        phone: "+79991111111",
        specialization: " Вокал ",
      }),
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
      "Вокал",
      "{}", // KVA-238: пустой customDataPatch
      null, // KVA-238: salary не передан
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.teacher_updated",
        entityType: "teacher",
        entityId: "teacher-a",
      }),
    );
  });
});
