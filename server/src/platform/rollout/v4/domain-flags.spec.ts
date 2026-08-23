import { ServiceUnavailableException } from "@nestjs/common";
import {
  resolveV4DomainRollout,
  V4DomainFlagsService,
} from "./domain-flags";

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

  it("fails closed when production is not on verified v4", () => {
    expect(() => resolveV4DomainRollout(
      "schedule",
      { NODE_ENV: "production", V4_SCHEDULE_MODE: "shadow" },
      0,
    )).toThrow("verified v4 execution");
  });
});

describe("V4DomainFlagsService runtime boundary", () => {
  const original = { ...process.env };

  afterEach(() => {
    process.env = { ...original };
  });

  it("rejects v4-only execution while shadow keeps the legacy path", () => {
    process.env.V4_ACCESS_MODE = "shadow";
    process.env.V4_PARITY_UNEXPLAINED_DIFFS = "0";

    expect(() => new V4DomainFlagsService().assertEnabled("access"))
      .toThrow(ServiceUnavailableException);
  });

  it("allows v4-only execution only after the domain is enabled", () => {
    process.env.V4_SCHEDULE_MODE = "v4";
    process.env.V4_PARITY_UNEXPLAINED_DIFFS = "0";

    expect(new V4DomainFlagsService().assertEnabled("schedule"))
      .toMatchObject({ effectivePath: "v4", enableAllowed: true });
  });
});
