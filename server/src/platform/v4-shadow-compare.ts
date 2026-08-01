import { createHash } from "crypto";
import { mkdirSync, readFileSync, writeFileSync } from "fs";
import { resolve } from "path";
import {
  AccessRole,
  USER_ROLES,
} from "../access-control/capability-registry";
import { BASELINE_CAPABILITY_ROLES } from "../access-control/capability-route-policy";
import { halfOpenIntervalsOverlap } from "../crm/schedule/constraint-engine.rules";
import { resolveV4DomainRollout } from "./v4-domain-flags";

type ShadowStatus = "parity" | "legacy-stricter" | "capability-stricter";

interface AccessRoute {
  id: string;
  boundary: "jwt-capability" | "public-or-external";
  capabilityKey?: keyof typeof BASELINE_CAPABILITY_ROLES;
  capabilityOnlyRoles?: AccessRole[];
  legacyOnlyRoles?: AccessRole[];
  shadowStatus?: ShadowStatus;
}

interface AccessCoverage {
  routes: AccessRoute[];
}

interface SafeDiff {
  domain: "access" | "schedule";
  corpusId: string;
  legacyAllowed: boolean;
  v4Allowed: boolean;
  explanation: string | null;
}

interface ShadowReport {
  schemaVersion: 1;
  task: "T8.3.3";
  generatedAt: string;
  summary: {
    accessDecisions: number;
    scheduleDecisions: number;
    differences: number;
    explainedDifferences: number;
    unexplainedDifferences: number;
  };
  safeDiffs: SafeDiff[];
  featureFlags: ReturnType<typeof resolveV4DomainRollout>[];
  proof: {
    requestCorpusDigestSha256: string;
    safePayload: true;
  };
}

const serverRoot = resolve(__dirname, "..", "..");
const repoRoot = resolve(serverRoot, "..");
const accessCoveragePath = resolve(
  repoRoot,
  "docs",
  "audits",
  "v4-access-coverage.json",
);

function legacyDecision(
  role: AccessRole,
  capabilityAllowed: boolean,
  capabilityOnly: readonly AccessRole[],
  legacyOnly: readonly AccessRole[],
): boolean {
  if (capabilityOnly.includes(role)) return false;
  if (legacyOnly.includes(role)) return true;
  return capabilityAllowed;
}

function expectedExplanation(
  route: AccessRoute,
  role: AccessRole,
  legacyAllowed: boolean,
  v4Allowed: boolean,
): string | null {
  if (legacyAllowed === v4Allowed) return "parity";
  if (
    route.shadowStatus === "legacy-stricter"
    && route.capabilityOnlyRoles?.includes(role)
    && !legacyAllowed
    && v4Allowed
  ) return "legacy_stricter_intersection";
  if (
    route.shadowStatus === "capability-stricter"
    && route.legacyOnlyRoles?.includes(role)
    && legacyAllowed
    && !v4Allowed
  ) return "capability_stricter_intersection";
  return null;
}

function compareAccess(coverage: AccessCoverage): {
  decisions: number;
  diffs: SafeDiff[];
} {
  const diffs: SafeDiff[] = [];
  let decisions = 0;
  for (const route of coverage.routes) {
    if (route.boundary !== "jwt-capability" || !route.capabilityKey) continue;
    const allowedRoles = BASELINE_CAPABILITY_ROLES[route.capabilityKey];
    const capabilityOnly = route.capabilityOnlyRoles ?? [];
    const legacyOnly = route.legacyOnlyRoles ?? [];
    for (const role of USER_ROLES) {
      decisions += 1;
      const v4Allowed = allowedRoles.includes(role);
      const legacyAllowed = legacyDecision(
        role,
        v4Allowed,
        capabilityOnly,
        legacyOnly,
      );
      if (legacyAllowed !== v4Allowed) {
        diffs.push({
          domain: "access",
          corpusId: `${route.id}:${role}`,
          legacyAllowed,
          v4Allowed,
          explanation: expectedExplanation(
            route,
            role,
            legacyAllowed,
            v4Allowed,
          ),
        });
      }
    }
  }
  return { decisions, diffs };
}

function seeded(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1_664_525) + 1_013_904_223) >>> 0;
    return state / 0x1_0000_0000;
  };
}

function compareSchedule(cases = 2_000): {
  decisions: number;
  diffs: SafeDiff[];
  corpus: Array<[number, number, number, number]>;
} {
  const random = seeded(0x4833_01);
  const diffs: SafeDiff[] = [];
  const corpus: Array<[number, number, number, number]> = [];
  for (let index = 0; index < cases; index += 1) {
    const leftStart = Math.floor(random() * 10_000);
    const leftEnd = leftStart + 1 + Math.floor(random() * 240);
    const rightStart = index % 10 === 0
      ? leftEnd
      : Math.floor(random() * 10_000);
    const rightEnd = rightStart + 1 + Math.floor(random() * 240);
    corpus.push([leftStart, leftEnd, rightStart, rightEnd]);
    const legacyAllowed = !(
      leftStart < rightEnd && rightStart < leftEnd
    );
    const epoch = Date.UTC(2026, 0, 1);
    const v4Allowed = !halfOpenIntervalsOverlap(
      {
        startAt: new Date(epoch + leftStart * 60_000),
        endAt: new Date(epoch + leftEnd * 60_000),
      },
      {
        startAt: new Date(epoch + rightStart * 60_000),
        endAt: new Date(epoch + rightEnd * 60_000),
      },
    );
    if (legacyAllowed !== v4Allowed) {
      diffs.push({
        domain: "schedule",
        corpusId: `interval-${index}`,
        legacyAllowed,
        v4Allowed,
        explanation: null,
      });
    }
  }
  return { decisions: cases, diffs, corpus };
}

function runShadowCompare(coverage: AccessCoverage): ShadowReport {
  const access = compareAccess(coverage);
  const schedule = compareSchedule();
  const safeDiffs = [...access.diffs, ...schedule.diffs];
  const explainedDifferences = safeDiffs.filter(
    (diff) => diff.explanation !== null,
  ).length;
  const unexplainedDifferences = safeDiffs.length - explainedDifferences;
  const corpusDigest = createHash("sha256")
    .update(JSON.stringify({
      accessRoutes: coverage.routes.map((route) => route.id),
      schedule: schedule.corpus,
    }))
    .digest("hex");
  return {
    schemaVersion: 1,
    task: "T8.3.3",
    generatedAt: new Date().toISOString(),
    summary: {
      accessDecisions: access.decisions,
      scheduleDecisions: schedule.decisions,
      differences: safeDiffs.length,
      explainedDifferences,
      unexplainedDifferences,
    },
    safeDiffs,
    featureFlags: [
      resolveV4DomainRollout("access", process.env, unexplainedDifferences),
      resolveV4DomainRollout("schedule", process.env, unexplainedDifferences),
    ],
    proof: {
      requestCorpusDigestSha256: corpusDigest,
      safePayload: true,
    },
  };
}

function writeReport(report: ShadowReport): string {
  const directory = resolve(repoRoot, "docs", "audits");
  mkdirSync(directory, { recursive: true });
  const path = resolve(directory, "v4-shadow-compare.json");
  writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  return path;
}

function main(): void {
  const coverage = JSON.parse(
    readFileSync(accessCoveragePath, "utf8"),
  ) as AccessCoverage;
  const report = runShadowCompare(coverage);
  const path = writeReport(report);
  process.stdout.write(`${JSON.stringify({
    task: report.task,
    summary: report.summary,
    featureFlags: report.featureFlags,
    report: path.replace(`${repoRoot}\\`, "").replace(/\\/g, "/"),
  })}\n`);
  if (
    process.argv.includes("--require-zero-unexplained")
    && report.summary.unexplainedDifferences > 0
  ) process.exitCode = 2;
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`v4 shadow compare failed: ${message}\n`);
    process.exitCode = 1;
  }
}

export { compareAccess, compareSchedule, runShadowCompare };
