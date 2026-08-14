import {
  groupScheduleConflicts,
  rankScheduleSuggestions,
  scheduleConflictFingerprint,
} from "./schedule-analyzer";

describe("Schedule Analyzer", () => {
  it("groups identical conflicts across rows, dates and students", () => {
    const violation = {
      code: "ROOM_OVERLAP" as const,
      resource: { type: "room" as const, id: "room-a" },
      conflictingLessonIds: ["lesson-b", "lesson-a"],
      ruleIds: [],
    };

    const conflicts = groupScheduleConflicts([
      {
        violation,
        scope: { rowIndex: 1, studentId: "student-b", localDate: "2026-08-21" },
      },
      {
        violation: {
          ...violation,
          conflictingLessonIds: ["lesson-a", "lesson-c"],
        },
        scope: { rowIndex: 0, studentId: "student-a", localDate: "2026-08-14" },
      },
    ]);

    expect(conflicts).toEqual([
      {
        fingerprint: "ROOM_OVERLAP:room:room-a",
        code: "ROOM_OVERLAP",
        resource: { type: "room", id: "room-a" },
        occurrences: 2,
        conflictingLessonIds: ["lesson-a", "lesson-b", "lesson-c"],
        ruleIds: [],
        scopes: [
          { rowIndex: 0, studentId: "student-a", localDate: "2026-08-14" },
          { rowIndex: 1, studentId: "student-b", localDate: "2026-08-21" },
        ],
      },
    ]);
  });

  it("keeps different resources in separate groups", () => {
    const conflicts = groupScheduleConflicts([
      {
        violation: {
          code: "ROOM_OVERLAP",
          resource: { type: "room", id: "room-a" },
          conflictingLessonIds: [],
          ruleIds: [],
        },
      },
      {
        violation: {
          code: "ROOM_OVERLAP",
          resource: { type: "room", id: "room-b" },
          conflictingLessonIds: [],
          ruleIds: [],
        },
      },
    ]);

    expect(conflicts.map((conflict) => conflict.fingerprint)).toEqual([
      "ROOM_OVERLAP:room:room-a",
      "ROOM_OVERLAP:room:room-b",
    ]);
    expect(scheduleConflictFingerprint(conflicts[0]!)).toBe(
      "ROOM_OVERLAP:room:room-a",
    );
  });

  it("deduplicates and deterministically ranks alternatives", () => {
    const ranked = rankScheduleSuggestions([
      {
        kind: "NEAREST_TIME",
        score: 920,
        changes: { startOffsetMinutes: 30 },
        resolves: ["ROOM_OVERLAP:room:room-a"],
      },
      {
        kind: "SAME_TIME_ROOM",
        score: 1_000,
        changes: { roomId: "room-b", roomName: "Класс 2" },
        resolves: ["ROOM_OVERLAP:room:room-a"],
      },
      {
        kind: "NEAREST_TIME",
        score: 900,
        changes: { startOffsetMinutes: 30 },
        resolves: ["ROOM_OVERLAP:room:room-a"],
      },
    ]);

    expect(ranked).toEqual([
      expect.objectContaining({
        rank: 1,
        kind: "SAME_TIME_ROOM",
        score: 1_000,
      }),
      expect.objectContaining({ rank: 2, kind: "NEAREST_TIME", score: 920 }),
    ]);
  });
});
