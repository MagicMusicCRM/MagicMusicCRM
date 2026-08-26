import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { ChatWorkTimelineService } from "../../messenger/chat-work-timeline.service";
import { ScheduleReadService } from "../schedule/schedule-read.service";
import { SharedTaskService } from "../tasks/shared-task.service";
import { TimelineService } from "../timeline.service";
import { StudentCardTimelineService } from "./student-card-timeline.service";
import { StudentDirectoryService } from "./student-directory.service";

describe("StudentCardTimelineService", () => {
  const student = {
    id: "student-a",
    leadId: null,
    sourceId: null,
    sourceName: null,
    status: "active",
    customData: {},
    profileId: "profile-a",
    profileUserId: "client-a",
    firstName: "Анна",
    lastName: "Иванова",
    email: "anna@example.com",
    phone: null,
    teacherUserIds: ["teacher-a"],
    createdAt: "2026-08-01T10:00:00.000Z",
    appealAt: "2026-08-01T10:00:00.000Z",
    appealAtSource: "record_created_at",
    age: null,
    ageMonths: null,
    ageSource: null,
    blacklisted: false,
    blacklistReason: null,
  };

  const createService = () => {
    const database = {
      query: jest.fn().mockResolvedValue({
        rows: [
          {
            id: "link-a",
            user_id: "client-a",
            email: "client@example.com",
            phone: "+79990000000",
            link_source: "manual_phone",
            confirmed_at: "2026-08-01T09:00:00.000Z",
            created_at: "2026-08-01T08:00:00.000Z",
          },
        ],
      }),
    };
    const directory = {
      getStudent: jest.fn().mockResolvedValue(student),
      listStudentGroups: jest.fn().mockResolvedValue({
        items: [{ id: "group-a" }],
      }),
    };
    const scheduleRead = {
      listLessons: jest.fn().mockResolvedValue({
        items: [
          {
            id: "lesson-a",
            isTrial: true,
            teacherName: "Преподаватель",
            roomName: "Класс 1",
            status: "scheduled",
            scheduledAt: "2026-08-01T12:00:00.000Z",
          },
        ],
      }),
    };
    const tasks = {
      list: jest.fn().mockResolvedValue({
        items: [
          {
            id: "task-a",
            title: "Позвонить",
            body: "Уточнить время",
            state: "open",
            createdAt: "2026-08-01T11:00:00.000Z",
          },
        ],
      }),
    };
    const timeline = {
      listComments: jest.fn().mockResolvedValue({
        items: [
          {
            id: "comment-a",
            body: "Комментарий",
            createdAt: "2026-08-01T10:00:00.000Z",
          },
        ],
      }),
      listFieldAudit: jest.fn().mockResolvedValue({
        items: [
          {
            id: "audit-a",
            title: "Правка полей",
            body: "Телефон: — → +79990000000",
            occurredAt: "2026-08-01T14:00:00.000Z",
          },
        ],
      }),
    };
    const chatWork = {
      listForEntity: jest.fn().mockResolvedValue([
        {
          id: "chat-a",
          type: "chat_work",
          title: "Взято в работу",
          body: "Менеджер",
          status: "assigned",
          amount: null,
          actor_user_id: "manager-a",
          actor_first_name: "Мария",
          actor_last_name: "Иванова",
          occurred_at: "2026-08-01T13:00:00.000Z",
        },
      ]),
    };
    return {
      service: new StudentCardTimelineService(
        database as unknown as DatabaseService,
        directory as unknown as StudentDirectoryService,
        scheduleRead as unknown as ScheduleReadService,
        tasks as unknown as SharedTaskService,
        timeline as unknown as TimelineService,
        chatWork as unknown as ChatWorkTimelineService,
      ),
      database,
      directory,
      scheduleRead,
      tasks,
      timeline,
      chatWork,
    };
  };

  it.each([
    { userId: "teacher-a", role: "teacher" as const },
    { userId: "admin-a", role: "admin" as const },
  ])("keeps the $role card authorized and finance-free", async (actor) => {
    const { service, directory } = createService();

    const card = await service.getStudentCard(actor, "student-a");

    expect(directory.getStudent).toHaveBeenCalledWith(actor, "student-a");
    expect(card.student).toEqual(student);
    expect(card).not.toHaveProperty("balance");
    expect(card).not.toHaveProperty("payments");
    expect(card).not.toHaveProperty("expectedPayments");
    expect(card).not.toHaveProperty("subscriptions");
  });

  it("maps every legacy activity type and sorts the combined timeline descending", async () => {
    const actor: ActorContext = { userId: "admin-a", role: "admin" };
    const { service } = createService();

    const card = await service.getStudentCard(actor, "student-a");

    expect(card.groups).toEqual([{ id: "group-a" }]);
    expect(card.lessons).toHaveLength(1);
    expect(card.tasks).toHaveLength(1);
    expect(card.comments).toHaveLength(1);
    expect(card.links).toEqual([
      {
        id: "link-a",
        userId: "client-a",
        email: "client@example.com",
        phone: "+79990000000",
        linkSource: "manual_phone",
        confirmedAt: "2026-08-01T09:00:00.000Z",
        createdAt: "2026-08-01T08:00:00.000Z",
      },
    ]);
    expect(card.timeline).toEqual([
      {
        id: "audit-a",
        type: "audit",
        title: "Правка полей",
        body: "Телефон: — → +79990000000",
        status: null,
        occurredAt: "2026-08-01T14:00:00.000Z",
      },
      {
        id: "chat-a",
        type: "chat_work",
        title: "Взято в работу",
        body: "Менеджер",
        status: "assigned",
        amount: null,
        actorUserId: "manager-a",
        actorName: "Мария Иванова",
        occurredAt: "2026-08-01T13:00:00.000Z",
      },
      {
        id: "lesson-a",
        type: "trial",
        title: "Пробное занятие",
        body: "Преподаватель",
        status: "scheduled",
        occurredAt: "2026-08-01T12:00:00.000Z",
      },
      {
        id: "task-a",
        type: "task",
        title: "Позвонить",
        body: "Уточнить время",
        status: "open",
        occurredAt: "2026-08-01T11:00:00.000Z",
      },
      {
        id: "comment-a",
        type: "comment",
        title: "Комментарий",
        body: "Комментарий",
        status: null,
        occurredAt: "2026-08-01T10:00:00.000Z",
      },
    ]);
  });

  it("stops before every downstream card read when student authorization rejects", async () => {
    const actor: ActorContext = { userId: "teacher-a", role: "teacher" };
    const authorizationError = new Error("student access denied");
    const {
      service,
      database,
      directory,
      scheduleRead,
      tasks,
      timeline,
      chatWork,
    } = createService();
    directory.getStudent.mockRejectedValueOnce(authorizationError);

    await expect(service.getStudentCard(actor, "student-a")).rejects.toBe(
      authorizationError,
    );

    expect(directory.listStudentGroups).not.toHaveBeenCalled();
    expect(scheduleRead.listLessons).not.toHaveBeenCalled();
    expect(tasks.list).not.toHaveBeenCalled();
    expect(timeline.listComments).not.toHaveBeenCalled();
    expect(timeline.listFieldAudit).not.toHaveBeenCalled();
    expect(database.query).not.toHaveBeenCalled();
    expect(chatWork.listForEntity).not.toHaveBeenCalled();
  });
});
