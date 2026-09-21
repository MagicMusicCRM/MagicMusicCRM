import {
  intersectIntervals,
  subtractIntervals,
  unionIntervals,
  utilizationPercent,
} from "./utilization-read.service";

const at = (hour: number) => new Date(Date.UTC(2026, 8, 21, hour));

describe("utilization interval math", () => {
  it("unions overlapping occupied lessons before calculating minutes", () => {
    expect(
      unionIntervals([
        { start: at(9), end: at(11) },
        { start: at(10), end: at(12) },
      ]),
    ).toEqual([{ start: at(9), end: at(12) }]);
  });

  it("intersects positive availability and subtracts unavailable windows", () => {
    const branch = [{ start: at(9), end: at(18) }];
    const positive = [{ start: at(10), end: at(17) }];
    const unavailable = [{ start: at(13), end: at(15) }];
    expect(
      subtractIntervals(intersectIntervals(branch, positive), unavailable),
    ).toEqual([
      { start: at(10), end: at(13) },
      { start: at(15), end: at(17) },
    ]);
  });

  it("returns no percentage when working windows are not configured", () => {
    expect(utilizationPercent(120, 0)).toBeNull();
    expect(utilizationPercent(120, 240)).toBe(0.5);
  });
});
