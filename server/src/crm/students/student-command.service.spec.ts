import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import type { AuditService } from "../../audit/audit.service";
import type { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import type { NotificationsService } from "../../notifications/notifications.service";
import type { RealtimeBus } from "../../realtime/realtime-bus";
import type { ValidatedStudentCreate } from "../clients/client-write.validator";
import type { CrmPolicy } from "../crm.policy";
import type { StudentRow } from "../student-read";
import { StudentCommandService } from "./student-command.service";
import type { StudentMutationExecutor } from "./student-mutation.executor";

describe("StudentCommandService", () => {
  const actor: ActorContext = { userId: "manager-a", role: "manager" };
  const student: StudentRow = {
    id: "student-a",
    status: "active",
    profile_id: "profile-a",
    profile_user_id: "user-a",
    lead_id: null,
    source_id: null,
    source_name: null,
    custom_data: {},
    blacklisted: false,
    blacklist_reason: null,
    first_name: "Анна",
    last_name: "Иванова",
    email: "student@example.com",
    phone: "+79990000000",
    teacher_user_ids: [],
    created_at: "2026-06-13T00:00:00.000Z",
  };

  const createHarness = () => {
    const events: string[] = [];
    const query: jest.Mock<
      Promise<{ rows: unknown[] }>,
      [sql: string, params?: unknown[]]
    > = jest.fn(async (sql: string) => {
      if (
        sql.includes("with eligible_actor as") &&
        sql.includes("update app.students")
      ) {
        events.push("responsible");
        return { rows: [] };
      }
      if (sql.includes("from app.students s")) {
        return { rows: [student] };
      }
      return { rows: [] };
    });
    const database = {
      query,
    };
    const audit = {
      record: jest.fn(async () => {
        events.push("audit");
      }),
    };
    const policy = { assertCanWriteCrm: jest.fn() };
    const notifications = {
      sendEmail: jest.fn(async () => {
        events.push("notification");
        return { queued: true };
      }),
    };
    const realtime = {
      emitCrmChanged: jest.fn(() => {
        events.push("realtime");
      }),
    };
    const mutations = {
      create: jest.fn(async () => {
        events.push("transaction");
        return student;
      }),
      update: jest.fn(async () => {
        events.push("transaction");
        return {
          beforeStudent: {
            status: "lead",
            branch_id: "branch-before",
            first_name: "Старая",
            last_name: "Фамилия",
            phone: "+70000000000",
            email: "old@example.com",
            custom_data: {},
          },
          student,
        };
      }),
    };
    const service = new StudentCommandService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      notifications as unknown as NotificationsService,
      realtime as unknown as RealtimeBus,
      mutations as unknown as StudentMutationExecutor,
    );
    return {
      service,
      events,
      database,
      audit,
      policy,
      notifications,
      realtime,
      mutations,
    };
  };

  it("normalizes create input and publishes only after mutation and fallback", async () => {
    const { service, events, mutations, policy } = createHarness();
    const validated = {
      firstName: "Анна",
      lastName: "Иванова",
      phone: "+79990000000",
      branchId: "branch-a",
      status: "active",
      sourceId: "source-a",
      sourceCanonicalName: "recommendation",
      sourceDisplayName: "Рекомендация",
      customFields: [],
      warnings: [
        {
          field: "phone",
          code: "PHONE_NORMALIZED" as const,
          normalizedValue: "+79990000000",
        },
      ],
    } satisfies ValidatedStudentCreate;

    await expect(
      service.createStudent(
        actor,
        {
          firstName: " Анна ",
          lastName: " Иванова ",
          email: "Student@Example.com",
          phone: " +79990000000 ",
        },
        validated,
      ),
    ).resolves.toEqual(
      expect.objectContaining({
        id: "student-a",
        firstName: "Анна",
        warnings: validated.warnings,
      }),
    );

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(mutations.create).toHaveBeenCalledWith({
      firstName: "Анна",
      lastName: "Иванова",
      email: "student@example.com",
      fullName: "Анна Иванова",
      phone: "+79990000000",
      status: "active",
      leadId: null,
      customDataPatch: {},
      requestedResponsibleId: undefined,
      branchId: null,
      sourceId: "source-a",
      customFields: [],
    });
    expect(events).toEqual(["transaction", "responsible", "audit", "realtime"]);
  });

  it("does not publish or assign fallback responsible when create mutation fails", async () => {
    const { service, database, audit, realtime, mutations } = createHarness();
    mutations.create.mockRejectedValueOnce(new Error("transaction failed"));

    await expect(
      service.createStudent(actor, { firstName: "Анна" }),
    ).rejects.toThrow("transaction failed");

    expect(database.query).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
  });

  it("preserves lead preflight and appeal date before invoking create mutation", async () => {
    const { service, database, mutations } = createHarness();
    database.query
      .mockResolvedValueOnce({
        rows: [
          {
            id: "lead-a",
            custom_data: { appealAt: "2026-05-01" },
            created_at: "2026-04-01T00:00:00.000Z",
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });

    await service.createStudent(actor, {
      firstName: "Анна",
      leadId: "lead-a",
      customDataPatch: {},
    });

    expect(database.query.mock.calls[0]?.[1]).toEqual(["lead-a"]);
    expect(database.query.mock.calls[1]?.[1]).toEqual(["lead-a"]);
    expect(mutations.create).toHaveBeenCalledWith(
      expect.objectContaining({
        leadId: "lead-a",
        customDataPatch: { appealAt: "2026-05-01T00:00:00.000Z" },
      }),
    );
  });

  it("rejects duplicate lead conversion before invoking mutation", async () => {
    const { service, database, mutations } = createHarness();
    database.query
      .mockResolvedValueOnce({
        rows: [{ id: "lead-a", custom_data: {}, created_at: "2026-04-01" }],
      })
      .mockResolvedValueOnce({ rows: [{ id: "student-existing" }] });

    await expect(
      service.createStudent(actor, { firstName: "Анна", leadId: "lead-a" }),
    ).rejects.toThrow("Этот лид уже конвертирован в ученика.");
    expect(mutations.create).not.toHaveBeenCalled();
  });

  it("rejects malformed responsible identity before reading a conversion lead", async () => {
    const { service, database, mutations } = createHarness();

    await expect(
      service.createStudent(actor, {
        firstName: "Анна",
        leadId: "lead-a",
        customDataPatch: { responsibleUserId: "not-a-uuid" },
      }),
    ).rejects.toThrow(
      "responsibleUserId должен быть UUID активного сотрудника.",
    );

    expect(database.query).not.toHaveBeenCalled();
    expect(mutations.create).not.toHaveBeenCalled();
  });

  it("normalizes update input and publishes only after mutation and fallback", async () => {
    const { service, events, mutations } = createHarness();
    const customFields = {
      values: [],
      warnings: [
        {
          field: "phone",
          code: "PHONE_NORMALIZED" as const,
          normalizedValue: "+79990000000",
        },
      ],
    };

    await expect(
      service.updateStudent(
        actor,
        "student-a",
        {
          firstName: " Анна ",
          expectedVersion: 7,
          lastName: " Иванова ",
          phone: " +79990000000 ",
          email: " STUDENT@example.com ",
          status: " active ",
        },
        customFields,
      ),
    ).resolves.toEqual(
      expect.objectContaining({
        id: "student-a",
        warnings: customFields.warnings,
      }),
    );

    expect(mutations.update).toHaveBeenCalledWith({
      studentId: "student-a",
      expectedVersion: 7,
      firstName: "Анна",
      lastName: "Иванова",
      phone: "+79990000000",
      email: "student@example.com",
      status: "active",
      customDataPatch: {},
      requestedResponsibleId: undefined,
      branchId: null,
      clearResponsible: false,
      sourceId: null,
      customFields: [],
    });
    expect(events).toEqual(["transaction", "responsible", "audit", "realtime"]);
  });

  it("does not publish or assign fallback responsible when update mutation fails", async () => {
    const { service, database, audit, realtime, mutations } = createHarness();
    mutations.update.mockRejectedValueOnce(new Error("transaction failed"));

    await expect(
      service.updateStudent(actor, "student-a", {
        expectedVersion: 1,
        firstName: "Анна",
      }),
    ).rejects.toThrow("transaction failed");

    expect(database.query).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
  });

  it("returns a business error when a saved email belongs to another user", async () => {
    const { service, mutations } = createHarness();
    mutations.update.mockRejectedValueOnce({
      code: "23505",
      constraint: "users_email_lower_unique",
    });

    await expect(
      service.updateStudent(actor, "student-a", {
        expectedVersion: 1,
        email: "existing@example.com",
      }),
    ).rejects.toMatchObject({
      status: 400,
      response: expect.objectContaining({
        message: "Пользователь с таким email уже существует.",
      }),
    });
  });

  it("sends invitation before recording a deterministic lowercase email hash", async () => {
    const { service, events, audit, notifications } = createHarness();

    await expect(service.inviteStudent(actor, "student-a")).resolves.toEqual({
      studentId: "student-a",
      email: "student@example.com",
      status: "queued",
    });

    expect(events).toEqual(["notification", "audit"]);
    expect(notifications.sendEmail).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "user-a",
        template: "student_invite",
        title: "Приглашение в личный кабинет Magic Music",
      }),
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.student_invite_sent",
        metadata: {
          emailHash:
            "616bb35d31d0a6840d2d5adfeacde5979ea99a18ab5fa7bb633460029e20717e",
        },
      }),
    );
  });

  it("keeps invitation failures fail-closed with exact messages", async () => {
    const { service, database, notifications } = createHarness();
    database.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ ...student, email: null }] })
      .mockResolvedValueOnce({ rows: [{ ...student, profile_user_id: null }] });

    await expect(service.inviteStudent(actor, "missing")).rejects.toThrow(
      new NotFoundException("Ученик не найден."),
    );
    await expect(service.inviteStudent(actor, "no-email")).rejects.toThrow(
      new BadRequestException("У ученика нет email для приглашения."),
    );
    await expect(service.inviteStudent(actor, "no-profile")).rejects.toThrow(
      new BadRequestException("У ученика нет профиля для приглашения."),
    );
    expect(notifications.sendEmail).not.toHaveBeenCalled();
  });

  it.each([
    [
      "delete",
      (service: StudentCommandService) =>
        service.deleteStudent(actor, "student-a"),
      "Прямое удаление ученика отключено. Используйте управляемое архивирование с предварительной проверкой связанных занятий, абонементов и финансовых операций.",
    ],
    [
      "return-to-lead",
      (service: StudentCommandService) =>
        service.returnStudentToLead(actor, "student-a"),
      "Возврат ученика в лиды отключён. Сначала нужен управляемый сценарий с предварительной проверкой занятий, абонементов и финансовых операций.",
    ],
  ])("keeps %s fail-closed without persistence", async (_, run, message) => {
    const { service, database, audit, policy } = createHarness();

    await expect(run(service)).rejects.toThrow(new ConflictException(message));

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(database.query).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });
});
