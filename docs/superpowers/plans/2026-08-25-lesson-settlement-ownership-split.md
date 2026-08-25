# Lesson Settlement Ownership Split Implementation Plan

> Execute with strict red-green-refactor. Preserve the caller-owned
> `PoolClient`, append-only financial facts, deterministic locks, and the
> public `LessonSettlementPort` after every task.

**Goal:** Delete the overloaded lesson-settlement repository and replace it
with tested catalog, plan, facts, capacity, and execution owners whose health
is at least 7.0.

**Tech Stack:** NestJS 11, TypeScript 5.8, PostgreSQL/PGlite, Jest 30,
RepoWise, Sentrux

## Global gates

- Baseline: health `1.00`, NLOC `1,264`, max CCN `21`, weighted deficit
  `8,848`, full backend `204/204` suites and `1,516/1,516` tests.
- After every structural commit run relevant Jest paths, typecheck,
  `git diff --check`, Sentrux rescan/health/rules, and allow the RepoWise hook
  to refresh.
- Stop on Sentrux quality below `5720`, acyclicity score below `10000`, depth
  above `13`, or an architectural-rule failure.
- Do not open transactions below `LessonSettlementService`; forward the same
  `PoolClient` through every new function.

### Task 1: Extract catalog loading and decision policy

**Files:**

- Create: `server/src/crm/commerce/lesson-settlement-catalog.ts`
- Create: `server/src/crm/commerce/lesson-settlement-catalog.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.repository.ts`

**Interfaces:**

```ts
export interface LessonSettlementCatalog { /* existing row shape */ }
export function invalidLessonSettlementDecision(code: string, field?: string): never;
export function rethrowLessonSettlementCalculation(error: unknown): never;
export async function loadLessonSettlementCatalog(
  client: PoolClient,
  branchId: string,
  revisions?: LessonSettlementRevisionIds,
): Promise<LessonSettlementCatalog>;
export function assertPlannedLessonSettlementDecision(
  catalog: LessonSettlementCatalog,
  decision: LessonFinancialDecision,
): void;
```

- [ ] Write red tests importing the missing functions and covering current and
  frozen catalog paths plus invalid settlement/pay/override decisions.
- [ ] Move the exact SQL and errors; no query or message changes.
- [ ] Rewire both plan and configured-settlement paths.
- [ ] Run catalog and settlement PostgreSQL tests, typecheck, Sentrux, and
  commit `refactor(commerce): extract settlement catalog policy`.

### Task 2: Extract plan persistence

**Files:**

- Create: `server/src/crm/commerce/lesson-settlement-plan.persistence.ts`
- Create: `server/src/crm/commerce/lesson-settlement-plan.persistence.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.repository.ts`

**Interfaces:**

```ts
export function prepareLessonSettlementPlan(...): Promise<PreparedLessonSettlementPlan>;
export function assignLessonSettlementPlan(...): Promise<PreparedLessonSettlementPlan>;
export function cloneLessonSettlementPlan(...): Promise<PreparedLessonSettlementPlan>;
export function insertPreparedLessonSettlementPlan(...): Promise<void>;
export function plannedLessonSubscriptionAllocations(...): Promise<PlannedSubscriptionAllocation[]>;
export function replaceLessonSettlementPlan(...): Promise<number>;
export function loadLessonSettlementPlan(...): Promise<StoredLessonSettlementPlan | null>;
export function markLessonSettlementPlanState(...): Promise<void>;
```

- [ ] Add a red paired test for executor reuse, optimistic replacement, and the
  immutable revision insert.
- [ ] Move plan functions and split allocation calculation into focused helpers
  so max CCN stays at most 10.
- [ ] Keep the old public methods as temporary delegators until Task 5.
- [ ] Run plan, lesson-write, schedule-plan, typecheck, Sentrux, and commit
  `refactor(commerce): extract settlement plan persistence`.

### Task 3: Extract fact persistence and projections

**Files:**

- Create: `server/src/crm/commerce/lesson-settlement-facts.persistence.ts`
- Create: `server/src/crm/commerce/lesson-settlement-facts.persistence.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.repository.ts`

**Interfaces:**

```ts
export function loadLessonSettlementSource(...): Promise<SettlementSource>;
export function loadLessonSettlementFacts(...): Promise<LessonSettlementResult | null>;
export function loadLessonSettlementCharges(...): Promise<ChargeSource[]>;
export function loadExcludedLessonParticipantIds(...): Promise<Set<string>>;
export function loadSupersededLessonFacts(...): Promise<SupersededFacts>;
export function insertLegacyLessonSettlementFacts(...): Promise<void>;
export function insertConfiguredClientFacts(...): Promise<void>;
export function insertConfiguredTeacherFact(...): Promise<void>;
```

- [ ] Write a red paired test for empty, complete, and partial effective fact
  projections.
- [ ] Move SQL and row-to-contract mapping exactly; split validation and DTO
  mapping into small pure helpers.
- [ ] Keep all inserts append-only and retain correction/supersession columns.
- [ ] Run settlement, completion, correction, typecheck, Sentrux, and commit
  `refactor(commerce): extract settlement fact persistence`.

### Task 4: Extract deterministic subscription capacity ownership

**Files:**

- Create: `server/src/crm/commerce/lesson-settlement-subscription-capacity.ts`
- Create: `server/src/crm/commerce/lesson-settlement-subscription-capacity.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.repository.ts`

**Interfaces:**

```ts
export function reserveLessonSettlementSubscriptions(...): Promise<void>;
export function assertCorrectionSubscriptionCapacity(...): Promise<void>;
```

- [ ] Add red tests for duplicate selection, sorted lock order, zero-unit
  behavior, insufficient capacity, ownership mismatch, and terminal
  reservation conflict.
- [ ] Move the exact locking and reservation SQL; preserve sorted subscription
  IDs and the correction exclusion of the current lesson.
- [ ] Run settlement and subscription-race suites, typecheck, Sentrux, and
  commit `refactor(commerce): extract settlement capacity locks`.

### Task 5: Extract execution and delete the old repository

**Files:**

- Create: `server/src/crm/commerce/lesson-settlement-execution.ts`
- Create: `server/src/crm/commerce/lesson-settlement-execution.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.service.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: the eight direct repository test consumers
- Delete: `server/src/crm/commerce/lesson-settlement.repository.ts`

**Interfaces:**

```ts
export function settleLesson(
  client: PoolClient,
  lessonId: string,
  input?: LessonSettlementInput,
): Promise<LessonSettlementResult>;
```

- [ ] Add red execution tests for context-to-lifecycle mapping, incomplete
  snapshots, idempotent replay, a different repeated decision, and required
  post-insert completeness.
- [ ] Move the high-level orchestration and configured calculation; use the
  new catalog/facts/capacity owners for all SQL side effects.
- [ ] Make `LessonSettlementService` delegate directly to plan/execution
  functions and remove its repository constructor dependency.
- [ ] Replace direct test construction without changing assertions; remove the
  repository provider/import and delete the old file.
- [ ] Run all settlement/race/completion/lesson-write/reschedule/schedule-plan
  suites, typecheck, Sentrux, and commit
  `refactor(commerce): remove settlement god repository`.

### Task 6: Verify package acceptance

- [ ] Run all backend tests, typecheck, Nest build, and `git diff --check`.
- [ ] Run Sentrux rescan/health/rules and record quality, depth, acyclicity,
  modularity, redundancy, and equality.
- [ ] Wait for RepoWise at exact HEAD; query health for service and every new
  production file. Require health `>=7`, max CCN `<=10`, NLOC `<=750`, no
  god/brain finding, and combined weighted deficit `<=1,769`.
- [ ] Run RepoWise change risk for the whole package and inspect every missing
  consumer/test warning against live source and executed suites.
- [ ] Append verified outcome to the package design and global recovery program
  and commit `docs(commerce): record settlement ownership split`.

### Task 7: Continue the global program

- [ ] Run a fresh RepoWise dashboard at the documentation HEAD.
- [ ] Select the highest recoverable production god/hotspot after applying the
  owner-approved production-first rule.
- [ ] Begin its pre-modification/design package; do not mark the global goal
  complete while module/code-only health floors or approved god-file cleanup
  remain open.
