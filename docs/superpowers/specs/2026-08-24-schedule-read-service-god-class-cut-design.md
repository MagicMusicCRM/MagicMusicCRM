# Schedule Read Service God-Class Cut Design

**Date:** 2026-08-24

**Status:** Implemented and verified at `e600c025`

## Context

RepoWise names `server/src/crm/schedule.service.ts` as the highest-leverage
health target in the repository. The file has 2,452 NLOC and a weighted deficit
of 16,110 points, or 3.1% of the repository gap to a health score of 8.0.
`ScheduleService` itself spans 2,335 NLOC across 42 methods. RepoWise classifies
it as a critical god class, a top-3% change-entropy hotspot, and a 99th-percentile
bug-prone file. It co-changes with 37 files and has three recent bug-fix commits.

The risk is unusually controllable for a god-class cut: current coverage is
88.16% line and 73.98% branch. Live-source inspection also exposes a cohesive
query-only slice at the top of the class. Its production callers are
`CrmScheduleController` and `CrmService`; no command or worker calls these read
methods.

No recorded ADR governs this boundary. Git archaeology shows that
`ScheduleService` was originally extracted from `CrmService` for single
responsibility, then accumulated read projections, lesson commands, conflicts,
resource locks, recurring-series orchestration, audit, notifications, and
realtime effects. This design continues that original separation instead of
introducing a parallel scheduling model.

## Goal

Create one cohesive schedule-read component and remove its implementation and
tests from the schedule command god class without changing any API response,
authorization decision, SQL predicate, route, transaction, or product behavior.

## Non-goals

- No change to lesson creation, update, deletion, settlement, transitions, or
  recurring-series commands.
- No move of conflict lookup, `queryConflicts`, advisory locks, booking-window
  guards, expected-version checks, idempotency, audit/outbox, notifications, or
  realtime fanout.
- No controller route, DTO, database schema, migration, environment, or
  production-state change.
- No compatibility façade on `ScheduleService`; production callers will depend
  on the component that actually owns the read behavior.
- No simultaneous split of the Flutter scheduling god classes.

## Considered approaches

### 1. Direct query-service split — selected

Move the three public read operations and their private projection helpers to a
new `ScheduleReadService`. Inject it directly into `CrmScheduleController` and
`CrmService`. This removes the largest cohesive block from the god class and
stops read-only changes from co-changing with transaction-sensitive commands.

Trade-off: two production constructors and their tests change. This is accepted
because direct ownership is clearer and the affected dependency graph is small.

### 2. Delegate through `ScheduleService`

Keep identically named façade methods on `ScheduleService` and forward them to a
new read service. This minimizes constructor changes, but preserves the wrong
public dependency and keeps read changes coupled to the god-class surface.

### 3. Extract SQL into a repository only

Move query text and row mapping into a repository while leaving authorization
and orchestration methods in `ScheduleService`. This isolates SQL but does not
meaningfully reduce the god class or its method-level change entropy.

## Component boundary

Create `server/src/crm/schedule/schedule-read.service.ts` with these public
methods, retaining their current signatures and return shapes:

- `getScheduleMatrix(actor, query)`;
- `getScheduleMonthSummary(actor, query)`;
- `listLessons(actor, query)`.

Move the following private read-only implementation with them:

- `scheduleMatrixBounds` and `utcDayStart`;
- `groupScheduleItems`;
- `clientLessonAccessSql`;
- the `ScheduleLessonRow` projection type;
- imports used only by this slice, including `LessonQuery`,
  `ScheduleMatrixQuery`, and `managerAdminRolesSql` when no command-side use
  remains.

`ScheduleReadService` depends only on `DatabaseService` and `CrmPolicy`. It must
not depend on `ScheduleService`, command services, audit, notifications,
realtime, constraint evaluation, or subscription reservation.

`ScheduleService` keeps all remaining command, conflict, lock, series, and
side-effect behavior. No delegate methods remain after callers are migrated.

## Dependency and request flow

`CrmModule` registers both services. `CrmScheduleController` injects
`ScheduleReadService` for the existing lesson-list, matrix, and month-summary
routes, while it continues to use `ScheduleService` for the existing command,
conflict, and series routes.

`CrmService.getStudentCard` uses `ScheduleReadService.listLessons` directly.
This avoids a read path through the command god class and does not create a
cycle because the read service depends only on database and policy services.

The HTTP paths, guards, DTO validation, status codes, and response bodies remain
unchanged. This is a dependency-ownership change, not a new API.

## Security and data invariants

The moved implementation is transferred without semantic rewriting.

- `getScheduleMatrix` and `getScheduleMonthSummary` continue calling
  `CrmPolicy.assertCanReadOperationalData` before querying.
- `listLessons` continues serving every role through its existing fail-closed
  SQL row predicate. New or unknown roles receive no rows unless explicitly
  added to that predicate.
- Teacher compensation and settlement repair fields remain selected only for
  actors allowed by the existing `CrmPolicy` gates.
- Client payment projection remains actor-scoped and must not expose client
  money to teachers.
- Moscow business-date bounds, lifecycle filters, group-participant exclusions,
  overlap deduplication, ordering, pagination, and null-versus-zero money
  semantics remain byte-for-byte or assertion-equivalent.

No query in this slice accepts a transaction executor. Conflict lookup and every
command helper that can receive a caller-owned `PoolClient` stay in
`ScheduleService`, preserving transaction and advisory-lock ownership.

## Test design

Create `server/src/crm/schedule/schedule-read.service.spec.ts`. Move, rather than
copy, every test whose subject is one of the three read methods. The new test
fixture constructs only `DatabaseService`, `CrmPolicy`, and
`ScheduleReadService` dependencies.

The read spec must preserve characterization coverage for:

- role-scoped lesson rows and unknown-role fail-closed behavior;
- payment, teacher-rate, settlement-failure, and compensation-field privacy;
- lesson ID, student, client/family/manual-link, trial, order, and limit filters;
- month-summary lifecycle and Moscow-bound behavior;
- matrix grouping, group participants, lifecycle state, conflict flags, pair
  deduplication, settlement projection, and teacher scope.

`schedule.service.spec.ts` keeps command, conflict, locking, series, booking
window, audit, notification, realtime, and mutation tests. Its shared fixture may
be simplified only where removed read tests no longer need a mock.

Controller and `CrmService` tests must prove that read calls go to
`ScheduleReadService` while command calls still go to `ScheduleService`.
A Nest composition test must resolve both providers from `CrmModule` or the
compiled application graph.

## Implementation sequence

1. Add failing ownership/routing tests for `ScheduleReadService`.
2. Create the read service and move the read tests and implementation.
3. Register the provider and migrate the two production callers.
4. Remove the read surface and read-only helpers from `ScheduleService`.
5. Run focused, full backend, build, Sentrux, and RepoWise gates.

Each logical step is committed separately so ownership wiring can be reverted
without reverting the extracted behavior tests.

## Acceptance

- All existing API routes and read response contracts remain unchanged.
- `ScheduleService` no longer defines or delegates the three read methods or
  their private projection helpers.
- `ScheduleReadService` has exactly the two approved dependencies and owns no
  timer, transaction, command, audit, notification, or realtime behavior.
- Focused schedule/controller/CRM tests, full backend tests, typecheck, and Nest
  build pass.
- Sentrux quality does not regress, acyclicity remains 1, and architectural
  rules pass. Depth 13 remains the already documented Flutter-test limitation.
- RepoWise is re-indexed at the implementation HEAD. Changed-file health and
  change risk show no cycle, breaking consumer, or missing production caller.
- The god-class NLOC and weighted deficit decrease materially; exact score gain
  is measured rather than promised because history-based markers decay only
  through future focused commits.

## Rollback

Revert the caller-wiring commit, then the extraction commit. Because routes,
DTOs, SQL behavior, and database state do not change, rollback needs no migration
or production-data action.
