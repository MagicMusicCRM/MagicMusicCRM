# Lesson Settlement Ownership Split Design

**Date:** 2026-08-25

## Context

RepoWise at `650960b1940c` identifies
`server/src/crm/commerce/lesson-settlement.repository.ts` as the highest
recoverable production hotspot after the CRM configuration package. It scores
`1.00`, contains `1,264` NLOC with max CCN `21`, carries `8,848` weighted
deficit points, has eight indexed dependents, and is an increasing 96th
percentile churn hotspot.

The file is not one repository. Its 1,233-line class owns five different
responsibilities:

1. settlement-plan creation, cloning, versioning, and state changes;
2. current and frozen configuration-catalog resolution;
3. settlement execution and idempotent replay;
4. append-only client/teacher fact persistence and correction links;
5. subscription capacity locks and reservation updates.

The existing PostgreSQL suites are behaviorally strong, but their names are
not paired with the source file, so RepoWise reports the production hotspot as
having no paired test. The full backend baseline is `204/204` suites and
`1,516/1,516` tests.

## Goal

Delete the overloaded repository and give each financial responsibility one
semantic owner while preserving the existing `LessonSettlementPort`, caller
owned transaction, SQL order, lock order, error contracts, immutable facts,
and all production behavior.

This is an ownership split, not a commerce redesign.

## Options considered

### Keep the class and extract private methods

This reduces individual method size but preserves the false repository
boundary and its combined plan/catalog/facts/capacity ownership. It does not
solve churn scatter or make future financial changes land in one place.

### Add several injected NestJS repositories behind the old repository

This creates a compatibility facade and an extra dependency layer. Direct test
construction becomes more complicated, while production still has two public
owners for the same settlement port.

### Selected: delete the repository and use executor-preserving functional owners

`LessonSettlementService` remains the only implementation of
`LessonSettlementPort`. It delegates to dependency-light functions grouped by
semantic responsibility. Every function receives the caller's exact
`PoolClient`; no owner may open or commit a transaction.

This keeps the dependency chain shallow, makes direct construction simpler,
and removes the overloaded class rather than hiding it.

## Ownership model

### `lesson-settlement-catalog.ts`

Owns:

- current school/branch catalog resolution;
- frozen revision-pair loading;
- catalog-shape validation;
- planned-decision validation against active catalog entries;
- shared conversion of calculation failures to the existing API error.

It does not own lesson rows, facts, reservations, or transactions.

### `lesson-settlement-plan.persistence.ts`

Owns:

- prepare, assign, and clone plan operations;
- initial plan and immutable plan-revision insertion;
- exact planned subscription allocation preview;
- optimistic plan replacement and revision insertion;
- plan loading/locking and state transition persistence.

It preserves the current optimistic version and append-only revision rules.

### `lesson-settlement-facts.persistence.ts`

Owns SQL-only fact operations:

- locked settlement source loading;
- effective client/teacher fact loading and DTO projection;
- charge-source and excluded-participant loading;
- correction supersession lookup;
- legacy fact insertion;
- configured client and teacher fact insertion.

It never decides catalog policy or subscription capacity.

### `lesson-settlement-subscription-capacity.ts`

Owns deterministic subscription locking, capacity validation, reservation
upsert, and correction-capacity validation. Subscription IDs remain sorted
before row locks so concurrent settlement order remains deterministic.

### `lesson-settlement-execution.ts`

Owns high-level settlement orchestration and calculation:

- acquire the existing advisory transaction lock;
- return an existing effective result on an idempotent replay;
- validate an explicitly repeated decision;
- load and validate the locked lesson snapshot;
- calculate configured facts from the selected/frozen catalog;
- invoke capacity and fact-persistence owners;
- require a complete result after insertion.

Its body must read as an outline. SQL paragraphs belong to facts persistence;
capacity SQL belongs to the capacity owner.

### `lesson-settlement.service.ts`

Remains the production application facade and sole port implementation. It
keeps `settleStandalone` as the only method in this package that starts a
database transaction. All client-taking methods forward the exact executor to
the appropriate semantic function.

### Deleted owner

`lesson-settlement.repository.ts` is deleted after all production and test
consumers move to `LessonSettlementService` or the narrow functional owner.
No compatibility facade or re-export remains.

## Data and execution flow

```text
caller-owned transaction / PoolClient
  -> LessonSettlementService (port)
       -> plan persistence
            -> catalog
            -> calculation
       -> settlement execution
            -> catalog
            -> facts persistence
            -> subscription capacity
            -> calculation
```

All arrows below the service carry the same `PoolClient` instance.

## Financial invariants

- `settleStandalone` starts one transaction; client-taking methods never do.
- The advisory lock key and lesson `FOR UPDATE` lock remain unchanged.
- Subscription rows are locked in sorted ID order before reservations/facts.
- Idempotent replay returns the existing effective fact pair and rejects a
  different explicit decision.
- Corrections append facts with `correction_id` and `supersedes_fact_id`; no
  historical fact is updated or deleted.
- Plan revisions remain append-only and plan replacement keeps expected
  version enforcement.
- Configuration revision IDs are frozen into the plan and facts; an archived
  catalog remains readable by its exact revision IDs.
- Group participant exclusions, personal-account minor conversion, fractional
  subscription units, compensation overrides, and Russian error contracts are
  preserved exactly.
- Missing or partial facts continue to fail closed.

## Test strategy

Use red-green-refactor and move tests with ownership rather than weakening the
existing PostgreSQL gates.

1. Add paired catalog/policy tests for current versus frozen revision loading,
   invalid decisions, percent bounds, and calculation-error mapping.
2. Add paired facts tests for complete/partial effective projections and
   settleable snapshot/context validation.
3. Keep the existing settlement, race, completion, lesson-write, reschedule,
   and schedule-plan PostgreSQL suites authoritative for lock order,
   concurrency, corrections, append-only history, and rollback.
4. Update direct test construction from the deleted repository to the service
   or narrow function without changing assertions.
5. Run focused tests after each structural commit, then full backend tests,
   typecheck, Nest build, diff checks, Sentrux, RepoWise health, and change
   risk.

## Acceptance

- `lesson-settlement.repository.ts` is deleted and has no compatibility owner.
- `LessonSettlementService` remains the only `LessonSettlementPort`
  implementation and no caller-visible method or payload changes.
- Every replacement production file has RepoWise health at least `7.0`; no
  replacement has a god-class/brain-method finding, max CCN above `10`, or
  more than `750` NLOC.
- Combined replacement weighted deficit is at most `1,769`, an 80% reduction
  from the `8,848` baseline.
- Focused PostgreSQL suites, all backend tests, typecheck, Nest build, and
  `git diff --check` pass.
- Sentrux quality remains at least `5720`, acyclicity score remains `10000`,
  depth remains at most `13`, and both architecture rules pass after each
  structural commit.
- RepoWise is exact at implementation HEAD with no new cycle, missing
  consumer, or unexplained change-risk warning.

## Rollback

Land catalog policy, plan ownership, facts/capacity ownership, execution/service
wiring, and old-file deletion as independent commits. Revert in reverse order.
No migration, API, environment, production-state, or data-repair rollback is
required.

## Verified outcome

The split is implemented and verified at `dd71952a0f9f`. It landed as five
independent implementation commits: catalog policy `f19a4ef1`, plan persistence
`bc29834f`, fact persistence `8833e37e`, capacity locks `59520bae`, and final
execution/service wiring with old-repository deletion `dd71952a`.

- The old `lesson-settlement.repository.ts` owner and its provider registration
  are deleted; live source contains no compatibility facade or stale reference.
  `LessonSettlementService` remains the sole `LessonSettlementPort`
  implementation and the only package owner that starts a transaction.
- RepoWise is exact at implementation HEAD with `index_behind=false`. Replacement
  health is service `7.25`, facts `8.80`, execution `8.85`, catalog `9.15`,
  capacity `9.47`, and plan persistence `9.85`; max CCN is `10`, max NLOC is
  `555`, and no replacement has a god-class or brain-method finding.
- Combined replacement weighted deficit is `82`, down `99.1%` from the `8,848`
  baseline and below the `1,769` acceptance ceiling.
- Verification passed: `209/209` backend suites, `1,531/1,531` tests,
  TypeScript typecheck, Nest build, and `git diff --check`. Paired focused tests
  cover every extracted owner, while the PostgreSQL suites retain the financial,
  locking, correction, and rollback gates.
- Sentrux reports quality `5732`, acyclicity score `10000` with raw `0`, depth
  `13`, equality `6223`, modularity `5360`, redundancy `4870`, and both
  architecture rules passing.

RepoWise classifies the full package range as `Elevated` at percentile `100`
because it contains 22 files and 4,145 changed lines. It reports no cycle,
breaking consumer, missing test, cross-repository change, or conformance
violation. Historical graph output still names the deleted repository, but the
exact index, clean build, full test suite, and live-source search jointly close
that warning.
