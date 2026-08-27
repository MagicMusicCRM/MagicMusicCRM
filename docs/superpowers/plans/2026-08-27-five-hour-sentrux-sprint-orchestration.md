# Five-Hour Sentrux Sprint Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute, independently review, and conditionally integrate the three approved Sentrux lanes inside exactly 300 wall-clock minutes without weakening policy or touching production.

**Architecture:** The root checkout is coordinator-owned; three external sibling Git worktrees isolate Lane A, B, and C without a tracked setup commit. Implementers return scoped commits, fresh reviewers never edit their worktrees, and the coordinator cherry-picks only green lanes through sequential RepoWise, test, hash, and stock-Sentrux gates.

**Tech Stack:** Git worktrees, Codex subagents, Flutter/Dart 3.11.1, NestJS/TypeScript/Jest/PostgreSQL, RepoWise 0.42, Sentrux 0.5.7, PowerShell

**Spec:** `docs/superpowers/specs/2026-08-27-five-hour-hotspot-sprint-design.md`

**Coordinator Sub-Skill:** REQUIRED: Use superpowers:using-git-worktrees before Task 1. This plan selects the explicit sibling root `C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees`; no tracked ignore rule is needed.

## Global Constraints

- Stop at 300 minutes. Lane C, B, and A implementation hard deadlines are `3:10`, `3:20`, and `3:55`; a late or partially green lane is omitted.
- The coordinator alone owns the root checkout, baselines, cherry-picks/reverts, one final RepoWise reindex, and all acceptance snapshots. Workers own only their plan's paths.
- A reviewer reads the spec, lane plan, diff, and evidence but never edits the implementer worktree. Any unresolved Critical or Important finding omits that lane; there is no post-review correction window.
- Never modify production, databases, migrations, persisted facts, `.sentrux/baseline.json`, `.sentrux/rules.toml`, lockfiles, or another lane's paths. The mandatory PostgreSQL test uses only the configured local test database.
- Lane A has exclusive use of the installed Dart query during its mutex-protected critical section. If unrelated Sentrux processes prevent exclusivity, omit Lane A without terminating them and continue B/C.

---

## File Structure and Ownership

| Lane | Required worker plan | Branch | Worktree |
|---|---|---|---|
| A | `docs/superpowers/plans/2026-08-27-sentrux-dart-call-calibration.md` | `codex/sentrux-dart-call-calibration` | `C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-dart-call-calibration` |
| B | `docs/superpowers/plans/2026-08-27-sentrux-health-module-flattening.md` | `codex/sentrux-health-module-flattening` | `C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-health-module-flattening` |
| C | `docs/superpowers/plans/2026-08-27-sentrux-teacher-compensation-equality.md` | `codex/sentrux-teacher-compensation-equality` | `C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-teacher-compensation-equality` |

The orchestration creates no tracked setup file or commit. Every accepted source/tool change arrives through a reviewed lane commit.

## Fixed Clock

| Clock | Hard outcome |
|---|---|
| `0:00-0:20` | Clean baseline, external worktrees, fresh stock `M0` root/server snapshots, dependency/test preflight |
| `0:20-3:10` | Three workers run; interrupt and omit C at `3:10` if incomplete |
| `3:10-3:55` | Fresh C/B reviewers run; B stops at `3:20`; A stops at `3:55` |
| `3:55-4:30` | Fresh A review runs while root accepts/rejects B then C sequentially |
| `4:30-4:50` | Conditionally integrate A and prove external-byte recovery |
| `4:50-5:00` | Fresh integrated verifier, one RepoWise reindex, final rules/evidence/status |

Use absolute deadlines derived once from `$sprintStart`; do not reset the clock after setup, omission, review, or failure.

## Frozen Stock Hash Gate

Run this exact block immediately before and after every stock snapshot pair:

```powershell
$expectedStockHashes = [ordered]@{
  'C:\Users\Alinka\AppData\Local\Programs\Sentrux\sentrux.exe' = '40DD2E47804BF9F006015EB742ABFE178A824F42D4A19EB00478A7D705697CAC'
  'C:\Users\Alinka\.sentrux\plugins\dart\plugin.toml' = '7271A5F0376CE3FF3AD81B9314F2D9355405AA3D20356A84AB3A8D1C082958F1'
  'C:\Users\Alinka\.sentrux\plugins\dart\queries\tags.scm' = '3B70536E2303745FE31220DE09972F489E77543283EC95C95BCD01F62661FDDD'
  'C:\Users\Alinka\.sentrux\plugins\dart\grammars\windows-x86_64.dll' = '482C79FEC72C93A07C38F2BDC009C0B405931F206AA0C2E50FD42E224125434B'
  'C:\Users\Alinka\.sentrux\plugins\typescript\plugin.toml' = '27219129BB53AFB16D2E3D407C592B2CF3F600A42F724A6EF9974FB9CA375406'
  'C:\Users\Alinka\.sentrux\plugins\typescript\queries\tags.scm' = '0977EE307FBBD8E9607932763BB81446D305D37A639E7FDBA0562FC542E40BA7'
  'C:\Users\Alinka\.sentrux\plugins\typescript\grammars\windows-x86_64.dll' = '37DD6AD9E4C9458CA45A3021A95F93F11C28B231DB7BCEF890D96376464BE169'
}
$observedStockHashes = [ordered]@{}
foreach ($entry in $expectedStockHashes.GetEnumerator()) {
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
  if ($actual -ne $entry.Value) {
    throw "Stock sensor mismatch: $($entry.Key) = $actual"
  }
  $observedStockHashes[$entry.Key] = $actual
}
$observedStockHashes | ConvertTo-Json
```

For every pair, save both emitted maps and require exact equality. In particular, all three TypeScript artifacts are checked on both sides of `M0-server`, `C1`, `preC2`, and `postC2`.

Fresh pre-lane snapshots must reproduce these graph metrics; documentation line counts may increase without changing them:

| Snapshot | Quality | Import edges | Cross-module | Depth | Equality raw/score | Modularity raw/score | Redundancy raw/score | Cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `M0-root` | 5,817 | 5,599 | 2,957 | 13 | 0.3487530500448399 / 6,512 | 0.34285816326530605 / 5,619 | 0.522313862840357 / 4,777 | 0 |
| `M0-server` | 6,386 | 3,202 | 1,879 | 13 | 0.4525196921628077 / 5,475 | 0.32665512770945393 / 5,511 | 0.0760775238646225 / 9,239 | 0 |

---

### Task 1: Start the clock and establish isolated worktrees

**Files:** Verify the repository and create three external Git worktree registrations; do not modify tracked files.

**Produces:** clean coordinator checkout, fixed base SHA, and three isolated branches.

- [ ] **Step 1: Record the hard deadlines (2 minutes).**

```powershell
$sprintStart = Get-Date
$deadlineC = $sprintStart.AddMinutes(190)
$deadlineB = $sprintStart.AddMinutes(200)
$deadlineA = $sprintStart.AddMinutes(235)
$deadlineReviewA = $sprintStart.AddMinutes(270)
$deadlineIntegration = $sprintStart.AddMinutes(290)
$deadlineFinal = $sprintStart.AddMinutes(300)
[ordered]@{
  start = $sprintStart.ToString('o')
  C = $deadlineC.ToString('o')
  B = $deadlineB.ToString('o')
  A = $deadlineA.ToString('o')
  reviewA = $deadlineReviewA.ToString('o')
  integration = $deadlineIntegration.ToString('o')
  final = $deadlineFinal.ToString('o')
} | ConvertTo-Json
```

- [ ] **Step 2: Verify the root checkout before mutation (2 minutes).**

```powershell
git status --short --branch
git rev-parse --show-toplevel
git worktree list --porcelain
$sprintBase = (git rev-parse HEAD).Trim()
```

Expected: current branch `main`, no uncommitted files, and none of the three target branches/worktree paths already exists. Stop for owner direction instead of deleting, moving, or reusing an unexpected path.

- [ ] **Step 3: Refuse branch/path collisions (2 minutes).**

```powershell
$worktreeRoot = 'C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees'
$laneBranches = @(
  'codex/sentrux-dart-call-calibration',
  'codex/sentrux-health-module-flattening',
  'codex/sentrux-teacher-compensation-equality'
)
$lanePaths = @(
  (Join-Path $worktreeRoot 'sentrux-dart-call-calibration'),
  (Join-Path $worktreeRoot 'sentrux-health-module-flattening'),
  (Join-Path $worktreeRoot 'sentrux-teacher-compensation-equality')
)
foreach ($branch in $laneBranches) {
  git show-ref --verify --quiet "refs/heads/$branch"
  if ($LASTEXITCODE -eq 0) { throw "Lane branch already exists: $branch" }
}
foreach ($path in $lanePaths) {
  if (Test-Path -LiteralPath $path) { throw "Lane path already exists: $path" }
}
```

- [ ] **Step 4: Create all three worktrees (3 minutes).**

```powershell
if (-not (Test-Path -LiteralPath $worktreeRoot)) {
  New-Item -ItemType Directory -Path $worktreeRoot | Out-Null
}
git worktree add $lanePaths[0] -b codex/sentrux-dart-call-calibration $sprintBase
git worktree add $lanePaths[1] -b codex/sentrux-health-module-flattening $sprintBase
git worktree add $lanePaths[2] -b codex/sentrux-teacher-compensation-equality $sprintBase
git worktree list --porcelain
```

Expected: three new worktrees point to the same `$sprintBase`; the root checkout stays on `main` and clean.

### Task 2: Capture fresh stock baselines and run lane preflight

**Files:** No tracked changes.

**Produces:** fresh `M0-root`/`M0-server`, green focused test baselines, immutable production SHA, and a recorded initial process set without prematurely omitting Lane A.

- [ ] **Step 1: Record the source and dependency baseline (2 minutes).**

```powershell
$productionBaseline = 'bc7dce8aa234c0d1861e0ba6313274d6448b60b2'
git merge-base --is-ancestor $productionBaseline $sprintBase
if ($LASTEXITCODE -ne 0) { throw "Approved production baseline is not an ancestor" }
git status --short --branch
```

- [ ] **Step 2: Validate stock recovery state and record initial processes (2 minutes).**

```powershell
$initialRecoveryRoot = 'C:\Users\Alinka\AppData\Local\MagicMusicCRM\sentrux-dart-sensor-recovery'
$initialManifest = Join-Path $initialRecoveryRoot 'manifest.json'
$initialBackup = Join-Path $initialRecoveryRoot 'stock-tags.scm.bin'
if (
  (Test-Path -LiteralPath $initialManifest) -or
  (Test-Path -LiteralPath $initialBackup)
) {
  throw 'Sprint blocked: preserve and validate existing Dart sensor recovery material before any scan'
}
$initialDartQuery = 'C:\Users\Alinka\.sentrux\plugins\dart\queries\tags.scm'
$initialDartQueryHash = (
  Get-FileHash -Algorithm SHA256 -LiteralPath $initialDartQuery
).Hash
if ($initialDartQueryHash -ne '3B70536E2303745FE31220DE09972F489E77543283EC95C95BCD01F62661FDDD') {
  throw 'Sprint blocked: installed Dart query is not the approved stock artifact'
}
$initialSentrux = @(Get-Process sentrux -ErrorAction SilentlyContinue)
$initialSentrux | Select-Object Id, Path
```

Do not delete recovery material or kill these processes. A recovery/hash mismatch blocks every Sentrux-backed acceptance gate until safely resolved. Existing PIDs affect only the later live-overlay window; they do not prevent fake-backed Lane A implementation.

- [ ] **Step 3: Capture fresh stock `M0-root` and `M0-server` (5 minutes).**

Use a read-only measurement specialist before implementation starts. It must compute the seven frozen hashes before and after each pair, then run exactly:

```text
mcp__sentrux__scan({"path":"C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM"})
mcp__sentrux__health({})
mcp__sentrux__scan({"path":"C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/server"})
mcp__sentrux__health({})
```

Store the complete JSON as `M0-root` and `M0-server`; require the approved structural values, Sentrux 0.5.7, and identical before/after hashes. The specialist reports every owned Sentrux PID and requests graceful connector shutdown after returning evidence. No process is force-terminated.

- [ ] **Step 4: Restore dependencies with three specialist slots total (5 minutes wall-clock).**

Keep the read-only M0 measurement specialist in slot 1, dispatch only the Lane B and Lane C preparatory workers in slots 2 and 3, and have the root coordinator restore Lane A locally. The coordinator runs:

```powershell
Push-Location 'C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-dart-call-calibration'
try {
  flutter pub get
  git status --short
} finally {
  Pop-Location
}
```

The Lane B worker runs `npm --prefix 'C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-health-module-flattening\server' ci` and `git -C 'C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-health-module-flattening' status --short`. Lane C runs the corresponding two commands with `C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-teacher-compensation-equality`. Expected: all three statuses are empty. A lockfile diff fails preflight; restore was not dependency-neutral.

- [ ] **Step 5: Run the Lane B focused baseline in its preparatory worker (5 minutes wall-clock).**

```powershell
npm --prefix 'C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-health-module-flattening\server' test -- --runTestsByPath src/health/health.service.spec.ts src/health/health.controller.spec.ts src/app.module.spec.ts
```

Expected: 3 suites and 23 tests pass before the two new ownership tests exist.

- [ ] **Step 6: Run Lane C baselines in its preparatory worker (5 minutes wall-clock).**

```powershell
npm --prefix 'C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-teacher-compensation-equality\server' test -- --runTestsByPath src/crm/commerce/lesson-settlement.calculation.spec.ts
npm --prefix 'C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-worktrees\sentrux-teacher-compensation-equality\server' test -- --runTestsByPath src/crm/commerce/lesson-settlement-postgres.integration.spec.ts
```

Expected: both pass. If PostgreSQL is unavailable, mark Lane C omitted before implementation and use its free agent slot for review support.

Steps 4-6 run concurrently after the two initial checks with exactly three specialists besides the root coordinator: M0 measurement, Lane B preparation, and Lane C preparation. The coordinator restores Flutter dependencies and verifies Lane A itself; B and C each restore dependencies then run their own baseline. All must return by `0:20`; otherwise the affected implementation lane starts late but keeps its original absolute hard deadline.

### Task 3: Dispatch three bounded implementation workers

**Files:** Workers modify only their lane-owned worktrees.

**Produces:** at most three focused commit SHAs plus complete command evidence by the hard deadlines.

- [ ] **Step 1: Start Lane C with its exact plan (3 minutes).**

Give a fresh worker this prompt and absolute worktree path:

```text
Implement docs/superpowers/plans/2026-08-27-sentrux-teacher-compensation-equality.md in the Lane C worktree. Use test-driven-development and verification-before-completion. Own only the two files named by the plan. Do not run Sentrux or RepoWise reindex. Return one focused commit SHA, exact test/typecheck/build/RepoWise evidence, changed paths, and blockers by the absolute 3:10 deadline. If mandatory local PostgreSQL is not green, return OMIT with no acceptance claim.
```

- [ ] **Step 2: Start Lane B with its exact plan (3 minutes).**

```text
Implement docs/superpowers/plans/2026-08-27-sentrux-health-module-flattening.md in the Lane B worktree. Use test-driven-development and verification-before-completion. Own only app.module.ts, app.module.spec.ts, and deletion of health.module.ts. Do not run Sentrux or RepoWise reindex. Return one focused commit SHA, exact test/typecheck/build/RepoWise evidence, changed paths, and blockers by the absolute 3:20 deadline.
```

- [ ] **Step 3: Always start fake-backed Lane A implementation (3 minutes).**

```text
Implement docs/superpowers/plans/2026-08-27-sentrux-dart-call-calibration.md in the Lane A worktree. Use test-driven-development and verification-before-completion. Own only its eight paths. Build and verify every fake-backed parser/MCP/recovery/watchdog/lifecycle test first; do not mutate the installed query until the coordinator explicitly grants a zero-PID live-overlay window. Return one focused candidate commit SHA and live evidence only if that window becomes available. If it does not, return OMIT plus fake-backed evidence; never terminate another process. Hard deadline: 3:55.
```

- [ ] **Step 4: Enforce the C and B deadlines (2 minutes).**

At `$deadlineC`, interrupt an incomplete C worker and mark the lane omitted. At `$deadlineB`, do the same for B. Do not cherry-pick a partial commit and do not extend either deadline with Lane A's unused time.

- [ ] **Step 5: Grant or deny the live-overlay window at `3:30` (3 minutes).**

Finish all coordinator measurement calls and ask their owners to close gracefully. Then run:

```powershell
$liveWindowPids = @(Get-Process sentrux -ErrorAction SilentlyContinue)
if ($liveWindowPids.Count -eq 0) {
  $laneALiveOverlayEligible = $true
  Write-Output 'Lane A live overlay authorized until 3:55.'
} else {
  $laneALiveOverlayEligible = $false
  $liveWindowPids | Select-Object Id, Path
  Write-Output 'Lane A live overlay denied; fake-backed candidate will be omitted.'
}
```

Send the result to the Lane A worker. Do not kill a process to make the gate green.

- [ ] **Step 6: Enforce the A deadline and restoration gate (3 minutes).**

At `$deadlineA`, interrupt incomplete A. Before accepting even a completed SHA, require the stock Dart query hash, all seven pinned hashes, no recovery manifest, no lock conflict, and no application-path diff. Failure omits A and blocks every coordinator Sentrux scan until recovery is safely resolved.

### Task 4: Run independent no-edit reviews in waves

**Files:** Reviewers read only; no tracked or external mutations.

**Produces:** one PASS/OMIT verdict per completed lane, with Critical/Important findings called out.

- [ ] **Step 1: Start a fresh Lane C reviewer at `3:10` (3 minutes).**

```text
Review Lane C against the approved spec and its implementation plan. Read the commit diff and supplied test/PostgreSQL/typecheck/build/RepoWise evidence. Do not edit. Check full seven-key results, all error-precedence boundaries, half-up rounding, the exact three-helper partition, public signature/import stability, path scope, and rollback safety. Report findings as Critical, Important, or Minor with exact file/line evidence. PASS only with no unresolved Critical or Important finding; finish by 3:45.
```

- [ ] **Step 2: Start a fresh Lane B reviewer at `3:20` (3 minutes).**

```text
Review Lane B against the approved spec and its implementation plan. Read the commit diff and supplied test/typecheck/build/RepoWise evidence. Do not edit. Check direct AppModule ownership, singleton dependency resolution, unchanged controller/service behavior, deletion/reference scope, and rollback safety. Report findings as Critical, Important, or Minor with exact file/line evidence. PASS only with no unresolved Critical or Important finding; finish by 3:55.
```

- [ ] **Step 3: Start a fresh Lane A reviewer at `3:55` (3 minutes).**

```text
Review Lane A against the approved spec and its implementation plan. Read the commit diff and supplied fixture/full-repo/hash/recovery evidence. Do not edit or run a global overlay. Check strict version/hash locking, fixture attribution logic, diagnostic parsing, named-mutex watchdog, durable restore order, PID exclusion, negative limitations, immutable application scope, and rollback safety. Report findings as Critical, Important, or Minor with exact file/line evidence. PASS only with no unresolved Critical or Important finding; finish by 4:30.
```

- [ ] **Step 4: Freeze each review verdict (2 minutes).**

A PASS freezes the reviewed SHA and evidence. Any Critical/Important finding, missing mandatory evidence, scope drift, or reviewer timeout becomes OMIT. Reviewers do not fix defects, and implementers do not get a correction window.

### Task 5: Integrate and measure Lane B then Lane C

**Files:** Root checkout receives reviewed commits only; no manual source edits.

**Produces:** accepted/rejected `C1`, immediate `preC2`, accepted/rejected `postC2`, and a recoverable commit history.

- [ ] **Step 1: Capture fresh stock `M0-server` before any cherry-pick (4 minutes).**

If Lane A used its live window, first require its watchdog exit, seven stock hashes, and absence of both recovery files. A fresh measurement worker runs the Frozen Stock Hash Gate, then these literal calls, then the hash gate again:

```text
mcp__sentrux__scan({"path":"C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/server"})
mcp__sentrux__health({})
```

It returns the complete JSON as the integration-time `M0-server`. Required baseline identity:

```text
quality_signal = 6386
total_import_edges = 3202
cross_module_edges = 1879
root_causes.depth.raw = 13
root_causes.equality.raw = 0.4525196921628077
root_causes.equality.score = 5475
root_causes.modularity.score = 5511
root_causes.acyclicity.raw = 0
```

If fresh source-equivalent output differs, stop integration and diagnose sensor/source identity instead of silently replacing the approved baseline.

- [ ] **Step 2: Scope-check and cherry-pick reviewed Lane B (3 minutes).**

```powershell
git show --name-status --format=fuller $laneBCommit
$laneBPaths = @(git diff-tree --no-commit-id --name-only -r $laneBCommit)
$expectedLaneBPaths = @(
  'server/src/app.module.spec.ts',
  'server/src/app.module.ts',
  'server/src/health/health.module.ts'
)
if (@(Compare-Object $expectedLaneBPaths $laneBPaths).Count -ne 0) {
  throw 'Lane B scope mismatch'
}
git cherry-pick $laneBCommit
$integratedLaneB = (git rev-parse HEAD).Trim()
```

Skip this step when B is omitted.

- [ ] **Step 3: Re-run Lane B behavior gates (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/health/health.service.spec.ts src/health/health.controller.spec.ts src/app.module.spec.ts
npm --prefix server run typecheck
npm --prefix server run build
```

Expected: 3 suites/25 tests, typecheck, and build pass. On failure, revert the cherry-picked commit and mark B omitted.

Call RepoWise MCP `get_change_risk` with the resolved full SHA `revspec = $integratedLaneB`, `baseline = 50`, and `extensions = [".ts"]`; store its parsed `result` as `$changeRisk` and apply the exact nested-schema/timeout policy in Task 6 Step 3. This is Lane B's per-commit gate, distinct from the later combined-range gate. Any block reverts `$integratedLaneB` and omits B.

- [ ] **Step 4: Capture and apply the `C1` structural predicates (5 minutes).**

Use a fresh measurement worker. Run the Frozen Stock Hash Gate, the literal server `scan -> health` calls from Step 1, and the hash gate again. Preserve the complete JSON as `C1`. Accept B only when:

```text
C1.total_import_edges < 3202
C1.cross_module_edges < 1879
C1.quality_signal >= 6386
C1.root_causes.modularity.score >= 5511
C1.root_causes.depth.raw <= 13
C1.root_causes.acyclicity.raw == 0
```

If any predicate fails, `git revert --no-edit $integratedLaneB`, rerun the focused tests, and use a fresh stock snapshot to prove return to `M0-server`.

- [ ] **Step 5: Capture immediate `preC2` and cherry-pick reviewed Lane C (4 minutes).**

Ask a fresh measurement worker to run the Frozen Stock Hash Gate, the literal server `scan -> health` pair, and the hash gate again immediately before C2; preserve the complete JSON and both hash maps as `preC2`. Then scope-check exactly the two Lane C paths and cherry-pick:

```powershell
$laneCPaths = @(git diff-tree --no-commit-id --name-only -r $laneCCommit)
$expectedLaneCPaths = @(
  'server/src/crm/commerce/lesson-settlement.calculation.spec.ts',
  'server/src/crm/commerce/lesson-settlement.calculation.ts'
)
if (@(Compare-Object $expectedLaneCPaths $laneCPaths).Count -ne 0) {
  throw 'Lane C scope mismatch'
}
git cherry-pick $laneCCommit
$integratedLaneC = (git rev-parse HEAD).Trim()
```

Skip the cherry-pick when C is omitted; `preC2` remains evidence only.

- [ ] **Step 6: Re-run all Lane C gates on the integrated tree (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/lesson-settlement.calculation.spec.ts src/crm/commerce/lesson-settlement-catalog.spec.ts src/crm/commerce/lesson-settlement-execution.spec.ts src/crm/commerce/lesson-settlement-plan.persistence.spec.ts src/crm/commerce/lesson-settlement-postgres.integration.spec.ts
npm --prefix server run typecheck
npm --prefix server run build
```

Any failure reverts C and marks it omitted.

Call RepoWise MCP `get_change_risk` with the resolved full SHA `revspec = $integratedLaneC`, `baseline = 50`, and `extensions = [".ts"]`; store its parsed `result` as `$changeRisk` and apply the exact nested-schema/timeout policy in Task 6 Step 3. This executes Lane C plan Task 5 on the integrated SHA and is distinct from the combined-range gate. Any block reverts `$integratedLaneC` and omits C.

- [ ] **Step 7: Capture `postC2` and apply exact equality predicates (5 minutes).**

With a new stock measurement worker, run the Frozen Stock Hash Gate, the literal server `scan -> health` pair, and the hash gate again; preserve this as `postC2`. Accept only when:

```text
postC2.root_causes.equality.score > preC2.root_causes.equality.score
postC2.root_causes.equality.raw < preC2.root_causes.equality.raw
postC2.root_causes.equality.score > 5475
postC2.root_causes.equality.raw < 0.4525196921628077
postC2.quality_signal >= preC2.quality_signal
postC2.total_import_edges <= preC2.total_import_edges
postC2.cross_module_edges <= preC2.cross_module_edges
postC2.root_causes.depth.raw <= preC2.root_causes.depth.raw
postC2.root_causes.acyclicity.raw == 0
```

On failure, run `git revert --no-edit $integratedLaneC`, rerun C's integrated suites, and prove the server snapshot returns to `preC2`.

### Task 6: Conditionally integrate Lane A and run the final verifier

**Files:** Root receives the reviewed Lane A commit only; final tools may update ignored RepoWise state.

**Produces:** clean integrated candidate, accepted lane SHAs, one final RepoWise index, stock root/server evidence, and rules 2/2.

- [ ] **Step 1: Scope-check and cherry-pick accepted Lane A by `4:30` (3 minutes).**

Require reviewer PASS, live fixture evidence, seven stock hashes, and absent recovery files. Finish all B/C measurement calls and request graceful closure of their owned MCP processes. Then evaluate the integration window:

```powershell
$laneAIntegrationPids = @(Get-Process sentrux -ErrorAction SilentlyContinue)
if ($laneAIntegrationPids.Count -gt 0) {
  $laneAIntegrationPids | Select-Object Id, Path
  $laneAIntegrationEligible = $false
  Write-Output 'Lane A omitted: no zero-PID integration window.'
} else {
  $laneAIntegrationEligible = $true
}
```

When `$laneAIntegrationEligible` is false, skip the remainder of Steps 1-2. Otherwise run:

```powershell
$laneAPaths = @(git diff-tree --no-commit-id --name-only -r $laneACommit)
$expectedLaneAPaths = @(
  'test/architecture/sentrux_dart_sensor_test.dart',
  'tool/calibrate_sentrux_dart.dart',
  'tool/sentrux/dart/fixtures/lib/main.dart.fixture',
  'tool/sentrux/dart/fixtures/lib/probe.dart.fixture',
  'tool/sentrux/dart/fixtures/pubspec.yaml.fixture',
  'tool/sentrux/dart/queries/tags.scm',
  'tool/sentrux/dart/sensor-lock.json',
  'tool/src/sentrux_dart_sensor.dart'
)
if (@(Compare-Object $expectedLaneAPaths $laneAPaths).Count -ne 0) {
  throw 'Lane A scope mismatch'
}
git cherry-pick $laneACommit
$integratedLaneA = (git rev-parse HEAD).Trim()
```

If any condition is missing, omit A; B/C acceptance does not depend on it.

- [ ] **Step 2: Re-run Lane A acceptance on the integrated tree (5 minutes).**

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart
$laneALocalGateFailed = $LASTEXITCODE -ne 0
if (-not $laneALocalGateFailed) {
  dart analyze tool
  $laneALocalGateFailed = $LASTEXITCODE -ne 0
}
if ($laneALocalGateFailed) {
  git revert --no-edit $integratedLaneA
  if ($LASTEXITCODE -ne 0) { throw 'Failed to revert rejected Lane A' }
  $integratedLaneA = $null
  $laneAIntegrationEligible = $false
  Write-Output 'Lane A OMIT: integrated test/analyze gate failed safely'
} else {
  $integratedFixtureJson = & dart run tool/calibrate_sentrux_dart.dart --fixture-only
  $integratedFixtureExit = $LASTEXITCODE
  $laneARecoveryRoot = 'C:\Users\Alinka\AppData\Local\MagicMusicCRM\sentrux-dart-sensor-recovery'
  $laneARecoveryPresent =
    (Test-Path -LiteralPath (Join-Path $laneARecoveryRoot 'manifest.json')) -or
    (Test-Path -LiteralPath (Join-Path $laneARecoveryRoot 'stock-tags.scm.bin'))
  $laneAHashMismatch = $false
  foreach ($entry in $expectedStockHashes.GetEnumerator()) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    if ($actual -ne $entry.Value) { $laneAHashMismatch = $true }
  }
  $laneAMutexUnavailable = $false
  $createdMutex = $false
  $mutexProbe = [System.Threading.Mutex]::new(
    $true,
    'Local\MagicMusicCRM.SentruxDartSensor.v0_5_7',
    [ref]$createdMutex
  )
  try {
    if (-not $createdMutex) {
      $laneAMutexUnavailable = $true
    } else {
      $mutexProbe.ReleaseMutex()
    }
  } finally {
    $mutexProbe.Dispose()
  }
  if ($laneARecoveryPresent -or $laneAHashMismatch -or $laneAMutexUnavailable) {
    throw 'Lane A unsafe: stop all Sentrux work and preserve recovery evidence'
  }
  if ($integratedFixtureExit -ne 0) {
    git revert --no-edit $integratedLaneA
    if ($LASTEXITCODE -ne 0) { throw 'Failed to revert safely rejected Lane A' }
    $integratedLaneA = $null
    $laneAIntegrationEligible = $false
    Write-Output 'Lane A OMIT: integrated live calibration failed safely'
  } else {
    $integratedFixtureEvidence = $integratedFixtureJson | ConvertFrom-Json
    if (
      [bool]$integratedFixtureEvidence.recovery_material_present -or
      [bool]$integratedFixtureEvidence.unrelated_sentrux_observed -or
      -not [bool]$integratedFixtureEvidence.watchdog_exited_normally
    ) {
      throw 'Lane A returned inconsistent success evidence'
    }
  }
}
if (-not [string]::IsNullOrWhiteSpace($integratedLaneA)) {
  $laneAChangedPaths = @(git diff-tree --no-commit-id --name-only -r $laneACommit)
  $laneAForbiddenPaths = @($laneAChangedPaths | Where-Object {
    $_ -like 'lib/*' -or
    $_ -like 'server/src/*' -or
    $_ -eq '.sentrux/rules.toml' -or
    $_ -eq '.sentrux/baseline.json' -or
    $_ -eq 'pubspec.yaml' -or
    $_ -eq 'pubspec.lock'
  })
  if ($laneAForbiddenPaths.Count -gt 0) {
    $laneAForbiddenPaths
    throw 'Lane A changed a forbidden application or policy path'
  }
}
```

The immutable-source predicate applies to Lane A's commit, not accepted B/C production changes. A nonzero live exit branches immediately: safe stock/recovery/mutex state causes a recoverable revert and omission; any unsafe state throws before RepoWise or another Sentrux command. Never waive live acceptance.

- [ ] **Step 3: Reindex RepoWise exactly once after structural integration (4 minutes).**

```powershell
repowise update --index-only
repowise health . --file server/src/app.module.ts --format json
repowise health . --file server/src/crm/commerce/lesson-settlement.calculation.ts --format json
```

Run RepoWise `get_change_risk` on `$sprintBase..HEAD` and classify its missing/impacted-test output by the fail-closed policy below; a new unexplained high-severity finding blocks final acceptance.
Use the exact arguments `revspec = "$sprintBase..HEAD"`, `baseline = 50`, and `extensions = [".ts", ".dart"]`.
After the one reindex, make this exact RepoWise call:

```text
mcp__repowise__get_context({"targets":["server/src/app.module.ts","server/src/health/health.module.ts"],"include":["skeleton"]})
```

Require the `app.module.ts` skeleton to contain the direct `HealthController`/`HealthService` registrations and `server/src/health/health.module.ts` to appear in `unresolved`. This graph lookup corroborates the already-green compiled ownership test and live-source checks; it does not replace them.

Apply impacted-test output fail closed with the parsed MCP `result` in `$changeRisk`. The policy derives whether an integrated Dart lane exists, so the Lane B/C per-commit calls remain backend-only while the final combined `no_map` fallback includes Flutter when needed.

```powershell
function Invoke-BeforeSprintDeadline {
  param(
    [Parameter(Mandatory)] [string] $FilePath,
    [Parameter(Mandatory)] [string[]] $ArgumentList
  )
  $remainingMilliseconds = [int][Math]::Floor(
    ($deadlineFinal - (Get-Date)).TotalMilliseconds
  )
  if ($remainingMilliseconds -le 0) {
    throw "No sprint time remains for $FilePath"
  }
  $ownedProcess = Start-Process `
    -FilePath $FilePath `
    -ArgumentList $ArgumentList `
    -PassThru `
    -NoNewWindow
  if (-not $ownedProcess.WaitForExit($remainingMilliseconds)) {
    try {
      $ownedProcess.Kill($true)
    } catch {
      Stop-Process -Id $ownedProcess.Id -Force -ErrorAction SilentlyContinue
    }
    throw "Owned command exceeded the five-hour deadline: $FilePath"
  }
  if ($ownedProcess.ExitCode -ne 0) {
    throw "Command failed with exit $($ownedProcess.ExitCode): $FilePath"
  }
}

$npmCommand = (Get-Command npm.cmd -ErrorAction Stop).Source
$flutterCommand = (Get-Command flutter.bat -ErrorAction Stop).Source
$runDartFallback = $false
$integratedLaneAVariable = Get-Variable integratedLaneA -ErrorAction SilentlyContinue
if ($null -ne $integratedLaneAVariable) {
  $runDartFallback = -not [string]::IsNullOrWhiteSpace(
    [string]$integratedLaneAVariable.Value
  )
}
$riskProperties = @($changeRisk.PSObject.Properties.Name)
if ('impacted_tests' -notin $riskProperties) {
  throw 'RepoWise omitted impacted_tests'
}
$impact = $changeRisk.impacted_tests
$impactProperties = @($impact.PSObject.Properties.Name)
$requiredImpactProperties = @(
  'status', 'map_present', 'tests', 'total', 'truncated', 'missing_tests'
)
if (@($requiredImpactProperties | Where-Object {
  $_ -notin $impactProperties
}).Count -gt 0) {
  throw 'RepoWise impacted_tests has an unknown shape'
}
if ([bool]$impact.truncated) {
  throw 'RepoWise impacted-test list was truncated'
}
$mappedTests = @($impact.tests)
if (@($mappedTests | Where-Object { $_ -isnot [string] }).Count -gt 0) {
  throw 'RepoWise returned a non-string impacted test'
}
$missingProperties = @($impact.missing_tests.PSObject.Properties.Name)
$requiredMissingProperties = @(
  'untested_changes', 'stale_test_candidates', 'covered', 'no_coverage_data'
)
if (@($requiredMissingProperties | Where-Object {
  $_ -notin $missingProperties
}).Count -gt 0) {
  throw 'RepoWise missing_tests has an unknown shape'
}
$impactStatus = [string]$impact.status
if ($impactStatus -eq 'no_map') {
  if ([bool]$impact.map_present -or $mappedTests.Count -ne 0 -or [int]$impact.total -ne 0) {
    throw 'RepoWise no_map payload is internally inconsistent'
  }
  Invoke-BeforeSprintDeadline $npmCommand @(
    '--prefix', 'server', 'test', '--', '--runInBand'
  )
  if ($runDartFallback) {
    Invoke-BeforeSprintDeadline $flutterCommand @('test')
  }
} elseif ($impactStatus -eq 'map_present') {
  if (-not [bool]$impact.map_present) {
    throw 'RepoWise map_present status has no coverage map'
  }
  $blockingUntested = @($impact.missing_tests.untested_changes)
  $blockingStale = @($impact.missing_tests.stale_test_candidates)
  $invalidNoCoverage = @($impact.missing_tests.no_coverage_data |
    Where-Object { $_ -isnot [string] })
  $blockingNoCoverage = @($impact.missing_tests.no_coverage_data |
    Where-Object {
      $_ -is [string] -and
      $_ -notmatch '^server/.+\.spec\.ts$' -and
      $_ -notmatch '^test/.+\.dart$'
    })
  if (
    $blockingUntested.Count -gt 0 -or
    $blockingStale.Count -gt 0 -or
    $invalidNoCoverage.Count -gt 0 -or
    $blockingNoCoverage.Count -gt 0
  ) {
    $impact.missing_tests | ConvertTo-Json -Depth 20
    throw 'RepoWise reported uncovered or stale production changes'
  }
  if ([int]$impact.total -ne $mappedTests.Count) {
    throw 'RepoWise impacted-test total does not match its test list'
  }
  $unknownTests = @($mappedTests | Where-Object {
    $_ -notmatch '^server/.+\.spec\.ts$' -and $_ -notmatch '^test/.+\.dart$'
  })
  $missingMappedFiles = @($mappedTests | Where-Object {
    -not (Test-Path -LiteralPath $_ -PathType Leaf)
  })
  if ($unknownTests.Count -gt 0 -or $missingMappedFiles.Count -gt 0) {
    throw 'RepoWise returned an unknown or missing impacted-test path'
  }
  $serverTests = @($mappedTests | Where-Object { $_ -like 'server/*' } |
    ForEach-Object { $_.Substring('server/'.Length) })
  $dartTests = @($mappedTests | Where-Object { $_ -like 'test/*' })
  if ($serverTests.Count -gt 0) {
    $serverArguments = @(
      '--prefix', 'server', 'test', '--', '--runTestsByPath'
    ) + $serverTests
    Invoke-BeforeSprintDeadline $npmCommand $serverArguments
  }
  if ($dartTests.Count -gt 0) {
    $dartArguments = @('test') + $dartTests
    Invoke-BeforeSprintDeadline $flutterCommand $dartArguments
  }
} elseif ($impactStatus -eq 'no_source_line_changes') {
  $unexpectedMissing = @(
    @($impact.missing_tests.untested_changes) +
    @($impact.missing_tests.stale_test_candidates) +
    @($impact.missing_tests.covered) +
    @($impact.missing_tests.no_coverage_data)
  )
  if (
    [bool]$impact.map_present -or
    $mappedTests.Count -ne 0 -or
    [int]$impact.total -ne 0 -or
    $unexpectedMissing.Count -ne 0
  ) {
    throw 'RepoWise no-source-change payload is internally inconsistent'
  }
} else {
  throw "Unknown RepoWise impacted_tests.status: $impactStatus"
}
if ((Get-Date) -gt $deadlineFinal) {
  throw 'Impacted tests did not finish inside the five-hour deadline'
}
```

`untested_changes`, `stale_test_candidates`, and production paths in `no_coverage_data` are blocking for `map_present`; `covered` and changed test files in `no_coverage_data` are informational. These tests are additional to Step 4's mandatory combined suite. Any missing field, truncated list, unknown path/extension/status, missing file, nonzero command, or timeout rejects the candidate. Only process IDs created by `Invoke-BeforeSprintDeadline` may be terminated.

- [ ] **Step 4: Run integrated tests, build, and Sentrux rules (5 minutes).**

Run the complete combined suite regardless of omissions; baseline behavior must remain green when a lane is absent:

```powershell
$combinedServerTests = @(
  'src/health/health.service.spec.ts',
  'src/health/health.controller.spec.ts',
  'src/app.module.spec.ts',
  'src/crm/commerce/lesson-settlement.calculation.spec.ts',
  'src/crm/commerce/lesson-settlement-catalog.spec.ts',
  'src/crm/commerce/lesson-settlement-execution.spec.ts',
  'src/crm/commerce/lesson-settlement-plan.persistence.spec.ts',
  'src/crm/commerce/lesson-settlement-postgres.integration.spec.ts'
)
$combinedArguments = @(
  '--prefix', 'server', 'test', '--', '--runTestsByPath'
) + $combinedServerTests
Invoke-BeforeSprintDeadline $npmCommand $combinedArguments
if (Test-Path -LiteralPath 'test/architecture/sentrux_dart_sensor_test.dart') {
  Invoke-BeforeSprintDeadline $flutterCommand @(
    'test', 'test/architecture/sentrux_dart_sensor_test.dart'
  )
  $dartCommand = (Get-Command dart.bat -ErrorAction Stop).Source
  Invoke-BeforeSprintDeadline $dartCommand @('analyze', 'tool')
}
Invoke-BeforeSprintDeadline $npmCommand @('--prefix', 'server', 'run', 'typecheck')
Invoke-BeforeSprintDeadline $npmCommand @('--prefix', 'server', 'run', 'build')
$gitCommand = (Get-Command git.exe -ErrorAction Stop).Source
$sentruxCommand = (Get-Command sentrux.exe -ErrorAction Stop).Source
Invoke-BeforeSprintDeadline $gitCommand @('diff', '--check')
Invoke-BeforeSprintDeadline $sentruxCommand @('check', '.')
```

Expected: all accepted-lane tests pass, compiler/build exit 0, and Sentrux rules are 2/2. Do not run or report the legacy `sentrux gate .` as an acceptance gate.

- [ ] **Step 5: Start specialist 10 for read-only final verification at `4:50` (3 minutes).**

```text
Verify the integrated five-hour Sentrux candidate read-only. Compare accepted SHAs and changed paths to the approved spec; inspect test/build/RepoWise/Sentrux evidence; verify all seven stock hashes, neither recovery file, availability of the named mutex, rules 2/2, no policy/baseline/lockfile drift, and no unexplained dirty files. Recompute no staged Dart metric. Return PASS or the first blocking discrepancy with exact evidence before 5:00. Do not edit or revert.
```

- [ ] **Step 6: Capture final stock metrics and clean status before `5:00` (5 minutes).**

Run the Frozen Stock Hash Gate, ask a fresh measurement worker to run exactly the calls below, then run the hash gate again:

```text
mcp__sentrux__scan({"path":"C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM"})
mcp__sentrux__health({})
mcp__sentrux__check_rules({})
mcp__sentrux__scan({"path":"C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/server"})
mcp__sentrux__health({})
```

Report final root beside M0 with the Dart caveat, never as proof that M1 repaired equality. Then run:

```powershell
$finalRecoveryRoot = 'C:\Users\Alinka\AppData\Local\MagicMusicCRM\sentrux-dart-sensor-recovery'
if (
  (Test-Path -LiteralPath (Join-Path $finalRecoveryRoot 'manifest.json')) -or
  (Test-Path -LiteralPath (Join-Path $finalRecoveryRoot 'stock-tags.scm.bin'))
) {
  throw 'Dart sensor recovery material remains at final handoff'
}
$createdMutex = $false
$mutexProbe = [System.Threading.Mutex]::new(
  $true,
  'Local\MagicMusicCRM.SentruxDartSensor.v0_5_7',
  [ref]$createdMutex
)
try {
  if (-not $createdMutex) { throw 'Dart sensor mutex remains owned' }
  $mutexProbe.ReleaseMutex()
} finally {
  $mutexProbe.Dispose()
}
git status --short --branch
git log --oneline --decorate $sprintBase..HEAD
git diff --exit-code $sprintBase -- .sentrux/rules.toml .sentrux/baseline.json pubspec.yaml pubspec.lock
```

Expected: clean tree; the log explicitly labels accepted lane commits and any rejected-commit/revert pair; protected files are unchanged, both recovery files are absent, the mutex probe succeeds, the final verifier reports PASS, and the current time is no later than `$deadlineFinal`.

## Rollback and Omission Rules

| Condition | Action |
|---|---|
| Worker deadline, mandatory test, or review fails | Omit that lane; never cherry-pick its partial state |
| Integrated test or metric predicate fails | Revert the corresponding captured `$integratedLaneA`, `$integratedLaneB`, or `$integratedLaneC`; rerun its focused gate and remeasure the predecessor |
| Lane A hash/recovery/process gate fails | Stop Sentrux work, preserve recovery evidence, restore only from verified stock bytes, omit A |
| Final verifier finds policy/lockfile/scope drift | Reject candidate until the exact commit is identified and recoverably reverted |
| Five-hour deadline arrives | Stop; report only already integrated and independently verified lanes |

Worktree cleanup is not part of the five-hour candidate and must not run automatically. Removing worktrees or branches is a separate owner-approved, recoverable housekeeping action after handoff.
