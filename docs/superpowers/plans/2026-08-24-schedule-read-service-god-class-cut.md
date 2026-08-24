# Schedule Read Service God-Class Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove schedule read projections from the `ScheduleService` god class and give them one directly consumed, query-only owner without changing scheduling behavior.

**Architecture:** Split the existing read contract into `ScheduleReadService`, depending only on `DatabaseService` and `CrmPolicy`. `CrmScheduleController` and `CrmService` consume the new service directly; `ScheduleService` retains commands, conflicts, locks, recurring-series orchestration, and side effects with no compatibility façade.

**Tech Stack:** NestJS 11, TypeScript 5.8, Jest 30, PostgreSQL, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-24-schedule-read-service-god-class-cut-design.md`

## Global Constraints

- Preserve the existing lesson-list, schedule-matrix, and month-summary routes, DTOs, status codes, SQL predicates, parameter ordering, and response shapes.
- Preserve role-scoped fail-closed reads, finance/rate privacy, lifecycle filters, Moscow date bounds, conflict-pair deduplication, pagination, and ordering.
- Do not move or change conflict lookup, transactions, `PoolClient` ownership, advisory locks, expected-version, idempotency, booking-window guards, audit/outbox, notifications, or realtime behavior.
- `ScheduleReadService` may inject only `DatabaseService` and `CrmPolicy`; it owns no timer, command, transaction, or side effect.
- `ScheduleService` must not retain delegate methods for the extracted reads after Task 2.
- Do not change database schema, migrations, environment variables, API responses, production state, or Flutter code.
- Keep each task in its own commit and exclude unrelated working-tree changes.
- After the structural cut run `repowise update --index-only`; acceptance also requires Sentrux quality `>= 4976`, acyclicity raw `1`, and architectural rules PASS. Root depth `13` is the documented Flutter-test limitation, not a target for this plan.

## File Structure

- `server/src/crm/schedule/schedule-read.service.ts`: sole implementation owner for lesson-list, schedule-matrix, and month-summary reads.
- `server/src/crm/schedule/schedule-read.service.spec.ts`: isolated read-contract and dependency-boundary tests.
- `server/src/crm/schedule.service.ts`: command/conflict/lock/series owner after read code is removed.
- `server/src/crm/schedule.service.spec.ts`: command/conflict/lock/series tests only.
- `server/src/crm/crm-schedule.controller.ts`: routes reads to `ScheduleReadService`, commands to existing services.
- `server/src/crm/crm.service.ts`: builds the student-card lesson section through `ScheduleReadService`.
- `server/src/crm/crm.module.ts`: registers both schedule services.
- `server/src/app.module.spec.ts`: proves the production Nest graph resolves both owners.

---

### Task 1: Isolate the schedule read characterization suite

**Files:**
- Create: `server/src/crm/schedule/schedule-read.service.spec.ts`
- Modify: `server/src/crm/schedule.service.spec.ts`

**Interfaces:**
- Consumes: the current `ScheduleService.getScheduleMatrix`, `getScheduleMonthSummary`, and `listLessons` behavior.
- Produces: an isolated read-contract suite that Task 2 retargets to `ScheduleReadService` without changing its assertions.

- [ ] **Step 1: Record the current schedule-suite baseline**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule.service.spec.ts --runInBand
```

Expected: PASS. Record the suite/test totals in the task report; the combined
totals after the move must match this baseline.

- [ ] **Step 2: Create the read-contract fixture around the current service**

Create `server/src/crm/schedule/schedule-read.service.spec.ts` with the minimal
dependencies used by the existing read tests:

```ts
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { NotificationsService } from "../../notifications/notifications.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ScheduleService } from "../schedule.service";
import { ScheduleConstraintEngine } from "./constraint-engine.service";

describe("schedule read contract", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const buildDeps = () => ({
    audit: { record: jest.fn().mockResolvedValue(undefined) },
    notifications: {
      notifyUser: jest.fn().mockResolvedValue({ notificationId: "notif-test" }),
    },
    policy: {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertManagerOnly: jest.fn(),
      canReadTeacherRates: jest.fn().mockReturnValue(false),
      canReadSchoolFinance: jest.fn().mockReturnValue(false),
      canReadStudentFinance: jest.fn().mockReturnValue(false),
    },
    constraints: {
      validate: jest.fn().mockResolvedValue({ valid: true, violations: [] }),
    },
  });

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const deps = buildDeps();
    const service = new ScheduleService(
      { query } as unknown as DatabaseService,
      deps.audit as unknown as AuditService,
      deps.policy as unknown as CrmPolicy,
      deps.notifications as unknown as NotificationsService,
      { emitCrmChanged: () => undefined } as unknown as RealtimeBus,
      deps.constraints as unknown as ScheduleConstraintEngine,
    );
    return { service, query, ...deps };
  };

  // Moved characterization tests follow here without assertion changes.
});
```

- [ ] **Step 3: Move every read-only characterization test**

Move, do not copy, the blocks that assert only the three read methods. Preserve
their names, fixtures, SQL assertions, parameter arrays, and expected DTOs:

```text
«оплаты по дням» (all four cases)
applied teacher rate (all three cases)
projects settlement failure only to staff who can repair it
lists trial lessons with actor-scoped query
loads one exact terminal lesson without weakening actor scope
keeps terminal cancellation and reschedule sources out of month totals
keeps post-conversion lessons visible to manual-link and family clients
returns schedule matrix grouped by room with conflicts
counts an overlapping pair once, not twice (KVA-166 dedup)
surfaces the lead's name in schedule feeds (no more «Не назначен»)
orders the client history desc when asked (recent lessons first)
```

The last two tests currently live inside the client-reference describe block;
move only those two tests and leave the command cases in the original block.

- [ ] **Step 4: Run both suites and verify test-count parity**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/schedule-read.service.spec.ts src/crm/schedule.service.spec.ts --runInBand
```

Expected: both suites PASS and their combined test count equals the Step 1
baseline. A higher count means tests were copied; a lower count means coverage
was dropped.

- [ ] **Step 5: Run typecheck and whitespace checks**

Run:

```powershell
npm --prefix server run typecheck
git diff --check
```

Expected: both commands exit `0`.

- [ ] **Step 6: Commit the test ownership boundary**

```powershell
git add -- server/src/crm/schedule/schedule-read.service.spec.ts server/src/crm/schedule.service.spec.ts
git commit -m "test(schedule): isolate read contract coverage"
```

- [ ] **Step 7: Refresh Sentrux and RepoWise after the test boundary**

Call Sentrux `rescan`, `health`, and `check_rules`. The test-only move must keep
quality `>= 4976`, acyclicity raw `1`, and architectural rules PASS. Then run:

```powershell
repowise update --index-only
```

Verify RepoWise reports `indexed_commit` equal to the Task 1 HEAD and
`index_behind=false`. Do not interpret a test-file relocation as a production
health improvement.

---

### Task 2: Extract and directly route `ScheduleReadService`

**Files:**
- Create: `server/src/crm/schedule/schedule-read.service.ts`
- Modify: `server/src/crm/schedule/schedule-read.service.spec.ts`
- Modify: `server/src/crm/schedule.service.ts`
- Modify: `server/src/crm/crm-schedule.controller.ts`
- Modify: `server/src/crm/crm-schedule.controller.spec.ts`
- Modify: `server/src/crm/crm.service.ts`
- Modify: `server/src/crm/crm.service.spec.ts`
- Modify: `server/src/crm/student-funnel-postgres.integration.spec.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/app.module.spec.ts`

**Interfaces:**
- Consumes: `DatabaseService.query`, `CrmPolicy.assertCanReadOperationalData`, `canReadTeacherRates`, and `canReadStudentFinance`; existing `LessonQuery` and `ScheduleMatrixQuery` DTOs.
- Produces: injectable `ScheduleReadService` with `getScheduleMatrix(actor, query)`, `getScheduleMonthSummary(actor, query)`, and `listLessons(actor, query)` using the current inferred return types.

- [ ] **Step 1: Write the failing direct-routing tests**

In `crm-schedule.controller.spec.ts`, add a dedicated read mock after the
existing schedule mock and pass it as the second constructor argument:

```ts
const scheduleRead = {
  listLessons: jest.fn().mockResolvedValue({ items: [] }),
  getScheduleMatrix: jest.fn().mockResolvedValue({ items: [], groups: [] }),
  getScheduleMonthSummary: jest.fn().mockResolvedValue({ items: [] }),
};

const controller = new CrmScheduleController(
  schedule as never,
  scheduleRead as never,
  lessonCommands as never,
  lessonSeriesCommands as never,
  lessonTransitions as never,
  flags,
  schedulePlans as never,
  {} as never,
);
```

Add the ownership assertion:

```ts
it("routes schedule reads through the dedicated read service", async () => {
  const { controller: subject, scheduleRead } = controller("v4");

  await subject.listLessons(actor, { limit: 10 } as never);
  await subject.getScheduleMatrix(actor, { groupBy: "room" } as never);
  await subject.getScheduleMonthSummary(actor, {} as never);

  expect(scheduleRead.listLessons).toHaveBeenCalledWith(actor, { limit: 10 });
  expect(scheduleRead.getScheduleMatrix).toHaveBeenCalledWith(actor, {
    groupBy: "room",
  });
  expect(scheduleRead.getScheduleMonthSummary).toHaveBeenCalledWith(actor, {});
});
```

Return `scheduleRead` from the fixture. In `app.module.spec.ts`, import
`ScheduleReadService` and assert it resolves from the compiled graph:

```ts
expect(moduleRef.get(ScheduleReadService, { strict: false })).toBeDefined();
```

Retarget the Task 1 read-contract fixture to the intended owner before that
owner exists:

```ts
import { ScheduleReadService } from "./schedule-read.service";

const createService = (rows: Record<string, unknown>[] = []) => {
  const query = jest.fn().mockResolvedValue({ rows });
  const policy = {
    assertCanReadOperationalData: jest.fn(),
    canReadTeacherRates: jest.fn().mockReturnValue(false),
    canReadSchoolFinance: jest.fn().mockReturnValue(false),
    canReadStudentFinance: jest.fn().mockReturnValue(false),
  };
  const service = new ScheduleReadService(
    { query } as unknown as DatabaseService,
    policy as unknown as CrmPolicy,
  );
  return { service, query, policy };
};
```

Add the exact dependency contract before implementation:

```ts
it("depends only on database and CRM policy", () => {
  expect(Reflect.getMetadata("design:paramtypes", ScheduleReadService)).toEqual([
    DatabaseService,
    CrmPolicy,
  ]);
});
```

- [ ] **Step 2: Run the routing tests and verify RED**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/schedule-read.service.spec.ts src/crm/crm-schedule.controller.spec.ts src/app.module.spec.ts --runInBand
```

Expected: FAIL because `ScheduleReadService` does not exist,
`CrmScheduleController` has no read-service constructor dependency, and the
compiled graph cannot resolve the new owner.

- [ ] **Step 3: Create the query-only service by moving existing code**

Create `server/src/crm/schedule/schedule-read.service.ts` with this boundary:

```ts
import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { LessonQuery } from "../dto/lesson.query";
import { ScheduleMatrixQuery } from "../dto/schedule-matrix.query";
import { LessonRow, toLessonDto } from "../crm-mappers";

interface ScheduleLessonRow extends LessonRow {
  conflict_types: string[] | null;
  group_participants?: Array<{
    clientId: string;
    clientName: string | null;
  }> | null;
  room_overlap_ids?: string[] | null;
  teacher_overlap_ids?: string[] | null;
}

@Injectable()
export class ScheduleReadService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  // Move getScheduleMatrix, getScheduleMonthSummary, and listLessons here.
  // Move scheduleMatrixBounds, utcDayStart, groupScheduleItems, and
  // clientLessonAccessSql here unchanged.
}
```

Move the current bodies from `schedule.service.ts` rather than rewriting them:

```text
ScheduleLessonRow interface: current lines 52-64
getScheduleMatrix: current lines 146-400
getScheduleMonthSummary: current lines 406-452
listLessons: current lines 454-627
clientLessonAccessSql: current lines 857-958
scheduleMatrixBounds, utcDayStart, groupScheduleItems: current lines 2556-2603
```

Preserve all comments explaining authorization and money semantics. Remove the
moved type, methods, helpers, and now-unused imports from `ScheduleService`.
Do not move `getScheduleConflicts`, `queryConflicts`, any lock helper, or any
method accepting a transaction executor.

- [ ] **Step 4: Run the isolated read contract and dependency boundary**

Run from repository root:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/schedule-read.service.spec.ts --runInBand
```

Expected: PASS with every moved SQL/DTO/privacy assertion unchanged.

- [ ] **Step 5: Register the provider and route production callers directly**

In `crm.module.ts`, import and add `ScheduleReadService` beside
`ScheduleService` in `providers`:

```ts
import { ScheduleReadService } from "./schedule/schedule-read.service";

providers: [
  // existing providers
  ScheduleReadService,
  ScheduleService,
]
```

In `CrmScheduleController`, add the direct dependency and change only the three
read routes:

```ts
constructor(
  private readonly schedule: ScheduleService,
  private readonly scheduleRead: ScheduleReadService,
  // existing command dependencies stay in their current order
) {}

return this.scheduleRead.listLessons(actor, query);
return this.scheduleRead.getScheduleMatrix(actor, query);
return this.scheduleRead.getScheduleMonthSummary(actor, query);
```

In `CrmService`, replace its sole `ScheduleService` dependency with the new read
owner and update the student-card call and nearby ownership comment:

```ts
import { ScheduleReadService } from "./schedule/schedule-read.service";

private readonly scheduleRead: ScheduleReadService,

this.scheduleRead.listLessons(actor, { studentId, limit: 100 });
```

Do not add both schedule services to `CrmService`; it has no command caller.

- [ ] **Step 6: Update constructor fixtures without weakening assertions**

Update `crm-schedule.controller.spec.ts` as defined in Step 1. In
`crm.service.spec.ts`, rename the `schedule` mock to `scheduleRead`, cast it to
`ScheduleReadService`, and keep the existing `listLessons` behavior and student
card assertions. Apply the same constructor substitution in
`student-funnel-postgres.integration.spec.ts`.

The constructor fragments become:

```ts
scheduleRead as unknown as ScheduleReadService
```

No `ScheduleService` mock remains in `crm.service.spec.ts` or
`student-funnel-postgres.integration.spec.ts` after the replacement.

- [ ] **Step 7: Run focused routing, read, command, and composition tests**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/schedule-read.service.spec.ts src/crm/schedule.service.spec.ts src/crm/crm-schedule.controller.spec.ts src/crm/crm.service.spec.ts src/crm/student-funnel-postgres.integration.spec.ts src/app.module.spec.ts --runInBand
```

Expected: six suites PASS. Read assertions exercise only
`ScheduleReadService`; command/conflict/series assertions exercise only
`ScheduleService`; the compiled graph resolves both.

- [ ] **Step 8: Verify no read surface or wrong production caller remains**

Run from repository root:

```powershell
rg -n "getScheduleMatrix|getScheduleMonthSummary|listLessons" server/src/crm/schedule.service.ts
rg -n "this\.schedule\.(getScheduleMatrix|getScheduleMonthSummary|listLessons)" server/src
rg -n "ScheduleReadService" server/src/crm server/src/app.module.spec.ts
```

Expected: the first two commands return no matches. The third command shows the
new service, both production consumers, module registration, focused tests, and
app composition assertion.

- [ ] **Step 9: Run full backend verification**

```powershell
npm --prefix server run typecheck
npm --prefix server test -- --runInBand
npm --prefix server run build
git diff --check
```

Expected: typecheck and build exit `0`; all backend suites/tests PASS; diff check
is silent and exits `0`.

- [ ] **Step 10: Run Sentrux and evaluate the actual health gain**

Call Sentrux `rescan`, `health`, and `check_rules`. Acceptance:

```text
quality_signal >= 4976
acyclicity.raw = 1
rules pass = true
```

Record root metrics and do not expand into the known Flutter depth chain.

- [ ] **Step 11: Commit the direct read ownership cut**

```powershell
git add -- server/src/crm/schedule/schedule-read.service.ts server/src/crm/schedule/schedule-read.service.spec.ts server/src/crm/schedule.service.ts server/src/crm/crm-schedule.controller.ts server/src/crm/crm-schedule.controller.spec.ts server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts server/src/crm/student-funnel-postgres.integration.spec.ts server/src/crm/crm.module.ts server/src/app.module.spec.ts
git commit -m "refactor(schedule): extract read service"
```

- [ ] **Step 12: Update RepoWise and inspect the committed change**

```powershell
repowise update --index-only
```

Then call RepoWise `get_health` for both schedule services with
`include=["biomarkers", "refactoring", "trend"]`, `get_risk` for the changed
production files, and `get_change_risk` for the Task 1 base through Task 2 HEAD.
Verify `indexed_commit` equals HEAD, `index_behind=false`, no dependency cycle or
breaking consumer exists, and report before/after NLOC, weighted deficit, god
class marker, and coverage. History-based change entropy is not expected to
disappear in one refactor.

## Rollback

If Task 2 fails before its commit, keep the Task 1 characterization split and
revert only the uncommitted Task 2 files. If a regression is found immediately
after Task 2 is committed, use a normal Git revert of
`refactor(schedule): extract read service`; do not hand-edit SQL or restore a
compatibility façade. The test-only Task 1 commit remains valid in both cases.
