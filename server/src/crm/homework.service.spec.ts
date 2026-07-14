import { ForbiddenException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { HomeworkService } from "./homework.service";

describe("HomeworkService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const makeDeps = () => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = { assertCanReadOperationalData: jest.fn() };
    return { audit, policy };
  };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const { audit, policy } = makeDeps();
    const service = new HomeworkService(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, audit, policy };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const { audit, policy } = makeDeps();
    const service = new HomeworkService(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, audit, policy };
  };

  it("creates a homework through operational-data policy and audit (P5c)", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "hw-a",
        lesson_id: "lesson-a",
        student_id: "student-a",
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
      { rows: [{ assigned_by: "manager-a", student_user_id: "client-user" }] },
      // status update
      {
        rows: [
          {
            id: "hw-a",
            lesson_id: null,
            student_id: "student-a",
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
      { rows: [{ assigned_by: "manager-a", student_user_id: "client-user" }] },
    ]);

    await expect(
      service.submitHomework(clientActor, "hw-a"),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("adds an assignment attachment through operational-data policy (P5c)", async () => {
    const { service, query, audit, policy } = createService([{ id: "att-a" }]);

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
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("insert into app.homework_attachments");
    expect(query.mock.calls[0][1]).toEqual([
      "hw-a",
      "file-a",
      "manager-a",
      "assignment",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.homework_attachment_added",
        entityType: "student",
        entityId: "hw-a",
      }),
    );
  });
});
