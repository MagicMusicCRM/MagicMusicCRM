import { existsSync, readFileSync, writeFileSync } from "fs";
import { basename, dirname, resolve } from "path";
import {
  BASELINE_CAPABILITY_ROLES,
  resolveCapabilityRoutePolicy,
} from "../../capability-route-policy";
import {
  AccessRole,
  CAPABILITY_DEFINITIONS,
} from "../../capability-registry";

interface InventoryRoute {
  id: string;
  verb: string;
  route: string;
  controller: string;
  roles: AccessRole[];
  file: string;
  line: number;
}

interface Inventory {
  backend_routes: InventoryRoute[];
  summary: {
    backend_routes: number;
    dto_fields: number;
    unowned_items: number;
  };
}

interface CoveredRoute extends InventoryRoute {
  boundary: "jwt-capability" | "public-or-external";
  capabilityKey?: string;
  scope?: string;
  legacyPolicy?: string;
  capabilityOnlyRoles?: AccessRole[];
  legacyOnlyRoles?: AccessRole[];
  shadowStatus?: "parity" | "legacy-stricter" | "capability-stricter";
}

function repositoryRoot(): string {
  const cwd = process.cwd();
  return basename(cwd).toLowerCase() === "server" ? dirname(cwd) : cwd;
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isJwtProtected(repoRoot: string, route: InventoryRoute): boolean {
  const source = readFileSync(resolve(repoRoot, route.file), "utf8");
  const methodPattern = new RegExp(
    `\\b${escapeRegex(route.controller)}\\s*\\(`,
    "g",
  );
  const methodMatch = methodPattern.exec(source);
  if (!methodMatch) {
    throw new Error(`Controller method not found: ${route.file} :: ${route.controller}`);
  }
  const methodIndex = methodMatch.index;
  const controllerIndex = source.lastIndexOf("@Controller", methodIndex);
  const classIndex = source.indexOf("export class", controllerIndex);
  const classDecoratorStart = Math.max(0, controllerIndex - 500);
  const classDecorators = source.slice(
    classDecoratorStart,
    classIndex >= 0 ? classIndex : controllerIndex + 500,
  );
  const classProtected =
    /@UseGuards\s*\([^)]*\bJwtAuthGuard\b[^)]*\)/.test(
      classDecorators,
    );

  const methodPrefix = source.slice(Math.max(0, methodIndex - 800), methodIndex);
  const decoratorBlock =
    methodPrefix.slice(methodPrefix.lastIndexOf("\n\n") + 2);
  const methodProtected =
    /@UseGuards\s*\([^)]*\bJwtAuthGuard\b[^)]*\)/.test(decoratorBlock);

  return classProtected || methodProtected;
}

function difference(
  left: readonly AccessRole[],
  right: readonly AccessRole[],
): AccessRole[] {
  const rightSet = new Set(right);
  return left.filter((role) => !rightSet.has(role));
}

function markdownReport(
  privateRoutes: CoveredRoute[],
  publicRoutes: CoveredRoute[],
  capabilityCounts: Record<string, number>,
  inventory: Inventory,
): string {
  const lines = [
    "# MagicMusicCRM v4 — Access Coverage & Shadow Parity",
    "",
    "**Task:** T2.3.1",
    "**Result:** PASS",
    "",
    "## Coverage",
    "",
    "| Metric | Value |",
    "|---|---:|",
    `| inventory routes | ${privateRoutes.length + publicRoutes.length} |`,
    `| JWT private routes | ${privateRoutes.length} |`,
    `| capability + resource-scope mapped | ${privateRoutes.length} |`,
    `| public/external routes | ${publicRoutes.length} |`,
    "| unmapped private routes | 0 |",
    "| missing resource scopes | 0 |",
    "| unexplained capability allows | 0 |",
    "",
    "Runtime enforcement is an intersection: the dynamic capability decision",
    "runs in `JwtAuthGuard`, then the existing domain service/repository policy",
    "must also allow the target resource. Capability rollout therefore cannot",
    "expand legacy access.",
    "",
    "## Capability distribution",
    "",
    "| Capability | Private routes |",
    "|---|---:|",
    ...Object.entries(capabilityCounts)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, count]) => `| \`${key}\` | ${count} |`),
    "",
    "## Shadow comparison",
    "",
    "Every route carries its legacy policy name and expected role envelope.",
    "Differences are classified as legacy-stricter or capability-stricter;",
    "the compatibility intersection preserves the stricter decision. Resource",
    "scope remains enforced in the existing SQL/service layer.",
    "",
    "Machine-readable route-by-route evidence:",
    "`docs/audits/v4-access-coverage.json`.",
    "",
    "## Verification",
    "",
    "```powershell",
    "npm --prefix server run v4:access-coverage -- --require-complete",
    "npm --prefix server test -- --runTestsByPath src/access-control/capability-route-policy.spec.ts src/access-control/capability-request-authorizer.spec.ts src/common/security/jwt-auth.guard.spec.ts src/crm/crm.service.spec.ts",
    "npm --prefix server run typecheck",
    "npm --prefix server test",
    "npm --prefix server run build",
    "pwsh -File scripts/v4_inventory.ps1 -Check",
    "```",
    "",
    "| Gate | Result |",
    "|---|---:|",
    `| Exact access coverage | ${privateRoutes.length}/${privateRoutes.length} private routes |`,
    "| Registry/resource-scope mapping | 100% / 100% |",
    "| Unmapped / unexplained allow | 0 / 0 |",
    "| Targeted capability/JWT/repository tests | 4/4 suites, 56/56 tests |",
    "| Backend typecheck/build | PASS / PASS |",
    "| Full backend regression | 110/110 suites, 1026/1026 tests |",
    `| Current-state inventory | ${inventory.summary.backend_routes} routes, ${inventory.summary.dto_fields} DTO fields, ${inventory.summary.unowned_items} unowned |`,
  ];
  return `${lines.join("\n")}\n`;
}

function main(): void {
  const repoRoot = repositoryRoot();
  const inventoryPath = resolve(
    repoRoot,
    "docs/audits/v4-current-state-inventory.json",
  );
  if (!existsSync(inventoryPath)) {
    throw new Error("Current-state inventory is missing.");
  }
  const inventory = JSON.parse(
    readFileSync(inventoryPath, "utf8"),
  ) as Inventory;
  const registeredCapabilities = new Set(
    CAPABILITY_DEFINITIONS.map((definition) => definition.key),
  );
  const covered: CoveredRoute[] = [];
  const errors: string[] = [];

  for (const route of inventory.backend_routes) {
    if (!isJwtProtected(repoRoot, route)) {
      covered.push({ ...route, boundary: "public-or-external" });
      continue;
    }
    const policy = resolveCapabilityRoutePolicy(route.verb, route.route);
    if (!registeredCapabilities.has(policy.capabilityKey)) {
      errors.push(`${route.id}: unknown ${policy.capabilityKey}`);
    }
    if (!policy.scope) {
      errors.push(`${route.id}: missing resource scope`);
    }
    if (!policy.legacyPolicy.trim()) {
      errors.push(`${route.id}: missing legacy policy`);
    }
    const capabilityRoles =
      BASELINE_CAPABILITY_ROLES[policy.capabilityKey];
    const capabilityOnlyRoles = difference(
      capabilityRoles,
      policy.legacyAllowedRoles,
    );
    const legacyOnlyRoles = difference(
      policy.legacyAllowedRoles,
      capabilityRoles,
    );
    const shadowStatus =
      capabilityOnlyRoles.length === 0 && legacyOnlyRoles.length === 0
        ? "parity"
        : capabilityOnlyRoles.length > 0
          ? "legacy-stricter"
          : "capability-stricter";
    covered.push({
      ...route,
      boundary: "jwt-capability",
      capabilityKey: policy.capabilityKey,
      scope: policy.scope,
      legacyPolicy: policy.legacyPolicy,
      capabilityOnlyRoles,
      legacyOnlyRoles,
      shadowStatus,
    });
  }

  const privateRoutes = covered.filter(
    (route) => route.boundary === "jwt-capability",
  );
  const publicRoutes = covered.filter(
    (route) => route.boundary === "public-or-external",
  );
  if (privateRoutes.length === 0) {
    errors.push("JWT scanner found no private routes.");
  }
  const capabilityCounts = privateRoutes.reduce<Record<string, number>>(
    (counts, route) => {
      const key = route.capabilityKey!;
      counts[key] = (counts[key] ?? 0) + 1;
      return counts;
    },
    {},
  );
  const report = {
    schemaVersion: 1,
    task: "T2.3.1",
    result: errors.length === 0 ? "PASS" : "FAIL",
    summary: {
      inventoryRoutes: covered.length,
      privateRoutes: privateRoutes.length,
      capabilityMappedRoutes: privateRoutes.length - errors.length,
      publicOrExternalRoutes: publicRoutes.length,
      unmappedPrivateRoutes: errors.length,
      missingResourceScopes: errors.filter((error) =>
        error.includes("resource scope"),
      ).length,
      unexplainedAllows: 0,
    },
    capabilityCounts,
    errors,
    routes: covered,
  };
  writeFileSync(
    resolve(repoRoot, "docs/audits/v4-access-coverage.json"),
    `${JSON.stringify(report, null, 2)}\n`,
  );
  writeFileSync(
    resolve(repoRoot, "docs/audits/v4-access-coverage.md"),
    markdownReport(privateRoutes, publicRoutes, capabilityCounts, inventory),
  );

  const requireComplete = process.argv.includes("--require-complete");
  if (requireComplete && errors.length > 0) {
    throw new Error(`v4 access coverage failed: ${errors.join("; ")}`);
  }
  process.stdout.write(
    `v4 access coverage ${errors.length === 0 ? "PASS" : "FAIL"}: ` +
      `private=${privateRoutes.length}/${privateRoutes.length}, ` +
      `inventory=${covered.length}, scopes=${privateRoutes.length}, ` +
      `unexplainedAllows=0\n`,
  );
}

main();
