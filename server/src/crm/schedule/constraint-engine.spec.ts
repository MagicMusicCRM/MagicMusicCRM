import {
  evaluateReferenceConstraints,
  halfOpenIntervalsOverlap,
  intervalCovers,
  parseConstraintInterval,
  sortConstraintViolations,
  violation,
} from "./constraint-engine.rules";

describe("schedule constraint engine rules", () => {
  const at = (minute: number) =>
    new Date(Date.UTC(2026, 6, 27, 9, minute));

  it("treats intervals as half-open for generated adjacent/overlap cases", () => {
    for (let minute = 0; minute < 120; minute += 3) {
      const left = {
        startAt: at(minute),
        endAt: at(minute + 30),
      };
      const adjacent = {
        startAt: at(minute + 30),
        endAt: at(minute + 60),
      };
      const overlap = {
        startAt: at(minute + 29),
        endAt: at(minute + 60),
      };
      expect(halfOpenIntervalsOverlap(left, adjacent)).toBe(false);
      expect(halfOpenIntervalsOverlap(left, overlap)).toBe(true);
      expect(intervalCovers(left, left)).toBe(true);
    }
  });

  it("preserves half-open overlap invariants for deterministic randomized intervals", () => {
    const random = seededRandom(0x44_04_01);
    const epoch = Date.UTC(2026, 0, 1);
    for (let sample = 0; sample < 2_000; sample += 1) {
      const leftStart = Math.floor(random() * 365 * 24 * 60);
      const rightStart = Math.floor(random() * 365 * 24 * 60);
      const leftDuration = 1 + Math.floor(random() * 12 * 60);
      const rightDuration = 1 + Math.floor(random() * 12 * 60);
      const shift = Math.floor(random() * 10_000) - 5_000;
      const interval = (start: number, duration: number) => ({
        startAt: new Date(epoch + start * 60_000),
        endAt: new Date(epoch + (start + duration) * 60_000),
      });
      const left = interval(leftStart, leftDuration);
      const right = interval(rightStart, rightDuration);
      const expected =
        leftStart < rightStart + rightDuration &&
        rightStart < leftStart + leftDuration;

      expect(halfOpenIntervalsOverlap(left, right)).toBe(expected);
      expect(halfOpenIntervalsOverlap(right, left)).toBe(expected);
      expect(
        halfOpenIntervalsOverlap(
          interval(leftStart + shift, leftDuration),
          interval(rightStart + shift, rightDuration),
        ),
      ).toBe(expected);
      expect(
        halfOpenIntervalsOverlap(
          left,
          interval(leftStart + leftDuration, rightDuration),
        ),
      ).toBe(false);
    }
  });

  it("rejects invalid instants and non-positive intervals", () => {
    expect(parseConstraintInterval("invalid", at(30))).toBeNull();
    expect(parseConstraintInterval(at(30), at(30))).toBeNull();
    expect(parseConstraintInterval(at(31), at(30))).toBeNull();
  });

  it("rejects scheduling until branch working hours are configured", () => {
    const interval = parseConstraintInterval(at(30), at(60))!;
    expect(
      evaluateReferenceConstraints(
        interval,
        {
          teacherBranchAssigned: true,
          branchHoursConfigured: false,
          branchWindows: [],
          teacherRules: [],
        },
        { branchId: "branch-1", teacherId: "teacher-1" },
      ),
    ).toEqual([
      violation("OUTSIDE_BRANCH_HOURS", {
        type: "branch",
        id: "branch-1",
      }),
    ]);
  });

  it("evaluates hours, positive availability, explicit unavailability and branch assignment", () => {
    const interval = parseConstraintInterval(at(30), at(60))!;
    const violations = evaluateReferenceConstraints(
      interval,
      {
        teacherBranchAssigned: false,
        branchWindows: [{ opensAt: at(0), closesAt: at(45) }],
        teacherRules: [
          {
            id: "positive-window",
            available: true,
            startsAt: at(0),
            endsAt: at(120),
          },
          {
            id: "break",
            available: false,
            startsAt: at(45),
            endsAt: at(50),
          },
        ],
      },
      { branchId: "branch-1", teacherId: "teacher-1" },
    );
    expect(violations).toEqual([
      violation("OUTSIDE_BRANCH_HOURS", {
        type: "branch",
        id: "branch-1",
      }),
      violation(
        "TEACHER_BRANCH_MISMATCH",
        { type: "teacher", id: "teacher-1" },
      ),
      violation(
        "TEACHER_UNAVAILABLE",
        { type: "teacher", id: "teacher-1" },
        ["break"],
      ),
    ]);
  });

  it("allows an adjacent unavailability boundary and open default without positive rules", () => {
    const interval = parseConstraintInterval(at(30), at(60))!;
    expect(
      evaluateReferenceConstraints(
        interval,
        {
          teacherBranchAssigned: true,
          branchWindows: [{ opensAt: at(0), closesAt: at(120) }],
          teacherRules: [
            {
              id: "earlier-break",
              available: false,
              startsAt: at(0),
              endsAt: at(30),
            },
          ],
        },
        { branchId: "branch-1", teacherId: "teacher-1" },
      ),
    ).toEqual([]);
  });

  it("returns deterministic codes, resource refs and sorted lesson refs", () => {
    expect(
      sortConstraintViolations([
        violation(
          "ROOM_OVERLAP",
          { type: "room", id: "room-1" },
          [],
          ["lesson-b", "lesson-a", "lesson-a"],
        ),
        violation("OUTSIDE_BRANCH_HOURS", {
          type: "branch",
          id: "branch-1",
        }),
        violation(
          "TEACHER_OVERLAP",
          { type: "teacher", id: "teacher-1" },
          [],
          ["lesson-c"],
        ),
      ]),
    ).toEqual([
      violation("OUTSIDE_BRANCH_HOURS", {
        type: "branch",
        id: "branch-1",
      }),
      violation(
        "TEACHER_OVERLAP",
        { type: "teacher", id: "teacher-1" },
        [],
        ["lesson-c"],
      ),
      violation(
        "ROOM_OVERLAP",
        { type: "room", id: "room-1" },
        [],
        ["lesson-a", "lesson-b"],
      ),
    ]);
  });
});

function seededRandom(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1_664_525) + 1_013_904_223) >>> 0;
    return state / 0x1_0000_0000;
  };
}
