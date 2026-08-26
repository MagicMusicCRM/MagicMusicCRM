import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { ScheduleReadService } from "../schedule/schedule-read.service";
import { SharedTaskService } from "../tasks/shared-task.service";
import { StudentSelfSummaryService } from "./student-self-summary.service";

describe("StudentSelfSummaryService", () => {
  const actor: ActorContext = { userId: "parent-a", role: "client" };
  const row = (id: string, firstName: string) => ({
    id,
    lead_id: null,
    source_id: null,
    source_name: null,
    status: "active",
    custom_data: {},
    profile_id: `profile-${id}`,
    profile_user_id: null,
    first_name: firstName,
    last_name: "Иванов",
    email: null,
    phone: null,
    teacher_user_ids: [],
    blacklisted: false,
    blacklist_reason: null,
    created_at: "2026-08-01T10:00:00.000Z",
  });

  const createService = (
    queryRows: Record<string, unknown>[][],
    options: { lessonsError?: Error; tasksError?: Error } = {},
  ) => {
    const query = jest.fn();
    for (const rows of queryRows) query.mockResolvedValueOnce({ rows });
    const scheduleRead = {
      listUpcomingLessonsForStudents: options.lessonsError
        ? jest.fn().mockRejectedValue(options.lessonsError)
        : jest.fn().mockResolvedValue([{ id: "lesson-a" }]),
    };
    const tasks = {
      list: options.tasksError
        ? jest.fn().mockRejectedValue(options.tasksError)
        : jest.fn().mockResolvedValue({ items: [{ id: "task-a" }] }),
    };
    return {
      service: new StudentSelfSummaryService(
        { query } as unknown as DatabaseService,
        tasks as unknown as SharedTaskService,
        scheduleRead as unknown as ScheduleReadService,
      ),
      query,
      scheduleRead,
      tasks,
    };
  };

  it("keeps own, then family, then manual rows when duplicate student ids differ", async () => {
    const { service } = createService([
      [row("student-own", "Свой")],
      [row("student-family", "Семья"), row("student-own", "Не свой")],
      [
        row("student-manual", "Ручной"),
        row("student-family", "Не семья"),
      ],
    ]);

    const result = await service.getMySummary(actor);

    expect(result.students.map(({ id, firstName }) => ({ id, firstName }))).toEqual([
      { id: "student-own", firstName: "Свой" },
      { id: "student-family", firstName: "Семья" },
      { id: "student-manual", firstName: "Ручной" },
    ]);
  });

  it("does not read lessons or tasks when no students are linked", async () => {
    const { service, scheduleRead, tasks } = createService([[], [], []]);

    await expect(service.getMySummary(actor)).resolves.toEqual({
      students: [],
      upcomingLessons: [],
      tasks: [],
    });
    expect(scheduleRead.listUpcomingLessonsForStudents).not.toHaveBeenCalled();
    expect(tasks.list).not.toHaveBeenCalled();
  });

  it("keeps tasks when the independent lesson section fails", async () => {
    const { service } = createService(
      [[row("student-a", "Анна")], [], []],
      { lessonsError: new Error("schedule unavailable") },
    );

    await expect(service.getMySummary(actor)).resolves.toMatchObject({
      upcomingLessons: [],
      tasks: [{ id: "task-a" }],
    });
  });

  it("keeps lessons when the independent task section fails", async () => {
    const { service } = createService(
      [[row("student-a", "Анна")], [], []],
      { tasksError: new Error("tasks unavailable") },
    );

    await expect(service.getMySummary(actor)).resolves.toMatchObject({
      upcomingLessons: [{ id: "lesson-a" }],
      tasks: [],
    });
  });
});
