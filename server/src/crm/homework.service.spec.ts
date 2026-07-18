import { BadRequestException, ForbiddenException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { HomeworkService } from "./homework.service";

describe("HomeworkService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const makeDeps = () => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = { assertCanReadOperationalData: jest.fn() };
    const realtime = { emitCrmChanged: jest.fn() };
    return { audit, policy, realtime };
  };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const transaction = jest.fn(
      (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    const { audit, policy, realtime } = makeDeps();
    const service = new HomeworkService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, transaction, audit, policy, realtime };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const queuedResults = [...results];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (String(sql).includes("pg_advisory_xact_lock")) {
        return Promise.resolve({ rows: [] });
      }
      return Promise.resolve(queuedResults.shift());
    });
    const transaction = jest.fn(
      (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    const { audit, policy, realtime } = makeDeps();
    const service = new HomeworkService(
      { query, transaction } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, transaction, audit, policy, realtime };
  };

  it("creates a homework through operational-data policy and audit (P5c)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "hw-a",
        lesson_id: "lesson-a",
        student_id: "student-a",
        lead_id: null,
        assigned_by: "manager-a",
        title: "Гаммы",
        description: "До-мажор",
        status: "assigned",
        due_at: "2026-06-30T00:00:00.000Z",
        created_at: "2026-06-22T00:00:00.000Z",
        updated_at: "2026-06-22T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createHomework(actor, {
        studentId: "student-a",
        lessonId: "lesson-a",
        title: " Гаммы ",
        description: " До-мажор ",
        dueAt: "2026-06-30T00:00:00.000Z",
      }),
    ).resolves.toEqual({
      id: "hw-a",
      lessonId: "lesson-a",
      studentId: "student-a",
      leadId: null,
      assignedBy: "manager-a",
      title: "Гаммы",
      description: "До-мажор",
      status: "assigned",
      dueAt: "2026-06-30T00:00:00.000Z",
      createdAt: "2026-06-22T00:00:00.000Z",
      updatedAt: "2026-06-22T00:00:00.000Z",
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("insert into app.lesson_homeworks");
    expect(query.mock.calls[0][1]).toEqual([
      "lesson-a",
      "student-a",
      null,
      "manager-a",
      "Гаммы",
      "До-мажор",
      "2026-06-30T00:00:00.000Z",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_assigned",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("lists homeworks for staff with student/status filters (P5c)", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "hw-a",
            lesson_id: null,
            student_id: "student-a",
            lead_id: null,
            assigned_by: "manager-a",
            title: "Гаммы",
            description: null,
            status: "assigned",
            due_at: null,
            created_at: "2026-06-22T00:00:00.000Z",
            updated_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
    ]);

    const result = await service.listHomeworks(actor, {
      studentId: "student-a",
      status: "assigned",
      limit: 50,
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toEqual(
      expect.objectContaining({ id: "hw-a", studentId: "student-a" }),
    );
    // student filter, status filter, then the limit param last.
    expect(query.mock.calls[0][1]).toEqual(["student-a", "assigned", 50]);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).not.toContain("p.user_id");
  });

  it("submits a homework as the owning client (P5c)", async () => {
    const clientActor = { userId: "client-user", role: "client" as const };
    const { service, query, audit } = createServiceWithQueryResults([
      // owner lookup
      {
        rows: [
          {
            student_id: "student-a",
            lead_id: null,
            teacher_user_id: null,
            client_can_access: true,
          },
        ],
      },
      // status update
      {
        rows: [
          {
            id: "hw-a",
            lesson_id: null,
            student_id: "student-a",
            lead_id: null,
            assigned_by: "manager-a",
            title: "Гаммы",
            description: null,
            status: "submitted",
            due_at: null,
            created_at: "2026-06-22T00:00:00.000Z",
            updated_at: "2026-06-22T00:00:00.000Z",
          },
        ],
      },
    ]);

    const result = await service.submitHomework(clientActor, "hw-a");
    expect(result.status).toBe("submitted");
    const updateSql = String(query.mock.calls[1][0]);
    expect(updateSql).toContain("status = 'submitted'");
    expect(query.mock.calls[1][1]).toEqual(["hw-a"]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_submitted",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("forbids submitting a homework owned by another client (P5c)", async () => {
    const clientActor = { userId: "other-user", role: "client" as const };
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          {
            student_id: "student-a",
            lead_id: null,
            teacher_user_id: null,
            client_can_access: false,
          },
        ],
      },
    ]);

    await expect(
      service.submitHomework(clientActor, "hw-a"),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("adds an assignment attachment through operational-data policy (P5c)", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            student_id: "student-a",
            lead_id: null,
            teacher_user_id: null,
          },
        ],
      },
      { rows: [{ id: "att-a" }] },
    ]);

    const result = await service.addHomeworkAttachment(actor, "hw-a", {
      fileId: "file-a",
      kind: "assignment",
    });

    expect(result).toEqual({
      id: "att-a",
      homeworkId: "hw-a",
      fileId: "file-a",
      kind: "assignment",
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[1][0]);
    expect(sql).toContain("insert into app.homework_attachments");
    expect(query.mock.calls[1][1]).toEqual([
      "hw-a",
      "file-a",
      "manager-a",
      "assignment",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_attachment_added",
        entityType: "student",
        entityId: "student-a",
      }),
    );
  });

  it("lets the assigned teacher create lead homework only for their own trial lesson", async () => {
    const teacher = { userId: "teacher-user", role: "teacher" as const };
    const { service, query, audit } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-trial",
            student_matches: false,
            lead_id: "lead-a",
            is_trial: true,
            teacher_user_id: "teacher-user",
          },
        ],
      },
      {
        rows: [
          {
            id: "hw-lead",
            lesson_id: "lesson-trial",
            student_id: null,
            lead_id: "lead-a",
            assigned_by: "teacher-user",
            title: "Этюд",
            description: null,
            status: "assigned",
            due_at: null,
            created_at: "2026-07-18T12:00:00.000Z",
            updated_at: "2026-07-18T12:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.createHomework(teacher, {
        leadId: "lead-a",
        lessonId: "lesson-trial",
        title: "Этюд",
      }),
    ).resolves.toMatchObject({
      id: "hw-lead",
      leadId: "lead-a",
      studentId: null,
    });

    expect(String(query.mock.calls[0][0])).toContain(
      "pg_advisory_xact_lock",
    );
    expect(String(query.mock.calls[1][0])).toContain(
      "teacher_profile.user_id as teacher_user_id",
    );
    expect(query.mock.calls[2][1]).toEqual([
      "lesson-trial",
      null,
      "lead-a",
      "teacher-user",
      "Этюд",
      null,
      null,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_assigned",
        entityType: "lead",
        entityId: "lead-a",
      }),
    );
  });

  it("rejects a teacher assigning homework to another teacher's trial", async () => {
    const teacher = { userId: "teacher-user", role: "teacher" as const };
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-trial",
            student_matches: false,
            lead_id: "lead-a",
            is_trial: true,
            teacher_user_id: "other-teacher",
          },
        ],
      },
    ]);

    await expect(
      service.createHomework(teacher, {
        leadId: "lead-a",
        lessonId: "lesson-trial",
        title: "Этюд",
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.lesson_homeworks"),
      ),
    ).toBe(false);
  });

  it("rejects late lead homework after conversion wins the shared lead lock", async () => {
    const teacher = { userId: "teacher-user", role: "teacher" as const };
    const { service, query, transaction } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-trial",
            student_matches: true,
            lead_id: null,
            is_trial: true,
            teacher_user_id: "teacher-user",
          },
        ],
      },
    ]);

    await expect(
      service.createHomework(teacher, {
        leadId: "lead-a",
        lessonId: "lesson-trial",
        title: "Этюд",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);

    expect(transaction).toHaveBeenCalledTimes(1);
    expect(String(query.mock.calls[0][0])).toContain(
      "pg_advisory_xact_lock",
    );
    expect(String(query.mock.calls[1][0])).toContain("l.lead_id");
    expect(
      query.mock.calls.some((call) =>
        String(call[0]).includes("insert into app.lesson_homeworks"),
      ),
    ).toBe(false);
  });

  it("scopes lead homework reads to linked/family clients and own-lesson teachers", async () => {
    const clientService = createServiceWithQueryResults([{ rows: [] }]);
    await clientService.service.listHomeworks(
      { userId: "client-user", role: "client" },
      { leadId: "lead-a" },
    );
    const clientSql = String(clientService.query.mock.calls[0][0]);
    expect(clientSql).toContain("app.user_crm_links lead_link");
    expect(clientSql).toContain("app.family_members lead_member");
    expect(clientService.query.mock.calls[0][1]).toEqual([
      "client-user",
      "lead-a",
      100,
    ]);

    const teacherService = createServiceWithQueryResults([{ rows: [] }]);
    await teacherService.service.listHomeworks(
      { userId: "teacher-user", role: "teacher" },
      { lessonId: "lesson-trial" },
    );
    const teacherSql = String(teacherService.query.mock.calls[0][0]);
    expect(teacherSql).toContain("own_teacher_profile.user_id");
    expect(teacherService.query.mock.calls[0][1]).toEqual([
      "teacher-user",
      "lesson-trial",
      100,
    ]);
  });

  it("publishes a created homework to its linked client and assigned teacher", async () => {
    const { service, query, realtime } = createServiceWithQueryResults([
      {
        rows: [
          {
            id: "lesson-trial",
            student_matches: false,
            lead_id: "lead-a",
            is_trial: true,
            teacher_user_id: "teacher-user",
          },
        ],
      },
      {
        rows: [
          {
            id: "hw-lead",
            lesson_id: "lesson-trial",
            student_id: null,
            lead_id: "lead-a",
            assigned_by: "teacher-user",
            title: "Этюд",
            description: null,
            status: "assigned",
            due_at: null,
            created_at: "2026-07-18T12:00:00.000Z",
            updated_at: "2026-07-18T12:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          { user_id: "client-user" },
          { user_id: "teacher-user" },
        ],
      },
    ]);

    await service.createHomework(
      { userId: "teacher-user", role: "teacher" },
      {
        leadId: "lead-a",
        lessonId: "lesson-trial",
        title: "Этюд",
      },
    );

    const audienceSql = String(query.mock.calls[3][0]);
    expect(audienceSql).toContain("app.user_crm_links lead_link");
    expect(audienceSql).toContain("app.family_members student_member");
    expect(audienceSql).toContain("teacher_profile.user_id");
    expect(query.mock.calls[3][1]).toEqual(["hw-lead"]);
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "homework",
      action: "created",
      id: "hw-lead",
      affectedUserIds: ["client-user", "teacher-user"],
    });
  });

  it("publishes a submitted homework to staff and the assigned teacher audience", async () => {
    const { service, query, realtime } = createServiceWithQueryResults([
      {
        rows: [
          {
            student_id: "student-a",
            lead_id: null,
            teacher_user_id: "teacher-user",
            client_can_access: true,
          },
        ],
      },
      {
        rows: [
          {
            id: "hw-a",
            lesson_id: "lesson-a",
            student_id: "student-a",
            lead_id: null,
            assigned_by: "manager-a",
            title: "Гаммы",
            description: null,
            status: "submitted",
            due_at: null,
            created_at: "2026-07-18T12:00:00.000Z",
            updated_at: "2026-07-18T13:00:00.000Z",
          },
        ],
      },
      {
        rows: [
          { user_id: "client-user" },
          { user_id: "teacher-user" },
        ],
      },
    ]);

    await service.submitHomework(
      { userId: "client-user", role: "client" },
      "hw-a",
    );

    expect(query.mock.calls[2][1]).toEqual(["hw-a"]);
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "homework",
      action: "updated",
      id: "hw-a",
      affectedUserIds: ["client-user", "teacher-user"],
    });
  });

  it("publishes an updated homework to its address-scoped audience", async () => {
    const { service, realtime } = createServiceWithQueryResults([
      {
        rows: [
          {
            student_id: "student-a",
            lead_id: null,
            teacher_user_id: "teacher-user",
          },
        ],
      },
      {
        rows: [
          {
            id: "hw-a",
            lesson_id: "lesson-a",
            student_id: "student-a",
            lead_id: null,
            assigned_by: "manager-a",
            title: "Новые гаммы",
            description: null,
            status: "assigned",
            due_at: null,
            created_at: "2026-07-18T12:00:00.000Z",
            updated_at: "2026-07-18T13:00:00.000Z",
          },
        ],
      },
      { rows: [{ user_id: "client-user" }] },
    ]);

    await service.updateHomework(actor, "hw-a", { title: "Новые гаммы" });

    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "homework",
      action: "updated",
      id: "hw-a",
      affectedUserIds: ["client-user"],
    });
  });
});
