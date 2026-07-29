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

  it("rejects invalid instants and non-positive intervals", () => {
    expect(parseConstraintInterval("invalid", at(30))).toBeNull();
    expect(parseConstraintInterval(at(30), at(30))).toBeNull();
    expect(parseConstraintInterval(at(31), at(30))).toBeNull();
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
