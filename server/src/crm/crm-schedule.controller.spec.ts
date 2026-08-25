import { ServiceUnavailableException } from "@nestjs/common";
import { V4DomainFlagsService } from "../platform/rollout/v4/domain-flags";
import { CrmScheduleController } from "./crm-schedule.controller";

describe("CrmScheduleController rollout boundary", () => {
  const actor = { userId: "user-a", role: "manager" } as const;

  function controller(effectivePath: "legacy" | "v4") {
    const schedule = {
      createLesson: jest.fn().mockResolvedValue({ path: "legacy" }),
      updateLesson: jest.fn().mockResolvedValue({ path: "legacy" }),
      createScheduleSeries: jest.fn().mockResolvedValue({ path: "legacy" }),
    };
    const scheduleRead = {
      listLessons: jest.fn().mockResolvedValue({ items: [] }),
      getScheduleMatrix: jest.fn().mockResolvedValue({ items: [], groups: [] }),
      getScheduleMonthSummary: jest.fn().mockResolvedValue({ items: [] }),
    };
    const scheduleConflicts = {
      getScheduleConflicts: jest.fn().mockResolvedValue({
        teacherBusy: false,
        roomBusy: false,
        conflicts: [],
      }),
    };
    const scheduleSeries = {
      listScheduleSeries: jest.fn().mockResolvedValue([]),
      createScheduleSeries: jest.fn().mockResolvedValue({ path: "legacy" }),
      updateScheduleSeries: jest.fn().mockResolvedValue({ id: "series-a" }),
      deleteScheduleSeries: jest.fn().mockResolvedValue({ success: true }),
    };
    const lessonCommands = {
      create: jest.fn().mockResolvedValue({ path: "v4" }),
      update: jest.fn().mockResolvedValue({ path: "v4" }),
      previewConstraints: jest
        .fn()
        .mockResolvedValue({ valid: true, violations: [] }),
    };
    const lessonSeriesCommands = {
      create: jest.fn().mockResolvedValue({ path: "v4" }),
    };
    const lessonTransitions = {
      previewCancel: jest.fn(),
    };
    const schedulePlans = {
      previewUpdateConstraints: jest.fn().mockResolvedValue({
        valid: true,
        rows: [],
      }),
    };
    const flags = {
      get: jest.fn(() => ({ effectivePath })),
      assertEnabled: jest.fn(() => {
        if (effectivePath !== "v4") throw new ServiceUnavailableException();
      }),
    } as unknown as V4DomainFlagsService;
    return {
      controller: new CrmScheduleController(
        schedule as never,
        scheduleRead as never,
        scheduleConflicts as never,
        scheduleSeries as never,
        lessonCommands as never,
        lessonSeriesCommands as never,
        lessonTransitions as never,
        flags,
        schedulePlans as never,
        {} as never,
      ),
      schedule,
      scheduleRead,
      scheduleConflicts,
      scheduleSeries,
      lessonCommands,
      schedulePlans,
    };
  }

  it("keeps lesson writes on the legacy service in shadow/legacy mode", async () => {
    const {
      controller: subject,
      schedule,
      lessonCommands,
    } = controller("legacy");

    await expect(
      subject.createLesson(actor, "key", "request", {} as never),
    ).resolves.toEqual({ path: "legacy" });
    expect(schedule.createLesson).toHaveBeenCalled();
    expect(lessonCommands.create).not.toHaveBeenCalled();
  });

  it("routes lesson writes to the v4 command only after enable", async () => {
    const { controller: subject, schedule, lessonCommands } = controller("v4");

    await expect(
      subject.createLesson(actor, "key", "request", {} as never),
    ).resolves.toEqual({ path: "v4" });
    expect(lessonCommands.create).toHaveBeenCalledWith(
      actor,
      {},
      {
        idempotencyKey: "key",
        requestId: "request",
      },
    );
    expect(schedule.createLesson).not.toHaveBeenCalled();
  });

  it("blocks v4-only transitions while the legacy path is effective", () => {
    const { controller: subject } = controller("legacy");

    expect(() =>
      subject.previewLessonCancel(actor, "lesson-a", {} as never),
    ).toThrow(ServiceUnavailableException);
  });

  it("routes constraint preview through the authoritative command engine", async () => {
    const { controller: subject, lessonCommands } = controller("v4");
    const dto = { scheduledAt: "2026-08-05T09:00:00.000Z" } as never;

    await expect(subject.previewLessonConstraints(actor, dto)).resolves.toEqual(
      {
        valid: true,
        violations: [],
      },
    );
    expect(lessonCommands.previewConstraints).toHaveBeenCalledWith(actor, dto);
  });

  it("routes Plan update preview through the authoritative Plan service", async () => {
    const { controller: subject, schedulePlans } = controller("v4");
    const dto = { expectedVersion: 2, effectiveFrom: "2026-08-20" } as never;

    await expect(
      subject.previewSchedulePlanUpdateConstraints(actor, "plan-a", dto),
    ).resolves.toEqual({ valid: true, rows: [] });
    expect(schedulePlans.previewUpdateConstraints).toHaveBeenCalledWith(
      actor,
      "plan-a",
      dto,
    );
  });

  it("routes schedule reads through the dedicated read service", async () => {
    const { controller: subject, scheduleRead } = controller("v4");

    await subject.listLessons(actor, { limit: 10 } as never);
    await subject.getScheduleMatrix(actor, { groupBy: "room" } as never);
    await subject.getScheduleMonthSummary(actor, {} as never);

    expect(scheduleRead.listLessons).toHaveBeenCalledWith(actor, { limit: 10 });
    expect(scheduleRead.getScheduleMatrix).toHaveBeenCalledWith(actor, {
      groupBy: "room",
    });
    expect(scheduleRead.getScheduleMonthSummary).toHaveBeenCalledWith(actor, {});
  });

  it("routes recurring-series reads and mutations through their owner", async () => {
    const { controller: subject, scheduleSeries } = controller("legacy");

    await subject.listScheduleSeries(actor, {} as never);
    await subject.createScheduleSeries(actor, "", "", {
      notes: "Проверка маршрутизации",
    } as never);
    await subject.updateScheduleSeries(actor, "series-a", {} as never);
    await subject.deleteScheduleSeries(actor, "series-a", {} as never);

    expect(scheduleSeries.listScheduleSeries).toHaveBeenCalled();
    expect(scheduleSeries.createScheduleSeries).toHaveBeenCalled();
    expect(scheduleSeries.updateScheduleSeries).toHaveBeenCalled();
    expect(scheduleSeries.deleteScheduleSeries).toHaveBeenCalled();
  });

  it("routes conflict preflight through the dedicated conflict service", async () => {
    const { controller: subject, scheduleConflicts } = controller("v4");
    const query = {
      teacherId: "teacher-a",
      startsAt: "2026-08-05T09:00:00.000Z",
      endsAt: "2026-08-05T10:00:00.000Z",
    } as never;

    await subject.getScheduleConflicts(actor, query);

    expect(scheduleConflicts.getScheduleConflicts).toHaveBeenCalledWith(
      actor,
      query,
    );
  });
});
