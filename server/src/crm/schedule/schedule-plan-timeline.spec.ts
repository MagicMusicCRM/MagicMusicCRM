import {
  buildSchedulePlanTimeline,
  type SchedulePlanTimelineInput,
  type SchedulePlanTimelineLessonInput,
  type SchedulePlanTimelineRuleInput,
} from "./schedule-plan-timeline";

const NOW = new Date("2026-09-03T12:00:00.000Z");

const rule = (
  id: string,
  activeFrom: string,
  activeUntil: string | null,
  overrides: Partial<SchedulePlanTimelineRuleInput> = {},
): SchedulePlanTimelineRuleInput => ({
  id,
  activeFrom,
  activeUntil,
  teacherId: "teacher-a",
  teacherName: "Teacher A",
  roomId: "room-a",
  roomName: "Room A",
  branchId: "branch-a",
  branchName: "Branch A",
  weekday: 4,
  beginTime: "10:00",
  durationMinutes: 60,
  ...overrides,
});

const lesson = (
  id: string,
  overrides: Partial<SchedulePlanTimelineLessonInput> = {},
): SchedulePlanTimelineLessonInput => ({
  id,
  sourceSeriesId: "source-series",
  seriesId: "source-series",
  scheduledAt: "2026-09-04T10:00:00.000Z",
  expectedScheduledAt: "2026-09-04T10:00:00.000Z",
  scheduledDate: "2026-09-04",
  teacherId: "teacher-a",
  teacherName: "Teacher A",
  roomId: "room-a",
  roomName: "Room A",
  branchId: "branch-a",
  branchName: "Branch A",
  weekday: 4,
  beginTime: "10:00",
  durationMinutes: 60,
  predecessorId: null,
  ...overrides,
});

describe("buildSchedulePlanTimeline", () => {
  it("orders open, finite, one-off, and expired entries by the documented buckets", () => {
    const fixture: SchedulePlanTimelineInput = {
      rules: [
        rule("expired-2026-08-01", "2026-07-01", "2026-08-01"),
        rule("finite-ending-2026-10-20", "2026-10-01", "2026-10-20"),
        rule("open-ended", "2026-08-01", null),
        rule("expired-2026-09-01", "2026-08-01", "2026-09-01"),
        rule("finite-ending-2026-09-20", "2026-08-20", "2026-09-20"),
      ],
      lessons: [
        lesson("exception-2026-09-04", {
          sourceSeriesId: "open-ended",
          seriesId: "open-ended",
          teacherId: "teacher-b",
        }),
      ],
    };

    const result = buildSchedulePlanTimeline(fixture, NOW);

    expect(result.entries.map((entry) => entry.id)).toEqual([
      "open-ended",
      "finite-ending-2026-09-20",
      "finite-ending-2026-10-20",
      "exception-2026-09-04",
      "expired-2026-09-01",
      "expired-2026-08-01",
    ]);
    expect(
      result.entries.map(({ id, sortBucket, sortAt, status }) => ({
        id,
        sortBucket,
        sortAt,
        status,
      })),
    ).toEqual([
      { id: "open-ended", sortBucket: 0, sortAt: "2026-08-01", status: "active" },
      { id: "finite-ending-2026-09-20", sortBucket: 1, sortAt: "2026-09-20", status: "active" },
      { id: "finite-ending-2026-10-20", sortBucket: 1, sortAt: "2026-10-01", status: "active" },
      { id: "exception-2026-09-04", sortBucket: 2, sortAt: "2026-09-04", status: "active" },
      { id: "expired-2026-09-01", sortBucket: 3, sortAt: "2026-09-01", status: "expired" },
      { id: "expired-2026-08-01", sortBucket: 3, sortAt: "2026-08-01", status: "expired" },
    ]);
  });

  it("uses the stable entry id when two sort keys are equal", () => {
    const result = buildSchedulePlanTimeline(
      {
        rules: [
          rule("rule-z", "2026-09-01", "2026-09-20"),
          rule("rule-a", "2026-09-01", "2026-09-20"),
        ],
        lessons: [],
      },
      NOW,
    );

    expect(result.entries.map((entry) => entry.id)).toEqual(["rule-a", "rule-z"]);
  });

  it("marks every supported one-day lesson change in a deterministic field order", () => {
    const changed = lesson("changed-lesson", {
      scheduledAt: "2026-09-04T11:00:00.000Z",
      teacherId: "teacher-b",
      roomId: "room-b",
      branchId: "branch-b",
      durationMinutes: 90,
    });

    expect(
      buildSchedulePlanTimeline(
        { rules: [rule("source-series", "2026-08-01", null)], lessons: [changed] },
        NOW,
      ).exceptions[0],
    ).toMatchObject({
      lessonId: "changed-lesson",
      scheduledDate: "2026-09-04",
      changedFields: [
        "scheduledAt",
        "teacherId",
        "roomId",
        "branchId",
        "durationMinutes",
      ],
    });
  });

  it("marks a single changed teacher or room as a dated exception", () => {
    const exceptionFixture: SchedulePlanTimelineInput = {
      rules: [rule("source-series", "2026-08-01", null)],
      lessons: [
        lesson("teacher-room-exception", {
          teacherId: "teacher-b",
          roomId: "room-b",
        }),
      ],
    };

    expect(buildSchedulePlanTimeline(exceptionFixture, NOW).exceptions[0]).toMatchObject({
      lessonId: "teacher-room-exception",
      scheduledDate: "2026-09-04",
      changedFields: ["teacherId", "roomId"],
    });
  });

  it("keeps a rescheduled successor as an exception when it has no series id", () => {
    const successor = lesson("successor", {
      seriesId: null,
      predecessorId: "source-lesson",
    });

    const result = buildSchedulePlanTimeline(
      { rules: [rule("source-series", "2026-08-01", null)], lessons: [successor] },
      NOW,
    );

    expect(result.exceptions).toEqual([
      expect.objectContaining({
        id: "successor",
        lessonId: "successor",
        sourceSeriesId: "source-series",
        kind: "dated_exception",
        changedFields: [],
      }),
    ]);
  });
});
