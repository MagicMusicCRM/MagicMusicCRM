import { ServiceUnavailableException } from "@nestjs/common";
import { V4DomainFlagsService } from "../platform/v4-domain-flags";
import { CrmScheduleController } from "./crm-schedule.controller";

describe("CrmScheduleController rollout boundary", () => {
  const actor = { userId: "user-a", role: "manager" } as const;

  function controller(effectivePath: "legacy" | "v4") {
    const schedule = {
      createLesson: jest.fn().mockResolvedValue({ path: "legacy" }),
      updateLesson: jest.fn().mockResolvedValue({ path: "legacy" }),
      createScheduleSeries: jest.fn().mockResolvedValue({ path: "legacy" }),
    };
    const lessonCommands = {
      create: jest.fn().mockResolvedValue({ path: "v4" }),
      update: jest.fn().mockResolvedValue({ path: "v4" }),
    };
    const lessonSeriesCommands = {
      create: jest.fn().mockResolvedValue({ path: "v4" }),
    };
    const lessonTransitions = {
      previewCancel: jest.fn(),
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
        lessonCommands as never,
        lessonSeriesCommands as never,
        lessonTransitions as never,
        flags,
      ),
      schedule,
      lessonCommands,
    };
  }

  it("keeps lesson writes on the legacy service in shadow/legacy mode", async () => {
    const { controller: subject, schedule, lessonCommands } = controller("legacy");

    await expect(subject.createLesson(actor, "key", "request", {} as never))
      .resolves.toEqual({ path: "legacy" });
    expect(schedule.createLesson).toHaveBeenCalled();
    expect(lessonCommands.create).not.toHaveBeenCalled();
  });

  it("routes lesson writes to the v4 command only after enable", async () => {
    const { controller: subject, schedule, lessonCommands } = controller("v4");

    await expect(subject.createLesson(actor, "key", "request", {} as never))
      .resolves.toEqual({ path: "v4" });
    expect(lessonCommands.create).toHaveBeenCalledWith(actor, {}, {
      idempotencyKey: "key",
      requestId: "request",
    });
    expect(schedule.createLesson).not.toHaveBeenCalled();
  });

  it("blocks v4-only transitions while the legacy path is effective", () => {
    const { controller: subject } = controller("legacy");

    expect(() => subject.previewLessonCancel(actor, "lesson-a", {} as never))
      .toThrow(ServiceUnavailableException);
  });
});
