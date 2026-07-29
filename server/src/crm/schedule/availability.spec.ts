import { BadRequestException } from "@nestjs/common";
import {
  assertAvailabilityRules,
  assertBranchHours,
  assertTeacherBranches,
  parseReferenceRange,
} from "./availability.rules";

describe("schedule availability rules", () => {
  it("keeps explicit UTC instants stable across a DST boundary", () => {
    const range = parseReferenceRange(
      "2026-03-29T00:30:00+01:00",
      "2026-03-29T03:30:00+02:00",
    );
    expect(range.from.toISOString()).toBe("2026-03-28T23:30:00.000Z");
    expect(range.to.toISOString()).toBe("2026-03-29T01:30:00.000Z");
    expect(range.to.getTime() - range.from.getTime()).toBe(2 * 60 * 60 * 1000);
  });

  it("rejects reversed and unbounded reference ranges", () => {
    expect(() =>
      parseReferenceRange("2026-04-01T00:00:00Z", "2026-03-01T00:00:00Z"),
    ).toThrow(BadRequestException);
    expect(() =>
      parseReferenceRange("2026-01-01T00:00:00Z", "2026-03-01T00:00:00Z"),
    ).toThrow("cannot exceed 32 days");
  });

  it("rejects duplicate weekdays, malformed exceptions and branch ranges", () => {
    expect(() =>
      assertBranchHours(
        [
          { weekday: 1, open: "09:00", close: "18:00" },
          { weekday: 1, open: "10:00", close: "17:00" },
        ],
        [],
      ),
    ).toThrow("Weekday must be unique");
    expect(() =>
      assertBranchHours(
        [{ weekday: 1, open: "09:00", close: "18:00" }],
        [{ date: "2026-05-01", closed: true, open: "10:00" }],
      ),
    ).toThrow("Invalid branch-hours exception");
    expect(() =>
      assertTeacherBranches([
        {
          branchId: "00000000-0000-4000-8000-000000000001",
          activeFrom: "2026-05-02",
          activeUntil: "2026-05-01",
        },
      ]),
    ).toThrow("interval is invalid");
  });

  it("supports recurring, bounded interval and indefinite unavailability", () => {
    expect(() =>
      assertAvailabilityRules([
        {
          kind: "recurring",
          available: true,
          timezone: "Europe/Berlin",
          weekday: 7,
          localStart: "09:00",
          localEnd: "18:00",
          validFrom: "2026-01-01",
        },
        {
          kind: "interval",
          available: false,
          startsAt: "2026-04-01T00:00:00Z",
        },
        {
          kind: "interval",
          available: true,
          startsAt: "2026-04-01T00:00:00Z",
          endsAt: "2026-04-01T01:00:00Z",
        },
      ]),
    ).not.toThrow();
    expect(() =>
      assertAvailabilityRules([
        {
          kind: "interval",
          available: true,
          startsAt: "2026-04-01T00:00:00Z",
        },
      ]),
    ).toThrow("Invalid interval availability rule");
  });
});
