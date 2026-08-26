# CRM Student Service Semantic Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `CrmService` god class while preserving every controller-facing student contract, RBAC check, SQL predicate, transaction boundary, audit/realtime sequence, and fail-closed lifecycle guard.

**Architecture:** Keep `CrmService` as an internal, controller-facing compatibility facade with delegation only. Extract immutable presentation/search helpers, read and composition services, one transaction executor that owns both complete callbacks, and one student command service; no schema, endpoint, DTO, or external module contract changes.

**Tech Stack:** NestJS, TypeScript, PostgreSQL, Jest, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md`

## Global Constraints

- This is Package 10 of the approved `25 -> 0` program; the production `god_class` count must decrease from `24` to `23` on one exact indexed commit.
- Preserve every current `CrmService` public signature and both controller constructors; `CrmService` remains private to `CrmModule` and is not exported.
- Backend RBAC and resource scope remain authoritative. List/search and group-roster policy checks run before their domain queries. Individual student/group reads first load only the authorization row, then call `assertCanReadStudent` before any subsequent protected read or response.
- Keep each complete create/update transaction callback intact in one executor. Do not nest transactions or change the `PoolClient`/`DatabaseService` callback semantics.
- Preserve create ordering: lead preflight/appeal derivation -> transaction -> fallback responsible -> audit -> realtime.
- Preserve update ordering: write policy -> transaction including `FOR UPDATE` and status history -> fallback responsible -> audit diff -> realtime.
- Preserve invitation ordering: notification -> hashed-email audit. Preserve exact Russian error text for invite, delete, and return-to-lead failures.
- Preserve the finance-free legacy `getStudentCard` return shape. The production card route continues through `ClientCardReadService`; it is not redirected.
- No database schema/data mutation, endpoint/DTO change, parallel CRM runtime, direct Flutter database access, or history rewrite belongs to this package.
- Every new production owner targets health `>=7.0`, max CCN `<=10`, and no `god_class`/`brain_method`. `CrmService` targets `<=120` NLOC and max CCN `1`.
- After every structural task: focused tests, typecheck, `git diff --check`, `repowise update --index-only`, exact RepoWise health/risk, Sentrux rescan/health, and architectural rules `2/2`.
- Package acceptance requires full backend tests, build/typecheck, fresh coverage ingestion, RepoWise hard arrays empty, Sentrux quality `>=5744`, depth `<=13`, perfect acyclicity, and rules `2/2`.
- Every command shown in this plan runs from the repository root. All Node commands use `npm --prefix server`; Jest paths therefore start with `src/`.

---

### Task 1: Lock missing student contracts before movement

**Files:**
- Modify: `server/src/crm/crm.service.spec.ts`
- Modify: `server/src/crm/crm-students.controller.spec.ts`
- Create: `server/src/crm/crm-facilities.controller.spec.ts`

**Interfaces:**
- Consumes: the current `CrmService` constructor and all existing public methods.
- Produces: characterization tests that later tasks must keep green without rewriting expectations.

- [ ] **Step 1: Add a list/read characterization block**

Append tests using the existing `createService`/database stubs. Define one complete `studentRow` fixture with `id`, profile/user/source fields, names, email, phone, status, `custom_data`, teacher ids, blacklist fields, and ISO `created_at`; derive `expectedStudentDto` by spelling out the current public response. Reuse the file's existing manager `actor` and add a teacher actor. Assert all four facts, not only the returned item:

```ts
it("lists students through list policy, bounded query, and canonical DTO", async () => {
  const { service, database, policy } = createService();
  database.query.mockResolvedValueOnce({ rows: [studentRow] });

  await expect(service.listStudents(actor, { q: "  Алина  ", limit: 999 }))
    .resolves.toEqual({ items: [expectedStudentDto] });

  expect(policy.assertCanListStudents).toHaveBeenCalledWith(actor);
  expect(database.query.mock.calls[0]![1]).toEqual([
    actor.role,
    actor.userId,
    "Алина",
    100,
  ]);
});

it("reads one student only after row-level authorization", async () => {
  const { service, database, policy } = createService();
  database.query.mockResolvedValueOnce({ rows: [studentRow] });

  await expect(service.getStudent(teacherActor, studentRow.id))
    .resolves.toEqual(expectedStudentDto);

  expect(policy.assertCanReadStudent).toHaveBeenCalledWith(teacherActor, {
    profileUserId: studentRow.profile_user_id,
    teacherUserIds: studentRow.teacher_user_ids,
  });
});
```

Add a separate not-found test expecting the exact `"Ученик не найден."` message and no mapper-dependent output.

- [ ] **Step 2: Characterize search cursor and post-commit publication order**

Add a search test with `limit: 1` and two rows. Assert `items.length === 1`, `totalCount`, and exact `nextCursor` format. Add create/update ordering assertions with a shared ordered-event array:

```ts
expect(events).toEqual([
  "transaction",
  "responsible",
  "audit",
  "realtime",
]);
```

Use a dedicated event-order harness. Its transaction wrapper pushes `transaction` only after the callback resolves; its database query mock pushes `responsible` only when SQL contains both the fallback query's unique `with eligible_actor` CTE and `update app.students`; its audit and `emitCrmChanged` mocks push their labels. Return the realtime mock from the harness. This observes the real `ensureResponsibleSafe` call without confusing the main update CTE for the fallback and without mocking the module. Keep existing SQL and response assertions.

- [ ] **Step 3: Characterize facade/controller signatures**

In `crm-students.controller.spec.ts`, add one table-driven delegation test for `getMySummary`, `listStudents`, `searchStudents`, `getStudent`, `listStudentGroups`, `inviteStudent`, `deleteStudent`, and `returnStudentToLead`. The expected service method receives the same actor/id/query object by identity.

Create `crm-facilities.controller.spec.ts` with typed empty stubs for its six unrelated constructor dependencies and a `CrmService` mock. Assert `listGroupStudents(actor, id, query)` delegates the same three values by identity to `crm.listGroupStudents` and returns its result.

- [ ] **Step 4: Run the red/green contract suite**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/crm.service.spec.ts src/crm/crm-students.controller.spec.ts src/crm/crm-facilities.controller.spec.ts --runInBand
```

Expected: all suites pass. These are characterization tests against unchanged production code, so no deliberate red phase is required.

- [ ] **Step 5: Verify and commit**

Run `npm --prefix server run typecheck` and `git diff --check`, then commit:

```powershell
git add server/src/crm/crm.service.spec.ts server/src/crm/crm-students.controller.spec.ts server/src/crm/crm-facilities.controller.spec.ts
git commit -m "test(crm): characterize student service boundaries"
```

---

### Task 2: Extract immutable student presentation and search policy

**Files:**
- Create: `server/src/crm/students/student-presenter.ts`
- Create: `server/src/crm/students/student-presenter.spec.ts`
- Create: `server/src/crm/students/student-search-filter.ts`
- Create: `server/src/crm/students/student-search-filter.spec.ts`
- Modify: `server/src/crm/crm.service.ts`
- Test: `server/src/crm/crm.service.spec.ts`

**Interfaces:**
- Consumes: `StudentRow`, `ActorContext`, `StudentSearchQuery`, `resolveAppealDate`, `resolveAge`, `presentableEmail`, `buildTextSearch`, branch/role SQL helpers.
- Produces: `StudentSearchRow`, `StudentGroupRow`, `StudentSearchSqlFilter`, `toStudentDto`, `toStudentSearchDto`, `toStudentGroupDto`, `buildStudentSearchFilter`.

- [ ] **Step 1: Write pure presenter tests first**

Cover appeal-date/age precedence, hidden placeholder email, null/zero numeric conversion, search counters, disciplines/table fields, and the `teacherRate: null | 0 | number` distinction.

```ts
expect(toStudentGroupDto({ ...groupRow, teacher_rate: null }).teacherRate)
  .toBeNull();
expect(toStudentGroupDto({ ...groupRow, teacher_rate: "0" }).teacherRate)
  .toBe(0);
```

Run the new spec and confirm it fails because the module does not exist.

- [ ] **Step 2: Create `student-presenter.ts`**

Export the row interfaces currently declared in `crm.service.ts` and pure functions with these signatures:

```ts
export interface StudentSearchRow extends StudentRow {
  total_count: string | number;
  branch_id: string | null;
  branch_name: string | null;
  groups_count: string | number;
  open_tasks_count: string | number;
  lessons_count: string | number;
  payments_total: string | number | null;
  linked_user_id: string | null;
  linked_user_email: string | null;
  is_app_account: boolean | null;
  disciplines: { id: string; name: string }[] | null;
  table_custom_fields: Record<string, unknown>[] | null;
}

export interface StudentGroupRow {
  id: string;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  name: string;
  price_per_lesson: string | null;
  teacher_rate?: string | number | null;
  teacher_name: string | null;
  branch_name: string | null;
  room_name: string | null;
  created_at: Date | string;
}

export function toStudentDto(row: StudentRow);
export function toStudentSearchDto(row: StudentSearchRow);
export function toStudentGroupDto(row: StudentGroupRow);
export function toNumericStat(value: string | number | null | undefined): number;
```

Move current mapping behavior verbatim. `toStudentDto` must preserve the exact `resolveAppealDate` and `resolveAge` precedence, placeholder-email hiding, null defaults, blacklist coercion, and every current response key. `toStudentSearchDto` must spread that result and preserve all counters, link/account, discipline, and table-field defaults. `toStudentGroupDto` must preserve `null` versus numeric zero for `teacherRate`. Do not add a second DTO model; use inferred implementation return types and name them with `ReturnType<typeof ...>` only when a consumer requires a name.

- [ ] **Step 3: Write exhaustive search-filter tests**

Use table cases for `q`, status, branch, no-branch, group, discipline/level/category, date bounds, linked user true/false, no email, no open tasks, valid cursor, malformed cursor, teacher scope, and manager branch scope. Assert both SQL fragments and exact parameter order.

Run the spec and confirm it fails because the builder does not exist.

- [ ] **Step 4: Create `student-search-filter.ts`**

Expose only:

```ts
export interface StudentSearchSqlFilter {
  where: string;
  params: unknown[];
  searchRank: string | null;
}

export function buildStudentSearchFilter(
  actor: ActorContext,
  query: StudentSearchQuery,
): StudentSearchSqlFilter;
```

Internally split actor scope, text/scalar filters, activity flags, and cursor into pure helpers. Preserve parameter insertion order exactly and keep every helper at CCN `<=10`.

- [ ] **Step 5: Route `CrmService` through the pure owners**

Replace the private mapper/filter methods and row interfaces with imports. Do not move database calls yet. Remove `resolveAge`, `resolveAppealDate`, `presentableEmail`, `buildTextSearch`, branch-search helper imports only when unused.

- [ ] **Step 6: Verify, index, scan, and commit**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/students/student-presenter.spec.ts src/crm/students/student-search-filter.spec.ts src/crm/crm.service.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
repowise update --index-only
```

Run RepoWise health on both new files and `CrmService`, then Sentrux rescan/health/rules. Commit:

```powershell
git add server/src/crm/students server/src/crm/crm.service.ts
git commit -m "refactor(crm): extract student presentation policy"
```

---

### Task 3: Extract the policy-gated student directory

**Files:**
- Create: `server/src/crm/students/student-directory.service.ts`
- Create: `server/src/crm/students/student-directory.service.spec.ts`
- Modify: `server/src/crm/crm.service.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/crm/crm.service.spec.ts`
- Modify: `server/src/crm/student-funnel-postgres.integration.spec.ts`
- Test: `server/src/app.module.spec.ts`

**Interfaces:**
- Consumes: `DatabaseService`, `CrmPolicy`, `findStudent`, Task 2 filter/presenter contracts, and existing DTO/query types.
- Produces: `StudentDirectoryService.listStudents`, `searchStudents`, `getStudent`, `listStudentGroups`, and `listGroupStudents` with signatures identical to the current facade methods.

- [ ] **Step 1: Write the directory owner spec**

Move/copy the Task 1 read/search characterization into a direct `StudentDirectoryService` harness. Keep facade tests intact. For list/search/group-roster policy failures, expect zero queries. For `getStudent` and `listStudentGroups`, expect exactly one `findStudent` authorization lookup, then the policy failure, and no subsequent protected query or response.

Run the new spec and confirm it fails because the service does not exist.

- [ ] **Step 2: Implement `StudentDirectoryService`**

Move the five complete read methods and their SQL without changing predicates, grouping, order, limits, cursor encoding, or mapping. Constructor:

```ts
constructor(
  private readonly database: DatabaseService,
  private readonly policy: CrmPolicy,
) {}
```

`getStudent` and `listStudentGroups` retain `findStudent` plus `assertCanReadStudent`. `listGroupStudents` retains both `assertCanReadOperationalData` and `assertGroupBranchScope` before its query.

- [ ] **Step 3: Delegate the facade and register DI**

Inject `StudentDirectoryService` into `CrmService`. Replace only the five moved bodies with direct returns, for example:

```ts
listStudents(actor: ActorContext, query: CrmListQuery) {
  return this.directory.listStudents(actor, query);
}
```

Add `StudentDirectoryService` to `CrmModule.providers`; do not export it.

Update both `createService` factories in `crm.service.spec.ts` and the manual constructor in `student-funnel-postgres.integration.spec.ts` in this same task. Construct one real `StudentDirectoryService(database, policy)` and pass it in the new facade constructor position so typecheck never sees an intermediate broken constructor.

- [ ] **Step 4: Verify, index, scan, and commit**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/students/student-directory.service.spec.ts src/crm/crm.service.spec.ts src/crm/student-funnel-postgres.integration.spec.ts src/app.module.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
repowise update --index-only
```

Require directory health `>=7`, max CCN `<=10`, no god/brain; run Sentrux rescan/health/rules. Commit:

```powershell
git add server/src/crm/students/student-directory.service.ts server/src/crm/students/student-directory.service.spec.ts server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts server/src/crm/crm.module.ts server/src/crm/student-funnel-postgres.integration.spec.ts
git commit -m "refactor(crm): extract student directory service"
```

---

### Task 4: Extract self-summary and legacy card composition

**Files:**
- Create: `server/src/crm/students/student-self-summary.service.ts`
- Create: `server/src/crm/students/student-self-summary.service.spec.ts`
- Create: `server/src/crm/students/student-card-timeline.service.ts`
- Create: `server/src/crm/students/student-card-timeline.service.spec.ts`
- Modify: `server/src/crm/crm.service.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/crm/crm.service.spec.ts`
- Modify: `server/src/crm/student-funnel-postgres.integration.spec.ts`
- Test: `server/src/app.module.spec.ts`

**Interfaces:**
- Consumes: Task 2 presenter, Task 3 directory, `DatabaseService`, `SharedTaskService`, `ScheduleReadService`, `TimelineService`, `ChatWorkTimelineService`, and `CrmPolicy` through the directory.
- Produces: `StudentSelfSummaryService.getMySummary` and `StudentCardTimelineService.getStudentCard` with exact legacy return shapes.

- [ ] **Step 1: Write direct composition specs**

For self-summary, assert own/family/manual union order and dedup, empty-student fast path, and independent lesson/task failure fallbacks. For legacy card, retain teacher/admin finance-free expectations and assert timeline descending order across comments/tasks/lessons/chat/audit.

Run both new specs and confirm missing-module failures.

- [ ] **Step 2: Implement `StudentSelfSummaryService`**

Move `getMySummary` plus the three actor-link queries. Constructor:

```ts
constructor(
  private readonly database: DatabaseService,
  private readonly tasks: SharedTaskService,
  private readonly scheduleRead: ScheduleReadService,
) {}
```

Preserve `own -> family -> manual` dedup priority and separate `.catch(() => [])` fallbacks.

- [ ] **Step 3: Implement `StudentCardTimelineService`**

Move the legacy `getStudentCard`, user-link query, and chat timeline mapping. Constructor:

```ts
constructor(
  private readonly database: DatabaseService,
  private readonly directory: StudentDirectoryService,
  private readonly scheduleRead: ScheduleReadService,
  private readonly tasks: SharedTaskService,
  private readonly timeline: TimelineService,
  private readonly chatWork: ChatWorkTimelineService,
) {}
```

Authorize/read the student through `directory.getStudent` but retain a raw authorized row helper only if the DTO cannot satisfy the existing card response. Do not call the canonical `ClientCardReadService` and do not add commerce fields.

- [ ] **Step 4: Delegate facade methods and register both providers**

`CrmService.getMySummary` delegates to self-summary; `getStudentCard` delegates to card timeline. Remove the moved dependencies/imports from the facade. Add both providers to `CrmModule`, not `exports`.

Update both `createService` factories in `crm.service.spec.ts` and the manual constructor in `student-funnel-postgres.integration.spec.ts` in this same task. Construct real summary/card owners from the existing stubs and pass them into the facade immediately; do not leave an intermediate constructor that fails typecheck.

- [ ] **Step 5: Verify, index, scan, and commit**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/students/student-self-summary.service.spec.ts src/crm/students/student-card-timeline.service.spec.ts src/crm/crm.service.spec.ts src/crm/student-funnel-postgres.integration.spec.ts src/app.module.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
repowise update --index-only
```

Run RepoWise health on both owners and the shrinking facade, then Sentrux rescan/health/rules. Require both owners health `>=7`, max CCN `<=10`, no god/brain. Commit:

```powershell
git add server/src/crm/students server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts server/src/crm/crm.module.ts server/src/crm/student-funnel-postgres.integration.spec.ts
git commit -m "refactor(crm): extract student read composition"
```

---

### Task 5: Move complete create/update transactions into one executor

**Files:**
- Create: `server/src/crm/students/student-mutation.types.ts`
- Create: `server/src/crm/students/student-mutation.executor.ts`
- Create: `server/src/crm/students/student-mutation.executor.spec.ts`
- Modify: `server/src/crm/crm.service.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/crm/crm.service.spec.ts`
- Modify: `server/src/crm/student-funnel-postgres.integration.spec.ts`
- Test: `server/src/app.module.spec.ts`

**Interfaces:**
- Consumes: `DatabaseService`, `StudentFunnelService`, responsible eligibility helpers, typed client repository helpers, and current SQL.
- Produces: `PreparedStudentCreate`, `PreparedStudentUpdate`, `StudentWriteSnapshot`, `StudentMutationExecutor.create`, and `StudentMutationExecutor.update`.

- [ ] **Step 1: Define immutable executor commands**

Create readonly interfaces carrying already-normalized values. The executor must not receive `ActorContext` or emit audit/realtime side effects.

```ts
export interface PreparedStudentCreate {
  readonly firstName: string;
  readonly lastName: string | null;
  readonly email: string | null;
  readonly fullName: string;
  readonly phone: string | null;
  readonly status: string;
  readonly leadId: string | null;
  readonly customDataPatch: Readonly<Record<string, unknown>>;
  readonly requestedResponsibleId: string | undefined;
  readonly branchId: string | null;
  readonly sourceId: string | null;
  readonly customFields?: ReadonlyArray<TypedClientCustomValue>;
}

export interface PreparedStudentUpdate {
  readonly studentId: string;
  readonly firstName: string | null;
  readonly lastName: string | null;
  readonly phone: string | null;
  readonly email: string | null;
  readonly status: string | null;
  readonly customDataPatch: Readonly<Record<string, unknown>>;
  readonly requestedResponsibleId: string | undefined;
  readonly branchId: string | null;
  readonly clearResponsible: boolean;
  readonly sourceId: string | null;
  readonly customFields?: ReadonlyArray<TypedClientCustomValue>;
}
```

Presence is semantic: `customFields === undefined` means do not touch typed values, while `customFields: []` means call the repository with an empty array (for update this removes existing non-system values). At the mutable repository boundary pass `[...command.customFields]`; never change the existing repository API just to satisfy the readonly command.

- [ ] **Step 2: Write executor tests before implementation**

Create a `DatabaseService.transaction` harness exposing one fake client. For create assert funnel validation, advisory lock before duplicate recheck, responsible lock, insert CTE parameters, and typed-field persistence all occur inside the same callback. For update assert `FOR UPDATE` snapshot precedes funnel/source/responsible checks, the update CTE and typed-field replacement share the client, and status history is appended only after a status change.

Run and confirm missing-module failure.

- [ ] **Step 3: Implement the create callback intact**

`StudentMutationExecutor.create(command)` starts exactly one `database.transaction`. Move lines equivalent to the current `364-471` callback without moving lead preflight/appeal derivation or post-commit publication into it. Keep advisory lock and duplicate recheck order exact.

- [ ] **Step 4: Implement the update callback intact**

`StudentMutationExecutor.update(command)` starts exactly one transaction and returns `{ beforeStudent, student }`. Keep `FOR UPDATE`, funnel/branch/source/responsible validation, multi-table CTE, typed-field replacement, and append-only status history inside the same callback. Split internal paragraphs into private helpers receiving the same transaction client so every method stays CCN `<=10`; do not start nested transactions.

- [ ] **Step 5: Route current facade mutation bodies through the executor**

Keep current normalization, preflight, policy, post-commit responsible/audit/realtime, response mapping, and error conversion in `CrmService` temporarily. Replace only the two transaction bodies with executor calls. Add the executor to `CrmModule.providers`.

Update both `createService` factories in `crm.service.spec.ts` and the manual constructor in `student-funnel-postgres.integration.spec.ts` in this same task. Instantiate the executor from the existing database/funnel stubs before passing it to `CrmService`, so there is no staged broken constructor.

- [ ] **Step 6: Verify PostgreSQL semantics, index, scan, and commit**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/students/student-mutation.executor.spec.ts src/crm/crm.service.spec.ts src/crm/student-funnel-postgres.integration.spec.ts src/app.module.spec.ts --runInBand
npm --prefix server run typecheck
npm --prefix server run build
git diff --check
repowise update --index-only
```

Require executor health `>=7`, max CCN `<=10`, no god/brain; verify exactly two transaction boundaries in the executor and none in new read/pure owners. Run Sentrux rescan/health/rules. Commit:

```powershell
git add server/src/crm/students server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts server/src/crm/crm.module.ts server/src/crm/student-funnel-postgres.integration.spec.ts
git commit -m "refactor(crm): extract student mutation executor"
```

---

### Task 6: Extract student commands and reduce `CrmService` to delegation

**Files:**
- Create: `server/src/crm/students/student-command.service.ts`
- Create: `server/src/crm/students/student-command.service.spec.ts`
- Rewrite: `server/src/crm/crm.service.ts`
- Modify: `server/src/crm/crm.service.spec.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/crm/student-funnel-postgres.integration.spec.ts`
- Modify: `server/src/crm/crm-students.controller.spec.ts`
- Modify: `server/src/crm/crm-facilities.controller.spec.ts`

**Interfaces:**
- Consumes: Task 2 presenter, Task 5 executor, `DatabaseService`, `AuditService`, `CrmPolicy`, `NotificationsService`, `RealtimeBus`, and existing helpers.
- Produces: `StudentCommandService` with all five current command methods and a facade containing only twelve direct delegations.

- [ ] **Step 1: Write direct command-service specs**

Move/copy create/update/invite/delete/return characterization to a direct `StudentCommandService` harness. Preserve exact exceptions, notification/audit hashes, warning response shape, and post-commit order. Add a test that executor failure produces no fallback-responsible, audit, or realtime call.

Run and confirm missing-module failure.

- [ ] **Step 2: Implement `StudentCommandService`**

Move all remaining normalization, lead preflight/appeal derivation, policy gates, executor calls, fallback responsible handling, audit/realtime, invitation, and fail-closed lifecycle guards. Constructor:

```ts
constructor(
  private readonly database: DatabaseService,
  private readonly audit: AuditService,
  private readonly policy: CrmPolicy,
  private readonly notifications: NotificationsService,
  private readonly realtime: RealtimeBus,
  private readonly mutations: StudentMutationExecutor,
) {}
```

Use private pure preparation helpers so `createStudent` and `updateStudent` each stay CCN `<=10`. Keep `hashEmail` private and deterministic SHA-256 lowercase.

- [ ] **Step 3: Rewrite `CrmService` as a compatibility facade**

Its only constructor dependencies are:

```ts
constructor(
  private readonly directory: StudentDirectoryService,
  private readonly summary: StudentSelfSummaryService,
  private readonly cardTimeline: StudentCardTimelineService,
  private readonly commands: StudentCommandService,
) {}
```

Retain the exact twelve public signatures: `getMySummary`, `listStudents`, `searchStudents`, `createStudent`, `getStudent`, `getStudentCard`, `listStudentGroups`, `updateStudent`, `inviteStudent`, `listGroupStudents`, `deleteStudent`, and `returnStudentToLead`. Every body is one direct return; no SQL, transaction, policy, mapper, logger, notification, audit, or realtime call remains.

- [ ] **Step 4: Update construction fixtures and DI**

Add `StudentCommandService` to providers. Update both facade factories, the PostgreSQL fixture, and both controller specs in this same task to instantiate or mock the final semantic graph, but keep controller constructors typed as `CrmService`. Do not export any new owner.

- [ ] **Step 5: Run focused and graph verification**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/students/student-command.service.spec.ts src/crm/students/student-mutation.executor.spec.ts src/crm/crm.service.spec.ts src/crm/crm-students.controller.spec.ts src/crm/crm-facilities.controller.spec.ts src/crm/student-funnel-postgres.integration.spec.ts src/app.module.spec.ts --runInBand
npm --prefix server run typecheck
npm --prefix server run build
git diff --check
repowise update --index-only
```

Require command health `>=7`, facade no structural findings/`<=120` NLOC/max CCN `1`, all other new owners still `>=7`/CCN `<=10`. Run Sentrux rescan/health/rules.

- [ ] **Step 6: Commit the semantic facade cut**

```powershell
git add server/src/crm/students server/src/crm/crm.service.ts server/src/crm/crm.service.spec.ts server/src/crm/crm.module.ts server/src/crm/crm-students.controller.spec.ts server/src/crm/crm-facilities.controller.spec.ts server/src/crm/student-funnel-postgres.integration.spec.ts
git commit -m "refactor(crm): thin student service facade"
```

---

### Task 7: Add a permanent student-boundary regression guard

**Files:**
- Create: `server/src/crm/students/student-service-boundary.spec.ts`
- Test: `server/src/crm/students/*.spec.ts`

**Interfaces:**
- Consumes: final source layout and public owner names.
- Produces: structural failures if persistence, policy, transactions, or god ownership return to the facade.

- [ ] **Step 1: Write four exact structural assertions**

Read production source as text and assert:

```ts
expect(facadeNloc).toBeLessThanOrEqual(120);
expect(facade).not.toMatch(/database\.|\.transaction\(|select\s|insert\s|update\s|delete\s/i);
expect(transactionBoundaryCount(executor)).toBe(2);
expect(command).not.toMatch(/\.transaction\(/);
```

Also assert all twelve facade method names exist, all five new injectable owners are present in `CrmModule`, and none are exported. Limit the transaction-ownership scan to `crm.service.ts` plus production `server/src/crm/students/*.ts`, explicitly excluding `*.spec.ts`; inside that boundary, only `StudentMutationExecutor` may contain create/update transaction callbacks. This guard does not claim transaction ownership for unrelated CRM modules.

- [ ] **Step 2: Prove the guard catches regression**

Run the guard green. Temporarily change its in-memory source sample or threshold so one assertion fails, run it red, restore the test, and run green again. Do not edit production code for this red check.

- [ ] **Step 3: Run focused regression and commit**

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/students/student-service-boundary.spec.ts src/crm/students/student-presenter.spec.ts src/crm/students/student-search-filter.spec.ts src/crm/students/student-directory.service.spec.ts src/crm/students/student-self-summary.service.spec.ts src/crm/students/student-card-timeline.service.spec.ts src/crm/students/student-mutation.executor.spec.ts src/crm/students/student-command.service.spec.ts src/crm/crm.service.spec.ts src/crm/crm-students.controller.spec.ts src/crm/crm-facilities.controller.spec.ts src/crm/student-funnel-postgres.integration.spec.ts src/app.module.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
```

Commit:

```powershell
git add server/src/crm/students/student-service-boundary.spec.ts
git commit -m "test(crm): guard student service boundaries"
```

Then update RepoWise and run Sentrux rescan/health/rules.

---

### Task 8: Prove Package 10 and rerank Package 11

**Files:**
- Modify: `docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md`
- Modify: `docs/superpowers/plans/2026-08-26-crm-student-service-semantic-split.md`

**Interfaces:**
- Consumes: final Package 10 commit, full test/coverage evidence, RepoWise and Sentrux metrics.
- Produces: exact Package 10 acceptance record and the next ready production god owner.

- [ ] **Step 1: Run full backend gates**

Run from the repository root:

```powershell
npm --prefix server test -- --runInBand
npm --prefix server run typecheck
npm --prefix server run build
```

Record exact suites/tests, failures, durations, and Node heap exceptions. No PASS may be inferred from a prior commit.

- [ ] **Step 2: Generate and ingest fresh coverage**

Generate and ingest one fresh artifact from the repository root:

```powershell
$env:NODE_OPTIONS='--max-old-space-size=8192'
npm --prefix server test -- --coverage --runInBand
Get-Item -LiteralPath server/coverage/lcov.info | Select-Object FullName,Length,LastWriteTimeUtc
Get-FileHash -LiteralPath server/coverage/lcov.info -Algorithm SHA256
repowise coverage add server/coverage/lcov.info
```

Record the artifact byte size and SHA-256 before ingestion, then record line/branch coverage for every new owner and the facade. If the heap override is unnecessary it may still remain set for reproducibility.

- [ ] **Step 3: Update RepoWise and prove acceptance**

Run `repowise update --index-only`. Record the exact full SHA and require `index_behind=false`. Collect:

- old/new facade health, NLOC, max CCN, weighted deficit;
- every new owner health/NLOC/max CCN and god/brain status;
- production god recount `24 -> 23`;
- module/combined portfolio delta;
- `get_risk`/`get_change_risk`, hard arrays, consumers, cycles, conformance, missing tests, and security findings.

Any new owner below `7` for a live structural reason or above CCN `10` reopens the owning task.

- [ ] **Step 4: Prove Sentrux acceptance**

Run rescan, health, and rules. Require quality `>=5744`, depth `<=13`, acyclicity `10000`, rules `2/2`, and no root-cause regression from Package 10 baseline. Record exact equality/modularity/redundancy.

- [ ] **Step 5: Update evidence and rerank**

Append a Package 10 verified outcome to the master spec and a Results section here. Use full 40-character SHAs for code range, evidence commit, coverage commit, and indexed commit. Rerun the live production god filter and select Package 11 by recoverable weighted deficit plus dependency readiness; do not assume Messenger wins without the fresh scan.

- [ ] **Step 6: Verify documentation and commit**

Cross-search all recorded values against raw evidence, run `git diff --check`, and commit:

```powershell
git add docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md docs/superpowers/plans/2026-08-26-crm-student-service-semantic-split.md
git commit -m "docs(health): record CRM student split evidence"
```

Package 10 is complete only after every task review and the final whole-package review are clean. Continuous execution then starts the freshly ranked Package 11 under the same approved `25 -> 0` program.
