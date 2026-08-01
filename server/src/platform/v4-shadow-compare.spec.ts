import { readFileSync } from "fs";
import { resolve } from "path";
import { runShadowCompare } from "./v4-shadow-compare";

describe("T8.3.3 shadow compare", () => {
  it("explains every access difference and keeps schedule parity", () => {
    const coverage = JSON.parse(readFileSync(resolve(
      __dirname,
      "..",
      "..",
      "..",
      "docs",
      "audits",
      "v4-access-coverage.json",
    ), "utf8"));
    const report = runShadowCompare(coverage);

    expect(report.summary).toMatchObject({
      accessDecisions: 1_650,
      scheduleDecisions: 2_000,
      unexplainedDifferences: 0,
    });
    expect(report.summary.differences).toBeGreaterThan(0);
    expect(report.summary.explainedDifferences).toBe(
      report.summary.differences,
    );
    expect(report.safeDiffs.every((diff) =>
      diff.domain !== "schedule" && diff.explanation !== null,
    )).toBe(true);
  });
});
