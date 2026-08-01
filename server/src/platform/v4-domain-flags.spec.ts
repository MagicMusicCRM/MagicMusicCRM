import { resolveV4DomainRollout } from "./v4-domain-flags";

describe("T8.3.3 domain compatibility flags", () => {
  it("defaults to legacy execution with shadow comparison", () => {
    expect(resolveV4DomainRollout("access", {}, 0)).toMatchObject({
      configuredMode: "shadow",
      effectivePath: "legacy",
      shadowCompare: true,
      enableAllowed: true,
    });
  });

  it("blocks v4 enable while an unexplained diff exists", () => {
    expect(resolveV4DomainRollout(
      "schedule",
      { V4_SCHEDULE_MODE: "v4" },
      1,
    )).toMatchObject({
      effectivePath: "legacy",
      shadowCompare: true,
      enableAllowed: false,
      reason: "unexplained_parity_diff",
    });
  });

  it("uses the kill switch as an immediate legacy fallback", () => {
    expect(resolveV4DomainRollout(
      "access",
      { V4_ACCESS_MODE: "v4", V4_ACCESS_KILL_SWITCH: "true" },
      0,
    )).toMatchObject({
      effectivePath: "legacy",
      shadowCompare: false,
      killSwitch: true,
      enableAllowed: false,
    });
  });
});
