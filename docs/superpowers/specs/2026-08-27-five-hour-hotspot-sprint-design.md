# Five-Hour Sentrux-First Architecture Sprint Design

**Date:** 2026-08-27<br>
**Status:** Approved by owner in chat; implementation plans independently reviewed and ready for execution<br>
**Production-code baseline:** `bc7dce8aa234c0d1861e0ba6313274d6448b60b2`<br>
**Pre-pivot documentation commit:** `52f720ca`<br>
**Execution budget:** 300 minutes of wall-clock time from implementation start

## Decision

The previously approved payment/token/schedule hotspot sprint is superseded by
this Sentrux-first design. Its three candidates remain valid backlog items, but
they are not implementation scope for this five-hour window.

The sprint will run three independent lanes in parallel:

1. calibrate Dart call attribution without treating the sensor delta as a code
   improvement;
2. remove the redundant NestJS `HealthModule` wrapper and its dependency edges;
3. reduce one TypeScript complexity outlier that Sentrux can measure correctly.

This sprint does **not** promise a root Sentrux score of 8,000-9,000. The current
root aggregate mixes valid TypeScript measurements with invalid Dart function
body measurements. The five-hour outcome is a trustworthy direction of travel,
with one bounded sensor correction and two genuine server-side cuts as the
acceptance targets.

## Baseline

All values use one production-code baseline; root lines include this design but
do not alter the code graph. Quality uses the CLI's 0-10,000 scale.

| Scope | Files | Lines | Edges | Cross-module | Quality | Depth | Equality | Modularity | Redundancy | Cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Repository root | 2,682 | 546,090 | 5,599 | 2,957 | 5,817 | 13 / 3,810 | 0.348753 / 6,512 | 0.342858 / 5,619 | 0.522314 / 4,777 | 0 / 10,000 |
| `server` | 1,057 | 197,780 | 3,202 | 1,879 | 6,386 | 13 / 3,810 | 0.452520 / 5,475 | 0.326655 / 5,511 | 0.076078 / 9,239 | 0 / 10,000 |
| Flutter `lib` | 422 | 116,230 | 1,347 | 924 | 2,853 | 13 / 3,810 | 0.000000 / 10,000 | 0.244690 / 4,965 | 1.000000 / 0 | 0 / 10,000 |

The Flutter equality and redundancy extremes are analyzer artifacts. Sentrux
0.5.7's installed Dart query captures `function_signature` as the whole
function definition. The core then computes hashes, spans and cyclomatic
complexity from that signature-only capture. Function bodies are absent, so
captured functions tend toward complexity 1, distinct bodies with an identical
signature can look duplicated, and the Dart-only equality score becomes a false
perfect 10,000.

The installed query also recognizes constructor calls through `new_expression`
but omits ordinary direct, instance, static, null-aware and cascade invocations.
That under-attributes live calls and contaminates dead-function and redundancy
signals.

RepoWise remains the independent code-health guard: weighted health is 7.25/10,
code-only weighted health is 6.92/10, and the weighted gap to 8.0 is 9.31% of
the maximum weighted target area. RepoWise and Sentrux use different models;
their scores are not added, averaged or converted into one another.

## Measurement Protocol

| Label | Meaning | What may be claimed |
|---|---|---|
| `M0` | Stock Sentrux 0.5.7 and stock installed plugins | Reproducible baseline above |
| `M1` | Same source scanned with the staged Dart call-query overlay | Call-attribution calibration only |
| `C1`, `C2` | Accepted backend cuts scanned with the stock restored toolchain | Genuine server code deltas |
| `M2` | Future paired Dart signature/body support in Sentrux core | Required before root equality, redundancy or quality becomes a hard target |

The implementation must never compare `M0` and `M1` as though the difference
were architecture gain. Backend code candidates are compared against the
unchanged server baseline of 6,386. Root scans remain visible, but root equality,
redundancy and aggregate quality are informational until `M2` exists.

The current `.sentrux/baseline.json` and `.sentrux/rules.toml` are not updated in
this sprint. A lower threshold, excluded source tree, renamed test tree, hidden
fixture or filtered language is not an accepted improvement.

The legacy `sentrux gate .` is not a pass/fail gate for this candidate. It
already exits 1 at `M0`: quality improves from 4,734 to 5,817 and cycles fall
from 1 to 0, but the old baseline reports god files increasing from 33 to 35.
Neither backend cut owns those two root findings. Acceptance therefore uses
paired live snapshots and `sentrux check`; resolving or replacing the historical
baseline requires a separate owner decision.

The gate's `God files` counter is a Sentrux heuristic and is not the RepoWise
formal god-file classification discussed separately with the owner.

## Approaches Considered

### Selected: sensor-first plus two measurable backend cuts

This is the only approach that separates measurement repair from code repair,
fits three parallel lanes, and leaves two changes whose effects can be evaluated
under the unchanged TypeScript sensor.

### Rejected: execute the old Variant A unchanged

The payment, preview-token and schedule cuts improve RepoWise hotspots, but the
five-hour candidate would not address the unreliable Dart Sentrux measurements
and could report a misleading root score.

### Deferred: complete Dart definition repair inside this sprint

The Dart grammar exposes signatures and bodies as siblings rather than one full
declaration node. A correct fix needs Sentrux core support for paired captures,
combined spans, signature metadata and body-based hashes/complexity. Estimated
additional work is 120-180 minutes after call calibration, plus custom-binary
verification. Combining that with the 215-minute call lane exceeds its five-hour
critical path.

## Frozen Contracts

- Production remains one `Flutter -> NestJS -> PostgreSQL` runtime; there is no
  deployment, production mutation, schema change or data cleanup.
- Backend routes, DTOs, RBAC/resource scope, readiness semantics, worker
  singleton ownership, transactions, idempotency, audit and outbox stay intact.
- Teacher compensation preserves all results, error codes and error precedence;
  no money or lesson fact is rewritten.
- Sentrux rules, baselines, source inclusion and installed plugin bytes are
  restored exactly; metric gaming is forbidden.
- RepoWise, live source and focused tests remain independent acceptance gates;
  Sentrux does not replace them.

## Lane A: Dart Call-Attribution Calibration (`M1`)

### Purpose

Establish a reproducible, repo-owned experiment that proves whether a staged
Dart query improves call attribution. This lane does not modify application
production code and does not claim to repair Dart equality, body hashing,
function NLOC or aggregate redundancy.

### Owned Files

| Path | Responsibility |
|---|---|
| `tool/sentrux/dart/sensor-lock.json` | Pin Sentrux plus Dart/TypeScript sensor identities |
| `tool/sentrux/dart/queries/tags.scm` | Staged call-attribution query |
| `tool/sentrux/dart/fixtures/pubspec.yaml.fixture` | Minimal temporary Dart package |
| `tool/sentrux/dart/fixtures/lib/main.dart.fixture` | Live call sites |
| `tool/sentrux/dart/fixtures/lib/probe.dart.fixture` | Called, dead and duplicate-signature probes |
| `tool/src/sentrux_dart_sensor.dart` | Hash checks, process lifecycle, backup/restore and scan parser |
| `tool/calibrate_sentrux_dart.dart` | Human-facing fixture/full-repository runner |
| `test/architecture/sentrux_dart_sensor_test.dart` | Fail-closed lifecycle and evidence tests |

The lock records Sentrux `0.5.7` and these SHA-256 identities:

| Artifact | SHA-256 |
|---|---|
| `sentrux.exe` | `40DD2E47804BF9F006015EB742ABFE178A824F42D4A19EB00478A7D705697CAC` |
| Dart `plugin.toml` | `7271A5F0376CE3FF3AD81B9314F2D9355405AA3D20356A84AB3A8D1C082958F1` |
| Stock Dart `queries/tags.scm` | `3B70536E2303745FE31220DE09972F489E77543283EC95C95BCD01F62661FDDD` |
| Dart grammar DLL | `482C79FEC72C93A07C38F2BDC009C0B405931F206AA0C2E50FD42E224125434B` |
| TypeScript `plugin.toml` | `27219129BB53AFB16D2E3D407C592B2CF3F600A42F724A6EF9974FB9CA375406` |
| TypeScript `queries/tags.scm` | `0977EE307FBBD8E9607932763BB81446D305D37A639E7FDBA0562FC542E40BA7` |
| TypeScript grammar DLL | `37DD6AD9E4C9458CA45A3021A95F93F11C28B231DB7BCEF890D96376464BE169` |

### Process Boundary

Sentrux 0.5.7 has no per-repository plugin override. Its startup synchronizes
plugins into `%USERPROFILE%/.sentrux/plugins` and can overwrite a manual edit.
The runner therefore owns this exact lifecycle:

```text
validate pinned stock hashes
  -> create isolated fixture directories
  -> scan fixtures once with a fresh stock MCP process
  -> start a second fresh MCP process and wait for plugin synchronization
  -> backup then atomically overlay only Dart queries/tags.scm
  -> perform the first scan so that process caches the staged query
  -> restore the original bytes immediately
  -> use the same process for patched fixture and optional full-repo scans
  -> terminate process and verify the original SHA-256 again
```

The external critical-section owner is the literal installed file
`C:\Users\Alinka\.sentrux\plugins\dart\queries\tags.scm`. Before mutation, the
runner acquires `Local\MagicMusicCRM.SentruxDartSensor.v0_5_7`, verifies that no
unrelated `sentrux.exe` process is active, and starts a watcher that aborts and
restores if a new unrelated Sentrux process appears. Coordinator Sentrux scans
are paused for this short overlay/cache/restore window.

Before overlay, the runner writes an original-byte backup and durable recovery
manifest under the validated local-app-data root
`C:\Users\Alinka\AppData\Local\MagicMusicCRM\sentrux-dart-sensor-recovery`.
The manifest names the absolute target, backup, original/staged hashes and owner
PID. A separate watchdog restores from it if the parent exits unexpectedly.
Every new runner invocation performs stale-manifest recovery before any scan.
Backup, overlay, normal restore and final verification also run under
`try/finally`.

The runner aborts before mutation on any version/hash/process mismatch. A caught
failure must restore immediately; an abrupt machine/process termination leaves
the durable recovery material for watchdog or next-start recovery. The final
sprint gate refuses acceptance while a recovery manifest exists, while the
installed query hash differs, or while an unrelated Sentrux process observed the
critical section.

### Query and Fixture Boundary

The staged query retains definition and import captures and replaces only the
call block. It narrowly captures adjacent invocation shapes:

| Dart form | Tree-sitter shape used for `@call.name` |
|---|---|
| `foo()` / `foo<T>()` | `identifier` followed by `selector(argument_part)` |
| `obj.foo()` / `Type.foo()` / chained calls | assignable-selector identifier followed by `selector(argument_part)` |
| `obj?.foo()` | conditional-assignable-selector identifier followed by `selector(argument_part)` |
| `obj..foo()` / later cascade calls | cascade selector/assignable selector followed by `argument_part` |
| `new Type()` / `const Type()` | `new_expression` or `const_object_expression` with arguments |

Adjacency predicates prevent the receiver identifier from becoming the call
target. Each supported form lives in an isolated fixture variant with one
uniquely named resolvable target. The observer parses the version-locked MCP
process `build_graphs` diagnostic with an anchored parser for its resolved
`<n> call` edge count and combines that count with structured `health` output.
Missing or multiply matched diagnostics fail closed. The harness does not
pretend that public Sentrux 0.5.7 exposes individual call names.

Tear-offs, reflective calls, indexed/parenthesized result invocation,
null-asserted callable invocation, property access, operators and dot shorthand
remain explicit limitations. A callable local such as `callback()` can be
captured syntactically but may remain unresolved; `Type.named()` is
indistinguishable from a static call without explicit `new`/`const` and is
attributed to `named`.

The fixture keeps an intentionally uncalled private top-level function and two
functions with the same `build(BuildContext)` signature but different bodies.
The duplicate-signature case must remain a documented known failure after `M1`;
making it appear fixed would conceal the signature-only definition defect.

### Acceptance

- The staged plugin validates; each one-call fixture increases the resolved
  call-edge count by exactly its expected delta, and negative fixtures do not.
- The top-level all-live fixture improves controlled dead attribution; adding
  one uncalled private function strictly worsens controlled `redundancy.raw`.
- The duplicate-signature known failure remains reproduced and Dart-only
  equality remains classified invalid.
- Installed plugin bytes match all seven pinned hashes after every completed run;
  application source and `.sentrux` policy files are unchanged.
- Full-repository `M1` is diagnostic only; no root aggregate increase is
  required, and no recovery manifest or global sensor lock remains at handoff.

## Lane B: Remove the Redundant Health Module Wrapper (`C1`)

### Current Structure

`AppModule` imports `HealthModule`; that module imports `DatabaseModule`,
`CrmModule` and `PlatformModule` solely to expose one controller and one service.
`AppModule` already imports all three dependency owners. They export every
dependency of `HealthService`: `DatabaseService`, `LessonCompletionWorker`,
`V4DomainFlagsService` and `PlatformOutboxWorker`.

The current maximum backend path through health is:

```text
app.module.spec -> AppModule -> HealthModule -> CrmModule -> AuthModule
  -> AuthController -> AuthService -> AuthLoginService
  -> AuthEmailChallengeService -> NotificationsService
  -> NotificationWorker -> AuditService -> platform-integrity -> redact
```

Removing this wrapper removes a real module layer and approximately four source
import edges. Another depth-13 route remains through `MessengerModule`, so this
lane must not claim a global depth reduction from 13 to 12.

### Design

`server/src/app.module.ts` will import `HealthController` and `HealthService`
directly, register the controller on `AppModule`, and add the service beside the
existing `SafeLogger` provider. `HealthModule` leaves the imports array and
`server/src/health/health.module.ts` is deleted.

`server/src/app.module.spec.ts` will reuse `findProviderOwners`,
`findControllerOwners` and `expectSoleOwner` to prove that the dynamically
compiled `AppModule` owns exactly one `HealthService` and exactly one
`HealthController`.

Health controller/service bodies, routes, response shapes, thresholds, worker
timers, repositories, database queries, rollout flags and readiness behavior do
not change.

### Acceptance

- `/health`, `/health/live` and `/health/ready` retain their controller behavior,
  including the degraded `503` readiness response.
- The compiled Nest graph contains one health controller and one health service,
  both owned by `AppModule`; all four injected dependencies resolve to their
  existing singleton owners.
- Server import edges are strictly below 3,202 and cross-module edges strictly
  below 1,879; cycles remain 0 and depth does not exceed 13.
- Server modularity does not fall below 5,511 and server quality does not fall
  below 6,386. Any regression requires explanation and rejection or owner review.
- Focused health/AppModule tests, backend typecheck and backend build pass.

## Lane C: Teacher Compensation Decision Partition (`C2`)

### Current Structure

`calculateTeacherCompensation` in
`server/src/crm/commerce/lesson-settlement.calculation.ts` has RepoWise CCN 31,
cognitive complexity 34 and 58 NLOC. It mixes duration and money validation,
legacy standard calculation, configured/override parsing, override policy and
five compensation modes. The file has 84% line coverage and 70.45% branch
coverage, a stable risk score of 0.446, four dependents and a direct spec.

Unlike Dart methods, this exported TypeScript function is captured as a full
`function_declaration`; its branch complexity is visible to Sentrux. It is the
measurable equality cut for this sprint.

### Design

Keep the exported function signature and result unchanged. Add three
non-exported same-file helpers:

```ts
parseTeacherValues(configuredValue, overrideValue)
  -> { configured, overridden }

teacherOverrideState(mode, overrideValue, configured, overridden, overrideReason)
  -> { hasOverride, normalizedReason }

resolveTeacherModeValues(mode, standardAmount, configured, overridden, durationMinutes)
  -> { defaultValue, actualValue, rate, amount }
```

The exported function remains the ordered orchestrator: duration validation,
legacy money parsing/standard amount, configured values, override policy,
mode calculation, final amount limit and response formatting. The mode helper
uses an exhaustive switch over the existing five `TeacherCompensationFactType`
values; no generic strategy registry or new file is introduced.

The refactor preserves this exact error precedence:

```text
duration
  -> legacy money
  -> configured/override numeric syntax and limit
  -> override prohibition for none/standard
  -> percent limit
  -> changed-override reason
  -> final standard/amount limit
```

It also preserves half-up rounding, all legacy fixed/hourly/none calculations,
all five compensation modes, trimmed reasons, and the rule that an equal
override is not a change and returns `overrideReason: null`.

### Acceptance

- Characterization covers every error code in precedence order, legacy
  fixed/hourly/none, half-up boundaries, all five modes and equal/changed
  overrides.
- `calculateTeacherCompensation` falls to RepoWise CCN at most 8; each new helper
  is at most 10 and the file maximum is at most 15.
- Against the stock server snapshot immediately before C2, equality score rises
  strictly and raw Gini falls strictly; it also stays above the M0 floor 5,475
  and below raw `0.4525196921628077`.
- Server import/depth/cycle counts do not regress, all three TypeScript sensor
  hashes stay exact, and quality does not fall below the pre-C2 snapshot.
- Focused settlement suites, backend typecheck and backend build pass with exact
  result/error compatibility.

## Parallel Ownership

Each lane uses an isolated `codex/` branch/worktree and writes only its owned
paths. The coordinator owns the root checkout, baselines, reviews, integration,
RepoWise reindex and final Sentrux scans.

| Lane | Production ownership | Test/tool ownership | Maximum lane time |
|---|---|---|---:|
| A | none | `tool/sentrux/dart/**`, sensor runner/library/test | 215 minutes |
| B | `app.module.ts`, delete `health.module.ts` | `app.module.spec.ts` | 180 minutes |
| C | `lesson-settlement.calculation.ts` | existing calculation spec | 170 minutes |

No agent changes lockfiles, `.sentrux/baseline.json`, `.sentrux/rules.toml`,
generated RepoWise data or another lane's files. Each lane returns one focused
commit SHA and its before/after evidence. Reviewers do not edit implementer
worktrees; a blocking review finding omits the lane from this candidate.

Lane A additionally owns the installed Dart query only during its locked
critical section. No other implementation or coordinator scan may touch or read
the staged global query during that interval.

The requested ten-specialist team runs in waves because the environment permits
three specialists beside the coordinator: specialists 1-3 completed the design
research, 4-6 implement the lanes, 7-9 review them, and specialist 10 verifies
the integrated candidate.

## Five-Hour Clock

| Clock | Work |
|---|---|
| `0:00-0:20` | Clean-state check, worktrees, `M0` root/server baselines and focused test baselines |
| `0:20-3:10` | Three lanes run in parallel; Lane C reaches its hard implementation deadline |
| `3:10-3:55` | Independent C then B reviews while A finishes; B deadline `3:20`, A deadline `3:55` |
| `3:55-4:30` | Independent A review; coordinator integrates reviewed B/C and scans after each cut |
| `4:30-4:50` | Integrate A only if clean; run sensor recovery/hash gates and stock root check |
| `4:50-5:00` | Final evidence, accepted-lane SHAs and clean-tree status |

A lane that misses its deadline or focused green state is omitted rather than
allowed to consume the integration window. A lane with an unresolved Critical
or Important review finding is not cherry-picked. There is no correction window
after an independent review; partial or late commits are not accepted.

## Verification

### Lane A

```powershell
flutter test test/architecture/sentrux_dart_sensor_test.dart
dart analyze tool
dart run tool/calibrate_sentrux_dart.dart --fixture-only
dart run tool/calibrate_sentrux_dart.dart --full-repo .
git diff --exit-code bc7dce8a -- lib server/src .sentrux/rules.toml .sentrux/baseline.json
```

### Lane B

```powershell
npm --prefix server test -- --runTestsByPath src/health/health.service.spec.ts src/health/health.controller.spec.ts src/app.module.spec.ts
npm --prefix server run typecheck
npm --prefix server run build
```

### Lane C

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/lesson-settlement.calculation.spec.ts src/crm/commerce/lesson-settlement-catalog.spec.ts src/crm/commerce/lesson-settlement-execution.spec.ts src/crm/commerce/lesson-settlement-plan.persistence.spec.ts src/crm/commerce/lesson-settlement-postgres.integration.spec.ts
npm --prefix server run typecheck
npm --prefix server run build
```

The calculation characterization replaces partial `toMatchObject` checks with
full `toEqual` result objects, including `snapshotRate`, the exact key set and
`overrideReason: null`. Multi-invalid inputs assert which error wins at every
boundary in the frozen precedence sequence. The local PostgreSQL integration
suite is mandatory; if its database is unavailable, C2 is omitted rather than
accepted on unit tests alone.

### Integrated Gates

```powershell
git diff --check
repowise update --index-only
sentrux check .
git status --short --branch
```

In a fresh stock Sentrux MCP process, the integrator performs
`scan(<absolute-repo>/server) -> health` before integration, after Lane B and
immediately before/after Lane C. All three TypeScript sensor hashes are checked
around every pair. Lane effects are accepted sequentially, never inferred from
one combined scan.

After restoring stock plugins, the integrator performs
`scan(<absolute-repo>) -> health -> check_rules`. The final root result is
reported beside `M0` with the Dart caveat attached. The legacy `sentrux gate .`
failure remains documented rather than misreported as a passing gate.

## Sprint Acceptance Matrix

| Area | Required result |
|---|---|
| Sensor | Reproducible supported call edges, known definition failure retained, exact external-byte restoration |
| Health boundary | One AppModule-owned controller/service, fewer server/cross-module edges, no behavior regression |
| Equality cut | Strict server-only equality improvement with unchanged calculation results and error order |
| Structural guard | Server quality at least 6,386, cycles 0, depth at most 13, rules 2/2 pass |
| Repository guard | Focused tests/typecheck/build green, RepoWise reindexed, no unexpected diff, clean final tree |

## Explicit Exclusions

- No payment-form, preview-token or schedule-presenter implementation from the
  superseded design.
- No Sentrux core fork, custom production binary, permanent user-profile plugin
  change or claim that `M1` repairs full Dart metrics.
- No exclusion/renaming of tests, migrations, Flutter source or generated code
  to improve a score.
- No route, DTO, public API, provider contract, database, migration, UI, theme,
  deployment or production-data change.
- No update of the checked-in Sentrux baseline/rules and no 8,000-9,000 score
  claim inside this five-hour candidate.

## Future `M2` Gate Toward 8,000

Before root quality becomes the roadmap KPI, Sentrux must support paired Dart
signature/body captures. The signature must supply name, parameters, visibility
and method identity; the body must supply hash and cyclomatic complexity; the
core must synthesize one correct function span.

`M2` acceptance requires distinct bodies with the same signature to stop
appearing duplicated, identical bodies to remain duplicates, branch changes to
move function complexity/equality, and signature-only renames not to change
body complexity. Fixtures must cover block/arrow functions, top-level and class
methods, extensions, getters/setters, operators and constructors.

Only after `M2` is green will the team rebaseline root Sentrux and forecast the
number of structural cuts needed for 8,000. A score of 9,000 remains a stretch
goal whose cost must be derived from that corrected baseline.

## Rollback

Lane A is reverted by its single repository commit; its runner must already have
restored the external stock query byte-for-byte. Lane B restores
`HealthModule` and the original `AppModule` import. Lane C restores the original
single calculation function and its prior tests. There are no migrations,
persisted-format changes, environment changes or production operations to undo.
