# CRM Configuration Service Semantic Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `CrmConfigurationService` god class by extracting typed, directly tested snapshot, branch, and impact policies while preserving the canonical persistence lifecycle.

**Architecture:** Move dependency-free types to the existing contract module and move pure policy behavior to three function modules. Keep the controller-facing service as the only lifecycle/persistence owner; it supplies the existing database or transaction executor through narrow callbacks where policy needs stored-value evidence.

**Tech Stack:** NestJS, TypeScript, Jest, PostgreSQL integration tests, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-25-crm-configuration-service-semantic-split-design.md`

## Global Constraints

- Do not change API routes, DTOs, response shapes, SQL semantics, schema, migrations, or stored data.
- Preserve RBAC, branch scope, commerce capability locking, advisory locks, expected versions, immutable revisions, audit, and realtime fanout.
- Keep `CrmConfigurationService` as the only controller-facing lifecycle owner; do not add a compatibility facade or runtime provider for pure policy functions.
- Preserve every current Russian validation message, error code, field path, warning, and affected-screen identifier.
- After every structural commit, require Sentrux quality `>=4974`, acyclicity `1`, depth `<=13`, and both architecture rules passing.
- Final RepoWise targets: service and every extracted owner health `>=7.0`, service max CCN `<=10`, service NLOC `<=750`, combined weighted deficit `<=2000`.

---

### Task 1: Move configuration contracts to the dependency-free owner

**Files:**

- Modify: `server/src/crm/crm-configuration.contracts.ts`
- Modify: `server/src/crm/crm-configuration.contracts.spec.ts`
- Modify: `server/src/crm/crm-configuration-baseline.ts`
- Modify: `server/src/crm/crm-configuration.service.ts`
- Modify: `server/src/crm/crm-configuration-postgres.integration.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-postgres.integration.spec.ts`

**Interfaces:**

- Consumes: existing `LessonSettlementTypeConfig` and `TeacherCompensationRuleConfig`.
- Produces: exported `ConfigCategory`, `ConfigField`, `ConfigOptionSet`, `ConfigSetting`, `ConfigSnapshot`, `ConfigBranchPatch`, and `ImpactReport` interfaces.

- [ ] **Step 1: Write the failing contract import test**

Add a type import and complete literal to
`crm-configuration.contracts.spec.ts` before moving the types:

```ts
import type { ConfigSnapshot } from "./crm-configuration.contracts";

const contractSnapshot: ConfigSnapshot = {
  categories: [],
  fields: [],
  optionSets: [],
  businessSettings: [],
  lessonSettlementTypes: [],
  teacherCompensationRules: [],
};

it("owns the complete configuration snapshot contract", () => {
  expect(Object.keys(contractSnapshot).sort()).toEqual([
    "businessSettings",
    "categories",
    "fields",
    "lessonSettlementTypes",
    "optionSets",
    "teacherCompensationRules",
  ]);
});
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
npm --prefix server run typecheck
```

Expected: TypeScript fails with `TS2305` because `ConfigSnapshot` is not yet
exported by `crm-configuration.contracts.ts`.

- [ ] **Step 3: Move the interfaces and migrate type imports**

Move the seven interfaces byte-for-byte from the service into the contract
module. Change every live import found by:

```powershell
rg -n "Config(Category|Field|OptionSet|Setting|Snapshot|BranchPatch)|ImpactReport" server/src/crm
```

Production and tests must import from `crm-configuration.contracts.ts`; remove
the service re-exports rather than keeping aliases. Do not move `RevisionRow`,
`Queryable`, `runQuery`, or persistence SQL.

- [ ] **Step 4: Verify GREEN and compile all consumers**

Run:

```powershell
npm --prefix server test -- --runInBand src/crm/crm-configuration.contracts.spec.ts src/crm/crm-configuration-postgres.integration.spec.ts src/crm/commerce/lesson-settlement-postgres.integration.spec.ts
npm --prefix server run typecheck
git diff --check
```

Expected: all selected suites and typecheck pass; no production file except the
contract module declares the moved interfaces.

- [ ] **Step 5: Run architecture gates and commit**

Run Sentrux rescan, health, and rules; run `repowise update --index-only`.
Commit:

```powershell
git add -- server/src/crm/crm-configuration.contracts.ts server/src/crm/crm-configuration.contracts.spec.ts server/src/crm/crm-configuration-baseline.ts server/src/crm/crm-configuration.service.ts server/src/crm/crm-configuration-postgres.integration.spec.ts server/src/crm/commerce/lesson-settlement-postgres.integration.spec.ts
git commit -m "refactor(crm): centralize configuration contracts"
```

### Task 2: Extract snapshot normalization as tested pure policy

**Files:**

- Create: `server/src/crm/crm-configuration-snapshot-normalizer.ts`
- Create: `server/src/crm/crm-configuration-snapshot-normalizer.spec.ts`
- Modify: `server/src/crm/crm-configuration.service.ts`

**Interfaces:**

- Consumes: `ConfigCategory`, `ConfigField`, `ConfigOptionSet`, `ConfigSetting`, `ConfigSnapshot`, `LessonSettlementTypeConfig`, and `TeacherCompensationRuleConfig`.
- Produces: `normalizeCrmConfigurationSnapshot(raw: Record<string, unknown>): ConfigSnapshot`.

- [ ] **Step 1: Write the first failing snapshot test**

Create the spec with a complete hand-authored snapshot that contains duplicate
legacy Lead/Student copies of one field. Import the missing function and assert
the literal merged result:

```ts
const normalized = normalizeCrmConfigurationSnapshot(rawSnapshot);

expect(normalized.fields).toEqual([
  expect.objectContaining({
    key: "phone",
    required: true,
    visibility: { lead: true, student: true },
  }),
]);
```

The fixture must include valid categories, option sets, both business settings,
one active settlement type, and one active compensation rule so the test
exercises the real entry point.

- [ ] **Step 2: Verify RED**

Run:

```powershell
npm --prefix server test -- --runInBand src/crm/crm-configuration-snapshot-normalizer.spec.ts
```

Expected: FAIL because the normalizer module/function does not exist.

- [ ] **Step 3: Implement the minimal composed parser**

Create the module and move validation behavior without semantic edits. The
entry point must read as composition:

```ts
export function normalizeCrmConfigurationSnapshot(
  raw: Record<string, unknown>,
): ConfigSnapshot {
  const categories = normalizeCategories(raw.categories);
  const fields = normalizeFields(raw.fields, new Set(categories.map((row) => row.key)));
  const optionSets = normalizeOptionSets(raw.optionSets ?? []);
  applyOptionSets(fields, optionSets);
  return {
    categories,
    fields,
    optionSets,
    businessSettings: normalizeBusinessSettings(raw.businessSettings),
    lessonSettlementTypes: normalizeSettlementTypes(raw.lessonSettlementTypes),
    teacherCompensationRules: normalizeCompensationRules(raw.teacherCompensationRules),
  };
}
```

Use focused private functions `normalizeCategories`, `normalizeFields`,
`mergeLegacyFields`, `normalizeOptionSets`, `applyOptionSets`,
`normalizeBusinessSettings`, `normalizeSettlementTypes`, and
`normalizeCompensationRules`. Keep primitive readers as module functions
`readArray`, `readObject`, `readText`, `readToken`, `readMinor`, `readKey`,
`readBoolean`, `readNumber`, `readInteger`, `assertUnique`, and `invalid`.

- [ ] **Step 4: Add and run one RED/GREEN case per rule family**

Before each implementation adjustment, add one failing behavior assertion for:

```text
unknown category; invalid placement; active field with no visibility;
incompatible legacy duplicate; unknown option set; setting bounds;
invalid settlement context; no active settlement type;
invalid compensation mode/value; no active compensation rule; stable ordering
```

Run the focused spec after every case. Expected final result: all new cases
pass and every failure preserves the original `{code, field, message}` body.

- [ ] **Step 5: Rewire the service and remove the brain method**

Import `normalizeCrmConfigurationSnapshot` and replace every
`this.normalizeSnapshot(...)` call. Delete `normalizeSnapshot` plus the eleven
primitive validation methods and moved constants from the service.

- [ ] **Step 6: Verify, gate, and commit**

Run:

```powershell
npm --prefix server test -- --runInBand src/crm/crm-configuration-snapshot-normalizer.spec.ts src/crm/crm-configuration-postgres.integration.spec.ts
npm --prefix server run typecheck
git diff --check
```

Then run Sentrux rescan/health/rules and `repowise update --index-only`.
Commit:

```powershell
git add -- server/src/crm/crm-configuration-snapshot-normalizer.ts server/src/crm/crm-configuration-snapshot-normalizer.spec.ts server/src/crm/crm-configuration.service.ts
git commit -m "refactor(crm): extract configuration snapshot policy"
```

### Task 3: Extract branch inheritance policy

**Files:**

- Create: `server/src/crm/crm-configuration-branch.policy.ts`
- Create: `server/src/crm/crm-configuration-branch.policy.spec.ts`
- Modify: `server/src/crm/crm-configuration.service.ts`

**Interfaces:**

- Consumes: `ConfigSnapshot` and `ConfigBranchPatch`.
- Produces: `createCrmConfigurationBranchPatch`, `applyCrmConfigurationBranchPatch`, `getCrmConfigurationSettingSources`, and `sameCrmConfigurationValue`.

- [ ] **Step 1: Write failing sparse-patch and attribution tests**

Use complete school/desired literals. Change one overridable setting and the
settlement catalog, then assert:

```ts
expect(createCrmConfigurationBranchPatch(school, desired)).toEqual({
  businessSettings: [desired.businessSettings[0]],
  lessonSettlementTypes: desired.lessonSettlementTypes,
});
expect(getCrmConfigurationSettingSources(desired, school)).toMatchObject({
  default_lesson_duration_minutes: "branch_override",
  payment_reminder_days: "school",
  lessonSettlementTypes: "branch_override",
  teacherCompensationRules: "school",
});
```

- [ ] **Step 2: Verify RED**

Run the new spec and expect module/function-not-found failure.

- [ ] **Step 3: Move the pure functions**

Move `sameJson`, `branchPatch`, `applyBranchPatch`, and `settingSources` without
changing equality, sparse settings, catalog omission, or source strings.
Rename only to the approved exported function names.

- [ ] **Step 4: Verify round-trip behavior**

Add a failing test first, then implement/confirm:

```ts
expect(
  applyCrmConfigurationBranchPatch(
    school,
    createCrmConfigurationBranchPatch(school, desired),
  ),
).toEqual(desired);
```

Run the branch spec and PostgreSQL configuration suite.

- [ ] **Step 5: Rewire, gate, and commit**

Replace the three private service methods and its equality calls with imports.
Run focused tests, typecheck, diff check, Sentrux gates, and RepoWise refresh.
Commit:

```powershell
git add -- server/src/crm/crm-configuration-branch.policy.ts server/src/crm/crm-configuration-branch.policy.spec.ts server/src/crm/crm-configuration.service.ts
git commit -m "refactor(crm): extract branch configuration policy"
```

### Task 4: Extract impact and migration-safety policy

**Files:**

- Create: `server/src/crm/crm-configuration-impact.policy.ts`
- Create: `server/src/crm/crm-configuration-impact.policy.spec.ts`
- Modify: `server/src/crm/crm-configuration.service.ts`

**Interfaces:**

- Consumes: `ConfigSnapshot`, `ImpactReport`, and
  `hasStoredClientFieldValues(definitionId: string): Promise<boolean>`.
- Produces:
  `buildCrmConfigurationImpact(input: CrmConfigurationImpactInput): Promise<ImpactReport>`.

- [ ] **Step 1: Write a failing branch-policy impact test**

Call the missing function with a branch snapshot that changes categories and a
non-overridable setting. Assert the exact two blocker codes and `valid:false`.

- [ ] **Step 2: Verify RED**

Run:

```powershell
npm --prefix server test -- --runInBand src/crm/crm-configuration-impact.policy.spec.ts
```

Expected: FAIL because the policy module/function does not exist.

- [ ] **Step 3: Implement the impact pipeline**

Compose the public function from focused stages:

```ts
export async function buildCrmConfigurationImpact(
  input: CrmConfigurationImpactInput,
): Promise<ImpactReport> {
  const blockingIssues = collectBranchIssues(input.next, input.school);
  collectStableCatalogIssues(blockingIssues, input.current, input.next);
  await collectFieldIssues(blockingIssues, input);
  return summarizeImpact(blockingIssues, input.current, input.next);
}
```

Move rules byte-for-byte. `collectFieldIssues` calls the supplied callback only
when an existing field with an `id` changes `valueType`.

- [ ] **Step 4: Add RED/GREEN tests for every blocker and projection family**

Add one failing case before implementing each family: stable-key removal,
system-field mutation, populated-field type change, fields created/updated/
archived, settings/catalog changes, warnings, and affected screens. Expected
values must be literal and the callback must return explicit true/false values.

- [ ] **Step 5: Rewire preview and publication to the correct executor**

Replace `this.buildImpact(...)` with:

```ts
buildCrmConfigurationImpact({
  next,
  current,
  school,
  hasStoredClientFieldValues: async (definitionId) => {
    const result = await runQuery<{ count: number | string }>(
      queryable,
      "select count(*) as count from app.client_custom_field_values where definition_id = $1",
      [definitionId],
    );
    return Number(result.rows[0]?.count ?? 0) > 0;
  },
});
```

The preview closure uses `DatabaseService`; the publish closure uses its
current transaction `PoolClient`. Delete the old `buildImpact` method.

- [ ] **Step 6: Verify, gate, and commit**

Run the impact spec, snapshot/branch specs, PostgreSQL configuration suite,
typecheck, and diff check. Run Sentrux and RepoWise. Commit:

```powershell
git add -- server/src/crm/crm-configuration-impact.policy.ts server/src/crm/crm-configuration-impact.policy.spec.ts server/src/crm/crm-configuration.service.ts
git commit -m "refactor(crm): extract configuration impact policy"
```

### Task 5: Prove the canonical service boundary and remove the god class

**Files:**

- Create: `server/src/crm/crm-configuration.service.spec.ts`
- Modify: `server/src/crm/crm-configuration.service.ts`

**Interfaces:**

- Consumes: the three extracted policy modules and existing database/policy/audit/realtime dependencies.
- Produces: the unchanged public `CrmConfigurationService` lifecycle API.

- [ ] **Step 1: Add service characterization before final cleanup**

Create a narrow fake `DatabaseService` that returns one complete stored school
revision. Test the real service method and literal projection:

```ts
await expect(service.getLessonDecisionCatalog(director)).resolves.toEqual({
  branchId: null,
  defaultLessonDurationMinutes: 45,
  settlementTypes: [activeSettlement],
  teacherCompensationRules: [activeCompensation],
});
```

This catches removal of active filtering, duration fallback/selection, or the
canonical read owner. Do not assert calls on the database fake.

- [ ] **Step 2: Run the characterization test against the pre-cleanup service**

Expected: PASS, establishing the observable baseline before deleting helpers.

- [ ] **Step 3: Remove obsolete declarations and imports**

Delete moved constants, interfaces, private methods, and re-exports. Keep only
lifecycle, scope, effective revision persistence, client-field sync,
authorization, branch existence, query helper, and revision DTO mapping.
Search:

```powershell
rg -n "normalizeSnapshot|buildImpact|branchPatch|applyBranchPatch|settingSources|export type \{" server/src/crm/crm-configuration.service.ts
```

Expected: no obsolete implementation owner remains.

- [ ] **Step 4: Run focused and full backend gates**

Run:

```powershell
npm --prefix server test -- --runInBand src/crm/crm-configuration.service.spec.ts src/crm/crm-configuration-snapshot-normalizer.spec.ts src/crm/crm-configuration-branch.policy.spec.ts src/crm/crm-configuration-impact.policy.spec.ts src/crm/crm-configuration-postgres.integration.spec.ts src/crm/crm-configuration.contracts.spec.ts src/app.module.spec.ts
npm --prefix server test -- --runInBand
npm --prefix server run typecheck
npm --prefix server run build
git diff --check
```

Expected: every suite passes with zero test failures; typecheck/build exit zero.

- [ ] **Step 5: Measure acceptance and perform only the evidence-triggered cut**

Refresh RepoWise and query health for the service and all extracted production
files. If the service is below `7.0`, above 750 NLOC/max CCN 10, or still has a
god-class/brain-method finding, stop and create a new red test around the
remaining effective-read or field-sync behavior before extracting it. Do not
create a repository abstraction when all thresholds already pass.

- [ ] **Step 6: Gate and commit**

Run Sentrux rescan/health/rules and verify the global floors. Commit:

```powershell
git add -- server/src/crm/crm-configuration.service.ts server/src/crm/crm-configuration.service.spec.ts
git commit -m "refactor(crm): remove configuration god class"
```

### Task 6: Record package evidence and re-rank the global portfolio

**Files:**

- Modify: `docs/superpowers/specs/2026-08-25-crm-configuration-service-semantic-split-design.md`
- Modify: `docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md`

**Interfaces:**

- Consumes: exact final RepoWise commit/health/deficit, Sentrux metrics, test totals, typecheck, and build output.
- Produces: package 3 evidence and the next active god-file directive.

- [ ] **Step 1: Capture exact evidence**

Record old/new NLOC, max CCN, health, combined weighted deficit, backend module
health, full test totals, and Sentrux quality/depth/acyclicity/modularity/
redundancy/rules. Do not infer missing numbers.

- [ ] **Step 2: Update both design documents**

Append a `Verified implementation outcome` section to the package spec and a
`Package 3 verified outcome` section to the recovery program. State explicitly
whether every acceptance threshold passed and identify the exact next RepoWise
directive.

- [ ] **Step 3: Verify docs, gate, and commit**

Run `git diff --check`, Sentrux rescan/health/rules, and refresh RepoWise at the
documentation HEAD. Commit:

```powershell
git add -- docs/superpowers/specs/2026-08-25-crm-configuration-service-semantic-split-design.md docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md
git commit -m "docs(crm): record configuration service split"
```

- [ ] **Step 4: Continue the global program**

Run RepoWise dashboard mode, select the highest recoverable weighted-deficit
production god file, and begin its pre-modification/design package. Do not mark
the global goal complete until all approved module and code-only health floors
are proven on one indexed commit.
