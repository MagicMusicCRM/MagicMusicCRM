import { verify } from "crypto";
import {
  canonicalJson,
  invariants,
  signReport,
} from "./v4-reconcile";

describe("v4 reconciliation report", () => {
  it("defines unique named invariants across all required systems", () => {
    const ids = invariants.map((invariant) => invariant.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids).toEqual(
      expect.arrayContaining([
        "finance.payment-facts",
        "finance.adjustment-facts",
        "finance.balance-facts",
        "commerce.subscription-facts",
        "commerce.installment-facts",
        "commerce.obligation-facts",
        "commerce.lifecycle-facts",
        "commerce.client-payment-records",
        "commerce.client-payment-status-events",
        "commerce.reporting-exclusions",
        "commerce.lesson-charge-facts",
        "commerce.teacher-compensation-facts",
        "commerce.reservation-facts",
        "schedule.lesson-facts",
        "schedule.participation-facts",
        "workflow.task-facts",
        "access.role-mappings",
      ]),
    );
    expect(invariants.filter((invariant) => invariant.economic)).toHaveLength(11);
  });

  it("signs canonical report content and detects tampering", () => {
    const unsigned: Parameters<typeof signReport>[0] = {
      schemaVersion: 1,
      task: "T8.1.5",
      generatedAt: "2026-07-25T00:00:00.000Z",
      mode: "fixture",
      source: "clean:source",
      target: "clean:target",
      status: "clean",
      tolerancePolicy: {
        economicFacts: 0,
        unexplainedFacts: 0,
      },
      summary: {
        invariants: 1,
        sourceFacts: 1,
        targetFacts: 1,
        invariantsWithDrift: 0,
        unexplainedDiff: 0,
      },
      invariants: [
        {
          id: "finance.payment-facts",
          owner: "SYS-COMMERCE",
          economic: true,
          tolerance: 0,
          description: "fixture",
          sourceCount: 1,
          targetCount: 1,
          sourceDigestSha256: "a".repeat(64),
          targetDigestSha256: "a".repeat(64),
          unexplainedDiff: [],
        },
      ],
    };
    const report = signReport(unsigned);
    const signature = Buffer.from(report.signature.valueBase64, "base64");
    expect(
      verify(
        null,
        Buffer.from(canonicalJson(unsigned), "utf8"),
        report.signature.publicKeyPem,
        signature,
      ),
    ).toBe(true);
    expect(
      verify(
        null,
        Buffer.from(
          canonicalJson({ ...unsigned, status: "drift" }),
          "utf8",
        ),
        report.signature.publicKeyPem,
        signature,
      ),
    ).toBe(false);
  });
});
