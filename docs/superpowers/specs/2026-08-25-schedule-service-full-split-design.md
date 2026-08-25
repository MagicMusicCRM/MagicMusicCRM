# Schedule Service Full Split Design

**Date:** 2026-08-25

**Status:** Approved for implementation

## Context

RepoWise identifies `server/src/crm/schedule.service.ts` as the current
highest-impact production health target after the recurring-schedule UI cut.
The file has 1,860 NLOC, health `1.9`, maximum CCN `16`, and a weighted deficit
of 11,346 points. `ScheduleService` itself spans roughly 1,755 lines across 35
methods. It is both a hotspot and a graph bottleneck: 19 incoming and 79
outgoing dependencies, 97th-percentile betweenness, and three recent fixes in
conflict detection and recurring-series materialization.

The earlier read-service cut removed three projections, but one self-view read,
lesson mutations, conflict detection, advisory locks, recurring-series CRUD,
and recurring-series materialization still share one class. This forces
unrelated changes through a transaction-sensitive god class and makes every
schedule fix carry a large blast radius.

Production forces the V4 schedule path, while non-production and compatibility
flows still exercise the legacy path. This split preserves that switch. It
changes ownership and composition only; it does not retire either execution
path or introduce a second scheduling model.

## Goal

Delete the `ScheduleService` god class after moving every remaining behavior to
one cohesive owner and wiring all production callers directly to those owners,
without changing routes, DTOs, SQL behavior, authorization, transactions,
locks, idempotency, audit/outbox, notifications, realtime fanout, or legacy/V4
selection.

This is package 2 of the production code-health recovery program. Completion of
this package does not close the global program: the next production god file is
selected by RepoWise weighted impact and refactored until every production
source area reaches the approved health targets.

## Non-goals

- No API, database schema, migration, product-rule, or production-state change.
- No removal of legacy schedule execution or shadow/compatibility coverage.
- No rewrite of SQL, recurrence algorithms, booking-window rules, or event
  payloads while code is moving.
- No new repository layer or generic scheduling framework.
- No compatibility facade named `ScheduleService` after direct callers migrate.

## Approved component boundaries

### `schedule-locks.ts`

Pure transaction-aware lock helpers:

- shared `ScheduleQueryExecutor` type;
- deterministic resource lock acquisition;
- recurring-series advisory lock acquisition;
- plan-series lock acquisition for caller-owned `PoolClient` transactions.

The module has no Nest provider and performs no query outside the supplied
executor. Lock-key calculation, sorting, and SQL stay behavior-identical.

### `ScheduleConflictService`

Owns public conflict preflight plus the atomic command-side conflict assertion:

- `getScheduleConflicts(actor, query)`;
- `assertNoScheduleConflicts(params, executor)`;
- conflict SQL, overlap predicates, row mapping, and resource-lock use.

It depends on `DatabaseService` and `CrmPolicy`. Lesson mutation calls it inside
the existing transaction and passes that transaction's executor.

### `ScheduleSeriesMaterializerService`

Owns recurrence expansion and persistence:

- series candidate lookup and deterministic lock keys;
- constraint validation and reservation checks;
- occurrence snapshots and horizon materialization;
- `materializePlanSeries(client, seriesId)`;
- `extendAllSeriesHorizon()`.

It depends on the database, constraint engine, and the existing optional
subscription reservation service. It accepts caller-owned transactions where
the old service did and never opens a second transaction for plan
materialization.

### `ScheduleSeriesService`

Owns recurring-series application commands:

- list, create, update, and delete series;
- expected-version and date/range validation;
- series DTO mapping;
- audit and realtime effects;
- delegation to the materializer after persistence.

It depends on the database, audit, policy, realtime bus, and materializer.

### `LessonScheduleMutationService`

Owns legacy-path lesson mutation behavior:

- create, update, and delete lesson;
- bulk teacher-rate update;
- lesson subject/client resolution and write authorization;
- booking-window guard, audit metadata, notifications, and realtime fanout.

It calls `ScheduleConflictService` for conflict enforcement. The controller
continues choosing between this service and the existing V4 command services
using `V4DomainFlagsService`; the branch conditions do not change.

### Existing `ScheduleReadService`

Gains `listUpcomingLessonsForStudents(actor, studentIds)`, including its
current policy assertion, SQL predicate, ordering, and row shape. `CrmService`
uses the read owner directly.

## Direct caller migration

- `CrmScheduleController` injects the read, conflict, series, lesson-mutation,
  V4 command, transition, plan, and analyzer owners directly.
- `SchedulePlanService` imports the pure plan lock helper and injects
  `ScheduleSeriesMaterializerService` for in-transaction materialization.
- `ScheduleSeriesWorker` injects `ScheduleSeriesMaterializerService`.
- `CrmService` injects `ScheduleReadService` for upcoming student lessons.
- `CrmModule` registers and exports the new owners and removes
  `ScheduleService`.

After migration, live-source search must find no import, constructor parameter,
provider registration, or test construction of `ScheduleService`. The original
file is deleted rather than retained as a delegate.

## Invariants

- Existing transaction boundaries and `PoolClient` ownership are preserved.
- Advisory locks remain deterministic and are acquired before conflict checks
  or series writes in the same order as today.
- Lesson monetary, expected-version, idempotency, audit/outbox, and append-only
  facts remain unchanged.
- RBAC and resource-scope enforcement remains on the backend and fail-closed.
- Existing legacy/V4 route selection, response shapes, status codes, and error
  codes remain unchanged.
- Test-only source moves do not count as production health improvement.

## Test strategy

Move characterization tests to the component that owns the behavior; do not
copy or weaken assertions. First record the current focused suite total. For
each boundary, add an ownership test that fails because the intended owner or
direct route is absent, then implement the smallest byte-preserving move that
makes it pass.

Focused coverage must prove:

- conflict preflight, atomic executor use, resource locks, and overlap errors;
- series expected-version, CRUD, materialization, plan transaction use, worker
  horizon extension, constraints, reservations, audit, and realtime behavior;
- lesson create/update/delete/rate behavior across legacy and V4 controller
  paths, including notifications and authorization;
- upcoming student lesson privacy and projection through `ScheduleReadService`;
- Nest production composition resolves every new owner and no old owner.

Every structural commit requires focused tests, typecheck, Sentrux scan/health/
rules, and RepoWise index refresh. The final package requires the full backend
suite and build.

## Acceptance

- `server/src/crm/schedule.service.ts` and class `ScheduleService` no longer
  exist.
- All production callers depend directly on the approved cohesive owners.
- No moved public behavior has two implementation owners or a compatibility
  facade.
- Focused tests, full backend tests, typecheck, Nest build, and `git diff
  --check` pass.
- Sentrux quality remains at least `4974`, acyclicity raw remains `1`, depth is
  at most `13`, and both architectural rules pass after every step.
- RepoWise is indexed at implementation HEAD, reports no new cycle or broken
  caller, and records a material reduction in weighted production deficit.
- The global code-health program remains active and immediately re-ranks all
  remaining production god files after this package.

## Rollback

Each ownership boundary is committed separately. Revert caller wiring before
the corresponding extraction commit. No database or production-state rollback
is required because the package changes neither schema nor persisted data.
