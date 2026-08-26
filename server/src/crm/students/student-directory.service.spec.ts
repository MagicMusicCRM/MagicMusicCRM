import { ForbiddenException } from "@nestjs/common";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { StudentDirectoryService } from "./student-directory.service";

describe("StudentDirectoryService", () => {
  const manager = { userId: "manager-a", role: "manager" as const };
  const teacher = { userId: "teacher-a", role: "teacher" as const };
  const student = {
    id: "student-a",
    status: "active",
    profile_id: "profile-a",
    profile_user_id: "user-a",
    lead_id: null,
    custom_data: {},
    blacklisted: false,
    blacklist_reason: null,
    first_name: "Алина",
    last_name: "Иванова",
    email: "alina@example.com",
    phone: "+79990000000",
    teacher_user_ids: ["teacher-a"],
    created_at: "2026-08-01T10:00:00.000Z",
  };

  function createDirectory(rows: Record<string, unknown>[] = []) {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = { query } as unknown as DatabaseService;
    const policy = {
      assertCanListStudents: jest.fn(),
      assertCanReadStudent: jest.fn(),
      assertCanReadOperationalData: jest.fn(),
    } as unknown as CrmPolicy;
    return {
      directory: new StudentDirectoryService(database, policy),
      query,
      policy,
    };
  }

  it("does not query when list policy rejects", async () => {
    const { directory, query, policy } = createDirectory();
    jest
      .spyOn(policy, "assertCanListStudents")
      .mockImplementation(() => { throw new ForbiddenException(); });

    await expect(directory.listStudents(teacher, {})).rejects.toThrow(
      ForbiddenException,
    );
    expect(query).not.toHaveBeenCalled();
  });

  it("does not query when search policy rejects", async () => {
    const { directory, query, policy } = createDirectory();
    jest
      .spyOn(policy, "assertCanListStudents")
      .mockImplementation(() => { throw new ForbiddenException(); });

    await expect(directory.searchStudents(teacher, {})).rejects.toThrow(
      ForbiddenException,
    );
    expect(query).not.toHaveBeenCalled();
  });

  it("reads exactly the authorization row before rejecting a student read", async () => {
    const { directory, query, policy } = createDirectory([student]);
    jest
      .spyOn(policy, "assertCanReadStudent")
      .mockImplementation(() => { throw new ForbiddenException(); });

    await expect(directory.getStudent(teacher, student.id)).rejects.toThrow(
      ForbiddenException,
    );
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("reads exactly the authorization row before rejecting student groups", async () => {
    const { directory, query, policy } = createDirectory([student]);
    jest
      .spyOn(policy, "assertCanReadStudent")
      .mockImplementation(() => { throw new ForbiddenException(); });

    await expect(
      directory.listStudentGroups(teacher, student.id, {}),
    ).rejects.toThrow(ForbiddenException);
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("does not query a group roster when operational policy rejects", async () => {
    const { directory, query, policy } = createDirectory();
    jest
      .spyOn(policy, "assertCanReadOperationalData")
      .mockImplementation(() => { throw new ForbiddenException(); });

    await expect(
      directory.listGroupStudents(teacher, "group-a", {}),
    ).rejects.toThrow(ForbiddenException);
    expect(query).not.toHaveBeenCalled();
  });

  it("maps a student from the directory owner", async () => {
    const { directory } = createDirectory([student]);

    await expect(directory.getStudent(manager, student.id)).resolves.toMatchObject({
      id: student.id,
      firstName: "Алина",
    });
  });
});
