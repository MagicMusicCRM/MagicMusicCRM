# Schedule Service Full Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the `ScheduleService` god class by moving all remaining behavior to cohesive, directly consumed owners without changing scheduling semantics.

**Architecture:** Extract pure advisory-lock functions, conflict enforcement, recurring-series materialization, recurring-series CRUD, and legacy lesson mutations into separate owners. Add the remaining self-view read to `ScheduleReadService`, migrate every production caller directly, and remove the old service with no facade.

**Tech Stack:** NestJS 11, TypeScript 5.8, Jest 30, PostgreSQL, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-25-schedule-service-full-split-design.md`

## Global constraints

- Preserve routes, DTOs, SQL text and parameter order, transaction boundaries,
  `PoolClient` ownership, lock ordering, error/status codes, and response shapes.
- Preserve legacy/V4 selection and all shadow/compatibility coverage.
- Preserve authorization, expected version, idempotency, booking-window,
  audit/outbox, notifications, realtime, and subscription-reservation behavior.
- Move tests rather than copy them; focused suite totals must not decrease.
- Do not retain a `ScheduleService` facade or duplicate implementation owner.
- Commit each structural boundary separately. After each commit run focused
  tests, `npm --prefix server run typecheck`, Sentrux scan/health/rules, and
  `repowise update --index-only`.
- Stop on unexplained Sentrux regression: quality `< 4974`, acyclicity `< 1`,
  depth `> 13`, or either architecture rule failing.
- Preserve unrelated working-tree changes and never include them in a commit.

## Task 1: Extract deterministic locks and conflict ownership

**Files:**

- Create `server/src/crm/schedule/schedule-locks.ts`
- Create `server/src/crm/schedule/schedule-conflict.service.ts`
- Create `server/src/crm/schedule/schedule-conflict.service.spec.ts`
- Modify `server/src/crm/schedule.service.ts`
- Modify `server/src/crm/crm-schedule.controller.ts`
- Modify `server/src/crm/crm-schedule.controller.spec.ts`
- Modify `server/src/crm/crm.module.ts`

- [ ] Record the current focused `schedule.service.spec.ts` and controller test
  totals.
- [ ] Add a failing direct-routing test for `ScheduleConflictService` and a
  failing isolated ownership test for atomic executor use.
- [ ] Move lock-key calculation/acquisition into pure functions and move
  conflict preflight/assertion into `ScheduleConflictService` without rewriting
  SQL or overlap logic.
- [ ] Route the controller and remaining command-side calls to the new owner;
  remove the old conflict methods.
- [ ] Run the conflict, schedule, and controller specs; typecheck; `git diff
  --check`; commit `refactor(schedule): extract conflict ownership`.
- [ ] Run Sentrux gates and refresh RepoWise at the commit HEAD.

## Task 2: Extract recurring-series materialization

**Files:**

- Create `server/src/crm/schedule/schedule-series-materializer.service.ts`
- Create `server/src/crm/schedule/schedule-series-materializer.service.spec.ts`
- Modify `server/src/crm/schedule.service.ts`
- Modify `server/src/crm/schedule/schedule-plan.service.ts`
- Modify `server/src/crm/schedule/schedule-plan-postgres.integration.spec.ts`
- Modify `server/src/crm/schedule-series.worker.ts`
- Modify `server/src/crm/crm.module.ts`

- [ ] Add failing ownership tests proving plan materialization uses its supplied
  transaction and the worker invokes the dedicated materializer.
- [ ] Move candidate lookup, recurrence expansion, snapshots, constraint and
  reservation validation, occurrence writes, and horizon extension as one
  cohesive implementation.
- [ ] Import `lockSchedulePlanSeries` from the pure lock module and inject the
  materializer directly into plan service and worker.
- [ ] Remove materialization delegates from `ScheduleService`.
- [ ] Run materializer, plan, worker, series integration, and schedule specs;
  typecheck; `git diff --check`; commit `refactor(schedule): extract series
  materialization`.
- [ ] Run Sentrux gates and refresh RepoWise at the commit HEAD.

## Task 3: Extract recurring-series CRUD

**Files:**

- Create `server/src/crm/schedule/schedule-series.service.ts`
- Create `server/src/crm/schedule/schedule-series.service.spec.ts`
- Modify `server/src/crm/schedule.service.ts`
- Modify `server/src/crm/crm-schedule.controller.ts`
- Modify `server/src/crm/crm-schedule.controller.spec.ts`
- Modify `server/src/crm/crm.module.ts`

- [ ] Add failing controller-routing and expected-version ownership tests.
- [ ] Move list/create/update/delete, date guards, DTO mapping, audit, realtime,
  and calls to the dedicated materializer without semantic edits.
- [ ] Route all series endpoints directly to `ScheduleSeriesService` and remove
  the old series surface.
- [ ] Run series unit/integration, schedule, and controller specs; typecheck;
  `git diff --check`; commit `refactor(schedule): extract series commands`.
- [ ] Run Sentrux gates and refresh RepoWise at the commit HEAD.

## Task 4: Extract lesson mutations and remaining read

**Files:**

- Create `server/src/crm/schedule/lesson-schedule-mutation.service.ts`
- Create `server/src/crm/schedule/lesson-schedule-mutation.service.spec.ts`
- Modify `server/src/crm/schedule/schedule-read.service.ts`
- Modify `server/src/crm/schedule/schedule-read.service.spec.ts`
- Modify `server/src/crm/schedule.service.ts`
- Modify `server/src/crm/crm-schedule.controller.ts`
- Modify `server/src/crm/crm-schedule.controller.spec.ts`
- Modify `server/src/crm/crm.service.ts`
- Modify `server/src/crm/crm.service.spec.ts`
- Modify `server/src/crm/student-funnel-postgres.integration.spec.ts`
- Modify `server/src/crm/crm.module.ts`

- [ ] Add failing tests for legacy-path lesson routing and direct upcoming-read
  ownership; keep the V4 branch assertions unchanged.
- [ ] Move `listUpcomingLessonsForStudents` to `ScheduleReadService` with its
  policy assertion, SQL, ordering, and row mapping unchanged.
- [ ] Move create/update/delete/rate plus lesson authorization, subject/client,
  audit, notification, and realtime helpers into
  `LessonScheduleMutationService`; inject `ScheduleConflictService` for atomic
  checks.
- [ ] Route controller legacy branches and `CrmService` directly to the new
  owners; remove all remaining methods from the old service.
- [ ] Run lesson command/parity/protected-patch, read, CRM, controller, and
  schedule specs; typecheck; `git diff --check`; commit `refactor(schedule):
  extract lesson schedule mutations`.
- [ ] Run Sentrux gates and refresh RepoWise at the commit HEAD.

## Task 5: Remove the god class and prove composition

**Files:**

- Delete `server/src/crm/schedule.service.ts`
- Delete or redistribute `server/src/crm/schedule.service.spec.ts`
- Modify `server/src/crm/crm.module.ts`
- Modify `server/src/app.module.spec.ts`

- [ ] Add a failing composition assertion for every new provider and verify no
  old provider can resolve.
- [ ] Move every remaining characterization test to its implementation owner;
  preserve the original combined focused test total.
- [ ] Remove the old source/spec and every import, constructor parameter,
  provider, export, mock, and type reference found by
  `rg -n "ScheduleService|schedule\.service" server/src`.
- [ ] Run all focused schedule/CRM/composition tests; typecheck; build; `git
  diff --check`; commit `refactor(schedule): remove schedule god class`.
- [ ] Run Sentrux gates and refresh RepoWise at the commit HEAD.

## Task 6: Full verification and global re-ranking

- [ ] Run `npm --prefix server test -- --runInBand`, `npm --prefix server run
  typecheck`, and `npm --prefix server run build`.
- [ ] Run Sentrux scan, health, and rules; record quality, depth, acyclicity,
  modularity, and changed-file results in the recovery-program evidence.
- [ ] Run `repowise update --index-only`, then request changed-file risk/health
  and confirm the index commit equals HEAD with no dependency cycle.
- [ ] Update
  `docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md`
  with before/after NLOC, CCN, health, weighted deficit, tests, and gates.
- [ ] Re-rank all remaining production files by recoverable weighted deficit;
  put the highest-impact god file into the next active package instead of
  ending the global program.
