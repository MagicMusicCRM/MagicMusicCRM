# Sentrux Health Ownership Flattening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant NestJS `HealthModule` layer while preserving all health routes, readiness behavior, and singleton dependencies.

**Architecture:** `AppModule` directly owns `HealthController` and `HealthService`. Its existing `DatabaseModule`, `CrmModule`, and `PlatformModule` imports continue supplying the four service dependencies; no health runtime logic moves.

**Tech Stack:** NestJS 11, TypeScript 5.8, Jest 30, RepoWise 0.42, Sentrux 0.5.7

**Spec:** `docs/superpowers/specs/2026-08-27-five-hour-hotspot-sprint-design.md`

## Global Constraints

- Modify only `server/src/app.module.ts`, `server/src/app.module.spec.ts`, and delete `server/src/health/health.module.ts`.
- Do not change controller/service bodies, routes, response shapes, readiness thresholds, workers, database access, rollout flags, lockfiles, Sentrux policy, or Sentrux baseline.
- Preserve one `HealthService`, one `HealthController`, and the existing singleton owners of `DatabaseService`, `LessonCompletionWorker`, `V4DomainFlagsService`, and `PlatformOutboxWorker`.
- Accept depth `<= 13`; another max-depth route remains through `MessengerModule`, so this lane must not claim `13 -> 12`.
- Produce one focused lane commit; RepoWise reindex and paired Sentrux scans belong to the coordinator after cherry-pick.

---

## File Structure

| Path | Action | Responsibility after the cut |
|---|---|---|
| `server/src/app.module.ts` | Modify | Direct health controller/service composition |
| `server/src/app.module.spec.ts` | Modify | Compiled-graph ownership regression tests |
| `server/src/health/health.module.ts` | Delete | Obsolete wrapper; no responsibility remains |
| `server/src/health/health.controller.ts` | Verify only | Unchanged routes and HTTP status behavior |
| `server/src/health/health.service.ts` | Verify only | Unchanged readiness aggregation |

The live wrapper is referenced only at `server/src/app.module.ts:13,42`. The four constructor tokens are at `server/src/health/health.service.ts:35-42`; their modules already export them and are already imported by `AppModule`.

## Baseline

Run from the lane worktree root:

```powershell
npm --prefix server test -- --runTestsByPath src/health/health.service.spec.ts src/health/health.controller.spec.ts src/app.module.spec.ts
```

Expected at the approved baseline: 3 suites and 23 tests pass. Stop and report if the lane worktree does not start green.

---

### Task 1: Freeze direct ownership with RED compiled-graph tests

**Files:**

- Modify: `server/src/app.module.spec.ts:17-18`
- Modify: `server/src/app.module.spec.ts:208`

**Interfaces:**

- Consumes: `HealthService`, `HealthController`, `findProviderOwners`, `findControllerOwners`, `expectSoleOwner`
- Produces: two tests requiring `AppModule` to be the sole compiled owner

- [ ] **Step 1: Add the health imports (2 minutes).**

Insert after the `DatabaseService` import:

```ts
import { HealthController } from "./health/health.controller";
import { HealthService } from "./health/health.service";
```

- [ ] **Step 2: Add the service ownership test (3 minutes).**

Insert before `"mounts the notification API shell directly"`:

```ts
  it("owns the health service directly", () => {
    expectSoleOwner(
      HealthService,
      findProviderOwners(modules, HealthService),
      appModuleType,
    );
  });
```

- [ ] **Step 3: Add the controller ownership test (3 minutes).**

Place it directly after the service test:

```ts
  it("owns the health controller directly", () => {
    expectSoleOwner(
      HealthController,
      findControllerOwners(modules, HealthController),
      appModuleType,
    );
  });
```

- [ ] **Step 4: Run the RED test (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/app.module.spec.ts
```

Expected: the suite fails in exactly the two new assertions because diagnostics name `HealthModule`, not `AppModule`. Any unrelated failure must be investigated before production edits.

### Task 2: Move health composition into AppModule

**Files:**

- Modify: `server/src/app.module.ts:13,22-45`
- Delete: `server/src/health/health.module.ts:1-13`

**Interfaces:**

- Consumes: exports from `DatabaseModule`, `CrmModule`, and `PlatformModule`
- Produces: one AppModule-owned `HealthController` and `HealthService`
- Preserves: `SafeLogger` provider/export and every existing module import other than `HealthModule`

- [ ] **Step 1: Replace the wrapper import (2 minutes).**

Apply this exact import change:

```diff
-import { HealthModule } from "./health/health.module";
+import { HealthController } from "./health/health.controller";
+import { HealthService } from "./health/health.service";
```

- [ ] **Step 2: Replace the module metadata (3 minutes).**

Apply this exact metadata change:

```diff
     SettingsModule,
     PlatformModule,
-    HealthModule,
   ],
-  providers: [SafeLogger],
+  controllers: [HealthController],
+  providers: [SafeLogger, HealthService],
   exports: [SafeLogger],
```

Do not export `HealthService`; its only health consumer is the directly owned controller.

- [ ] **Step 3: Delete the obsolete wrapper (2 minutes).**

Delete the complete tracked file:

```text
server/src/health/health.module.ts
```

- [ ] **Step 4: Run the GREEN ownership test (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/app.module.spec.ts
```

Expected: 1 suite and 15 tests pass. Nest compilation proves all four constructor tokens resolve; the new tests prove exactly one controller/service wrapper and direct `AppModule` ownership.

- [ ] **Step 5: Prove the wrapper has no references (3 minutes).**

```powershell
$healthModuleMatches = rg -n "HealthModule|health/health\.module" server/src
if ($LASTEXITCODE -eq 0) {
  $healthModuleMatches
  throw "HealthModule references remain"
}
if ($LASTEXITCODE -ne 1) {
  throw "rg failed while checking HealthModule references"
}
git diff --name-status -- server/src/app.module.ts server/src/app.module.spec.ts server/src/health/health.module.ts
```

Expected diff shape: two modified files and one deleted file, with no other `HealthModule` match.

### Task 3: Verify the lane and commit it

**Files:**

- Verify: `server/src/health/health.controller.spec.ts`
- Verify: `server/src/health/health.service.spec.ts`
- Commit: the two modifications and one deletion only

**Interfaces:**

- Produces: one cherry-pickable Lane B commit
- Commit message: `refactor(health): flatten health ownership into AppModule`

- [ ] **Step 1: Run the focused behavior suites (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/health/health.service.spec.ts src/health/health.controller.spec.ts src/app.module.spec.ts
```

Expected: 3 suites and 25 tests pass. The controller spec retains the degraded `503` assertion; the service spec retains database, migration, worker, outbox, and rollout readiness cases.

- [ ] **Step 2: Run backend typecheck (5 minutes).**

```powershell
npm --prefix server run typecheck
```

Expected: exit 0 with no diagnostics.

- [ ] **Step 3: Run the Nest build (5 minutes).**

```powershell
npm --prefix server run build
```

Expected: exit 0.

- [ ] **Step 4: Run live RepoWise health without reindexing (4 minutes).**

```powershell
repowise health . --file server/src/app.module.ts --format json
repowise health . --file server/src/app.module.spec.ts --format json
git diff --check
git status --short
```

Expected: no new high-severity finding; status lists only the two modifications and one deletion. Do not run `repowise update` in the lane worktree.

- [ ] **Step 5: Commit the lane (3 minutes).**

```powershell
git add -- server/src/app.module.ts server/src/app.module.spec.ts server/src/health/health.module.ts
git diff --cached --check
git commit -m "refactor(health): flatten health ownership into AppModule"
```

Expected: one focused commit and a clean lane worktree.

### Task 4: Apply coordinator-owned structural acceptance

**Files:**

- No additional file changes
- Measure the integrated main worktree after cherry-picking Lane B

**Interfaces:**

- Consumes: the Lane B commit SHA
- Produces: accepted/rejected `C1` snapshot used as the immediate predecessor of `C2`

- [ ] **Step 1: Verify the TypeScript sensor hashes (3 minutes).**

```powershell
$sentruxTsRoot = "C:\Users\Alinka\.sentrux\plugins\typescript"
$expectedSentruxTsHashes = [ordered]@{
  "plugin.toml" = "27219129BB53AFB16D2E3D407C592B2CF3F600A42F724A6EF9974FB9CA375406"
  "queries\tags.scm" = "0977EE307FBBD8E9607932763BB81446D305D37A639E7FDBA0562FC542E40BA7"
  "grammars\windows-x86_64.dll" = "37DD6AD9E4C9458CA45A3021A95F93F11C28B231DB7BCEF890D96376464BE169"
}
foreach ($relativePath in $expectedSentruxTsHashes.Keys) {
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (
    Join-Path $sentruxTsRoot $relativePath
  )).Hash
  if ($actualHash -ne $expectedSentruxTsHashes[$relativePath]) {
    throw "Unexpected TypeScript sensor hash: $relativePath = $actualHash"
  }
}
```

Expected: all three exact hashes match. Do not scan during Lane A's external query critical section.

- [ ] **Step 2: Capture the post-C1 stock server snapshot (5 minutes).**

Use a fresh stock Sentrux MCP process:

```text
mcp__sentrux__scan({"path":"C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/server"})
mcp__sentrux__health({})
```

Required against `M0`: import edges `< 3202`, cross-module edges `< 1879`, quality `>= 6386`, modularity `>= 5511`, depth `<= 13`, and cycles `0`. The expected source-edge delta is approximately `-4`, but it is not a promise.

- [ ] **Step 3: Inspect live RepoWise health without reindexing (4 minutes).**

```powershell
repowise health . --file server/src/app.module.ts --format json
repowise health . --file server/src/app.module.spec.ts --format json
```

Prove ownership from compiled behavior and live source, not from the still-stale RepoWise graph: the focused `AppModule` test must resolve `HealthController` and `HealthService`, `rg -n "HealthController|HealthService" server/src/app.module.ts` must show both direct registrations, and `Test-Path server/src/health/health.module.ts` must be false. Then call RepoWise MCP `get_change_risk` with the resolved full SHA `revspec = $integratedLaneB`, `baseline = 50`, and `extensions = [".ts"]`. Use it only for change risk and impacted-test discovery; any new unexplained high-severity finding blocks Lane B. The orchestration plan runs the single final `repowise update --index-only` and post-index ownership lookup after all accepted structural commits.

- [ ] **Step 4: Run the final structural rule check (3 minutes).**

```powershell
git diff --check
sentrux check .
git status --short --branch
```

Expected: Sentrux rules 2/2 pass. Do not report the legacy `sentrux gate .` as passing; its pre-existing god-file baseline failure is documented in the spec.

## Rollback

Before the lane commit:

```powershell
git restore --source=HEAD -- server/src/app.module.ts server/src/app.module.spec.ts server/src/health/health.module.ts
```

After integration, use the exact integrated SHA captured by the coordinator; never rediscover it by commit-message grep:

```powershell
if ([string]::IsNullOrWhiteSpace($integratedLaneB)) {
  throw "Integrated Lane B SHA was not supplied"
}
git cat-file -e "${integratedLaneB}^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Integrated Lane B commit is invalid" }
git revert --no-edit $integratedLaneB
```

Rerun the focused three-suite command and the paired structural gates. There are no migrations, persisted-format changes, environment changes, or production operations to reverse.
