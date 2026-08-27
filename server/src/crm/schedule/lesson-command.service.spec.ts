import { ActorContext } from "../../common/security/actor-context";
import { LessonConstraintPreviewService } from "./lesson-constraint-preview.service";

describe("LessonConstraintPreviewService", () => {
  it("uses the unified analyzer and preserves the requested lesson interval", async () => {
    const policy = { assertCanWriteCrm: jest.fn() };
    const analysis = {
      valid: false,
      violations: [],
      conflicts: [],
      suggestions: [],
    };
    const constraints = {
      analyze: jest.fn().mockResolvedValue(analysis),
    };
    const service = new LessonConstraintPreviewService(
      policy as never,
      constraints as never,
    );
    const actor = {
      userId: "00000000-0000-4000-8000-000000000001",
      role: "manager",
    } as ActorContext;

    await expect(
      service.previewConstraints(actor, {
        clientRef: {
          type: "student",
          id: "00000000-0000-4000-8000-000000000002",
        },
        teacherId: "00000000-0000-4000-8000-000000000003",
        branchId: "00000000-0000-4000-8000-000000000004",
        roomId: "00000000-0000-4000-8000-000000000005",
        scheduledAt: "2026-08-14T09:00:00.000Z",
        durationMinutes: 45,
        excludeLessonId: "00000000-0000-4000-8000-000000000006",
      }),
    ).resolves.toBe(analysis);

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(constraints.analyze).toHaveBeenCalledWith({
      clientRef: {
        type: "student",
        id: "00000000-0000-4000-8000-000000000002",
      },
      teacherId: "00000000-0000-4000-8000-000000000003",
      branchId: "00000000-0000-4000-8000-000000000004",
      roomId: "00000000-0000-4000-8000-000000000005",
      startAt: new Date("2026-08-14T09:00:00.000Z"),
      endAt: new Date("2026-08-14T09:45:00.000Z"),
      excludeLessonId: "00000000-0000-4000-8000-000000000006",
    });
  });
});
