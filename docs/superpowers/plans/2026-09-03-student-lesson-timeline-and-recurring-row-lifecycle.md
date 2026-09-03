# Student Lesson Timeline and Recurring Row Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show one complete chronological lesson timeline in every student card and make recurring schedule rows visible, sortable, and safely removable with their future lessons.

**Architecture:** Add a student-scoped timeline query that reads the canonical lesson table independently of schedule-plan membership, then let the client card render that single paginated result below the schedule rules. Keep recurring plan history as rules plus dated exceptions, and implement row removal as a signed preview/commit command that reuses the existing plan-end cancellation and reservation release semantics.

**Tech Stack:** NestJS 11, TypeScript 5.8, PostgreSQL, Jest 30, Flutter/Dart, Riverpod, existing Magic adaptive surfaces.

**Spec:** `docs/superpowers/specs/2026-09-03-unified-student-schedule-and-settlement-policy-design.md`

## Global Constraints

- The student timeline includes manual lessons, every recurring-plan lesson, cancelled lessons, and every member of a reschedule chain exactly once.
- Historical and terminal lesson facts remain append-only; row removal only cancels eligible future unfinished lessons.
- Plan and row mutations retain expected-version, idempotency, signed preview, audit/outbox, and reservation history.
- Active open-ended rules sort first, then active finite rules by nearest end date, then one-off exceptions by nearest date, then expired rules newest first.
- UI copy is Russian; code and comments are English.
- Business validation returns typed 409/422 responses rather than generic 500 responses.

---

### Task 1: Add the canonical student lesson timeline endpoint

**Files:**
- Create: `server/src/crm/dto/student-lesson-timeline.query.ts`
- Create: `server/src/crm/schedule/student-lesson-timeline.repository.ts`
- Create: `server/src/crm/schedule/student-lesson-timeline.service.ts`
- Create: `server/src/crm/schedule/student-lesson-timeline.service.spec.ts`
- Modify: `server/src/crm/crm-schedule.controller.ts`
- Modify: `server/src/crm/crm-schedule.controller.spec.ts`
- Modify: `server/src/crm/crm.module.ts`

**Interfaces:**
- Consumes: `ActorContext`, existing CRM organization scoping, canonical `lessons`, `lesson_participants`, `schedule_series`, `schedule_plans`, subscription reservation and settlement fact projections.
- Produces: `StudentLessonTimelineService.list(actor: ActorContext, studentId: string, query: StudentLessonTimelineQuery): Promise<StudentLessonTimelinePage>`.
- HTTP: `GET /crm/students/:studentId/lesson-timeline?cursor=<opaque>&direction=previous|next&limit=24`.

- [ ] **Step 1: Write failing service tests for all lesson origins**

```ts
it("returns manual, plan, cancelled, and rescheduled lessons once", async () => {
  repository.listPage.mockResolvedValue([
    row({ id: "manual", plan_id: null, lifecycle_state: "scheduled" }),
    row({ id: "plan-a", plan_id: PLAN_A_ID, lifecycle_state: "scheduled" }),
    row({ id: "plan-b", plan_id: PLAN_B_ID, lifecycle_state: "cancelled" }),
    row({ id: "moved-from", successor_id: "moved-to", lifecycle_state: "rescheduled" }),
    row({ id: "moved-to", predecessor_id: "moved-from", lifecycle_state: "scheduled" }),
  ]);

  const page = await service.list(actor, STUDENT_ID, { limit: 24 });

  expect(page.items.map((item) => item.id)).toEqual([
    "manual", "plan-a", "plan-b", "moved-from", "moved-to",
  ]);
  expect(page.items[3].reschedule).toEqual({
    predecessorId: null,
    successorId: "moved-to",
    actionableLessonId: "moved-to",
  });
});
```

Add cases for organization scoping, deterministic `(scheduled_at, id)` paging, `hasPrevious`/`hasNext`, subscription coverage marker, and empty result.

- [ ] **Step 2: Run the focused tests and confirm the service is absent**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/student-lesson-timeline.service.spec.ts src/crm/crm-schedule.controller.spec.ts`

Expected: FAIL because the query DTO, repository, service, and route do not exist.

- [ ] **Step 3: Implement the DTO, keyset repository, and projection service**

```ts
export class StudentLessonTimelineQuery {
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9_-]+$/)
  cursor?: string;

  @IsOptional()
  @IsIn(["previous", "next"])
  direction?: "previous" | "next";

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(40)
  limit = 24;
}

export interface StudentLessonTimelineItem {
  id: string;
  version: number;
  scheduledAt: string;
  durationMinutes: number;
  lifecycleState: "scheduled" | "settlement_pending" | "successfully_completed" | "cancelled" | "rescheduled";
  student: { id: string; name: string };
  group: { id: string; name: string } | null;
  teacher: { id: string; name: string } | null;
  room: { id: string; name: string } | null;
  branch: { id: string; name: string } | null;
  origin: { kind: "manual" | "generated" | "one_off_exception"; planId: string | null; seriesId: string | null };
  settlement: { coveredBySubscription: boolean; settlementTypeKey: string | null };
  reschedule: { predecessorId: string | null; successorId: string | null; actionableLessonId: string };
}

export interface StudentLessonTimelinePage {
  items: StudentLessonTimelineItem[];
  previousCursor: string | null;
  nextCursor: string | null;
  hasPrevious: boolean;
  hasNext: boolean;
}
```

The repository query must start from student ownership/participation, join optional series/plan metadata, and aggregate the effective subscription marker without filtering by `plan_id`. Return every page in ascending `(scheduled_at, id)` order. With no cursor, center the page around the organization-local current time using the existing previous/next balancing rule so the latest history and nearest future lessons are visible together. Decode cursors inside the service and reject malformed cursors with `{ code: "STUDENT_TIMELINE_CURSOR_INVALID" }` and HTTP 422.

- [ ] **Step 4: Register the endpoint and rerun the focused slice**

```ts
@Get("students/:studentId/lesson-timeline")
studentLessonTimeline(
  @CurrentActor() actor: ActorContext,
  @Param("studentId", ParseUUIDPipe) studentId: string,
  @Query() query: StudentLessonTimelineQuery,
) {
  return this.studentLessonTimelineService.list(actor, studentId, query);
}
```

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/student-lesson-timeline.service.spec.ts src/crm/crm-schedule.controller.spec.ts; npm run typecheck`

Expected: PASS; an actor cannot read a student from another organization, and pagination never duplicates an item.

- [ ] **Step 5: Commit the canonical timeline endpoint**

```powershell
git add server/src/crm/dto/student-lesson-timeline.query.ts server/src/crm/schedule/student-lesson-timeline.repository.ts server/src/crm/schedule/student-lesson-timeline.service.ts server/src/crm/schedule/student-lesson-timeline.service.spec.ts server/src/crm/crm-schedule.controller.ts server/src/crm/crm-schedule.controller.spec.ts server/src/crm/crm.module.ts
git commit -m "feat: add canonical student lesson timeline"
```

---

### Task 2: Project recurring rule history and dated exceptions

**Files:**
- Create: `server/src/crm/schedule/schedule-plan-timeline.ts`
- Create: `server/src/crm/schedule/schedule-plan-timeline.spec.ts`
- Modify: `server/src/crm/schedule/schedule-plan.repository.ts`
- Modify: `server/src/crm/schedule/schedule-plan-query.service.ts`
- Modify: `server/src/crm/schedule/schedule-plan-services.spec.ts`
- Modify: `server/src/crm/schedule/schedule-plan.types.ts`

**Interfaces:**
- Consumes: active and retired schedule series, plan boundaries, lessons with manual resource changes, and transition predecessor/successor links.
- Produces: `buildSchedulePlanTimeline(input: SchedulePlanTimelineInput, now: Date): SchedulePlanTimelineProjection` and the fields `ruleTimeline`, `exceptions`, `sortBucket`, and `sortAt` in plan list projections.

- [ ] **Step 1: Write failing pure sorting and exception tests**

```ts
it("orders open, finite, one-off, and expired entries", () => {
  const result = buildSchedulePlanTimeline(fixture, new Date("2026-09-03T12:00:00Z"));

  expect(result.entries.map((entry) => entry.id)).toEqual([
    "open-ended",
    "finite-ending-2026-09-20",
    "finite-ending-2026-10-20",
    "exception-2026-09-04",
    "expired-2026-09-01",
    "expired-2026-08-01",
  ]);
});

it("marks a single changed teacher or room as a dated exception", () => {
  expect(buildSchedulePlanTimeline(exceptionFixture, NOW).exceptions[0]).toMatchObject({
    lessonId: EXCEPTION_LESSON_ID,
    scheduledDate: "2026-09-04",
    changedFields: ["teacherId", "roomId"],
  });
});
```

Include an assertion that a rescheduled successor is an exception even when it has no `series_id`.

- [ ] **Step 2: Run the pure and repository tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-plan-timeline.spec.ts src/crm/schedule/schedule-plan-services.spec.ts`

Expected: FAIL because historical rules and exceptions are not projected.

- [ ] **Step 3: Implement one deterministic timeline builder**

```ts
export type ScheduleRuleTimelineEntry = {
  id: string;
  kind: "recurring_rule" | "dated_exception";
  status: "active" | "expired";
  activeFrom: string;
  activeUntil: string | null;
  scheduledDate: string | null;
  teacherId: string;
  roomId: string;
  branchId: string;
  weekday: number;
  beginTime: string;
  durationMinutes: number;
  changedFields: Array<"scheduledAt" | "teacherId" | "roomId" | "branchId" | "durationMinutes">;
  sortBucket: 0 | 1 | 2 | 3;
  sortAt: string;
};
```

Assign bucket `0` to active open-ended rules, `1` to active/upcoming finite rules, `2` to future/current dated exceptions, and `3` to expired rules/exceptions. For bucket 1, `sortAt` is `activeFrom` when the range is upcoming and `activeUntil` when it is already active; for bucket 2 it is `scheduledDate`; for bucket 3 it is the range end or exception date. Sort buckets 0–2 ascending by `sortAt` with stable ID fallback; sort bucket 3 descending by `sortAt` with stable ID fallback.

- [ ] **Step 4: Extend the plan list repository without losing retired series**

Load series history and exception candidates in bounded batched queries for all returned plan IDs. Keep `rows` as the current editable definition and add `ruleTimeline` for display/history so older series never become editable current rows.

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-plan-timeline.spec.ts src/crm/schedule/schedule-plan-services.spec.ts src/crm/schedule/schedule-plan-postgres.integration.spec.ts; npm run typecheck`

Expected: PASS; two saved date ranges remain visible and a one-day teacher override appears as its own dated entry.

- [ ] **Step 5: Commit the recurring timeline projection**

```powershell
git add server/src/crm/schedule/schedule-plan-timeline.ts server/src/crm/schedule/schedule-plan-timeline.spec.ts server/src/crm/schedule/schedule-plan.repository.ts server/src/crm/schedule/schedule-plan-query.service.ts server/src/crm/schedule/schedule-plan-services.spec.ts server/src/crm/schedule/schedule-plan.types.ts
git commit -m "feat: expose recurring rule history and exceptions"
```

---

### Task 3: Add signed recurring-row removal with future lesson cancellation

**Files:**
- Create: `server/src/crm/dto/schedule-plan-row-removal.dto.ts`
- Create: `server/src/crm/schedule/future-plan-lesson-cancellation.service.ts`
- Create: `server/src/crm/schedule/schedule-plan-row-removal.service.ts`
- Create: `server/src/crm/schedule/schedule-plan-row-removal.service.spec.ts`
- Modify: `server/src/crm/schedule/schedule-plan-end.service.ts`
- Modify: `server/src/crm/schedule/schedule-plan.repository.ts`
- Modify: `server/src/crm/schedule/schedule-plan.service.ts`
- Modify: `server/src/crm/crm-schedule.controller.ts`
- Modify: `server/src/crm/crm.module.ts`

**Interfaces:**
- Consumes: existing schedule-plan preview token signer, version locks, lifecycle appender, `SubscriptionReservationService`, and the plan-end future cancellation rules.
- Produces: `previewRemoveRow(...)`, `removeRow(...)`, and two endpoints under `/crm/schedule-plans/:planId/rows/:seriesId/remove`.

- [ ] **Step 1: Write failing preview/commit tests**

```ts
it("cancels only future unfinished lessons and releases their reservations", async () => {
  const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
    expectedVersion: 4,
    effectiveFrom: "2026-09-04",
    reasonText: "Смена преподавателя",
  });

  expect(preview.impact).toEqual({
    futureUnfinishedLessons: 3,
    terminalLessonsPreserved: 2,
    changedLessonsPreserved: 1,
    activeReservationsToRelease: 3,
    endsPlan: false,
  });
});
```

Add commit tests for stale version `409 SCHEDULE_PLAN_VERSION_STALE`, invalid/expired preview token `422 SCHEDULE_PLAN_ROW_PREVIEW_INVALID`, idempotent replay, audit/outbox append, and final-row removal delegating to the complete plan-end result.

Assert the preview default date is the row start for a future row and the
organization-local current date for a current row.

- [ ] **Step 2: Run the row-removal tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-plan-row-removal.service.spec.ts`

Expected: FAIL because row removal does not exist.

- [ ] **Step 3: Extract the existing future-cancellation primitive**

```ts
export interface FuturePlanLessonCancellationInput {
  planId: string;
  seriesIds: string[];
  effectiveFrom: string;
  actorUserId: string;
  reasonText: string;
}

cancelEligible(
  client: PoolClient,
  input: FuturePlanLessonCancellationInput,
): Promise<{
  cancelledLessonIds: string[];
  releasedReservationIds: string[];
  preservedTerminalLessonIds: string[];
  preservedChangedLessonIds: string[];
}>;
```

Move the plan-end cancellation loop into this service. Eligibility is `scheduled_at >= effectiveFrom`, non-terminal state, still owned by the selected plan/series, and not detached by a manual exception. Cancellation appends lifecycle/audit facts and reservation release facts; it never deletes lesson rows.

- [ ] **Step 4: Implement signed row preview/commit and routes**

```ts
export class SchedulePlanRowRemovalPreviewDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsDateString()
  effectiveFrom!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reasonText!: string;
}

export class SchedulePlanRowRemovalCommandDto extends SchedulePlanRowRemovalPreviewDto {
  @IsString()
  @MaxLength(16_384)
  previewToken!: string;

  @Equals(true)
  confirm!: true;
}
```

Routes:

```ts
@Post("schedule-plans/:planId/rows/:seriesId/remove/preview")
@Post("schedule-plans/:planId/rows/:seriesId/remove")
```

Within one transaction: lock the plan and row, verify the signed impact fingerprint, retire the row at `effectiveFrom - 1 day`, cancel eligible future lessons, release reservations, increment plan version, append audit/outbox. When no current row remains, call the shared plan-ending transaction path and return `endsPlan: true`.

Every system-generated cancellation uses reason
`Строка постоянного расписания удалена`, settlement type `free_lesson`, zero
client duration, and teacher rule `none`. Keep the operator-entered reason as
separate audit context rather than using it as the lifecycle reason.

- [ ] **Step 5: Run backend schedule gates and commit**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-plan-row-removal.service.spec.ts src/crm/schedule/schedule-plan-services.spec.ts src/crm/schedule/schedule-plan-postgres.integration.spec.ts; npm run typecheck`

Expected: PASS; historical lessons remain readable and removed-row future reservations return to available capacity.

```powershell
git add server/src/crm/dto/schedule-plan-row-removal.dto.ts server/src/crm/schedule/future-plan-lesson-cancellation.service.ts server/src/crm/schedule/schedule-plan-row-removal.service.ts server/src/crm/schedule/schedule-plan-row-removal.service.spec.ts server/src/crm/schedule/schedule-plan-end.service.ts server/src/crm/schedule/schedule-plan.repository.ts server/src/crm/schedule/schedule-plan.service.ts server/src/crm/crm-schedule.controller.ts server/src/crm/crm.module.ts
git commit -m "feat: remove recurring rows with signed impact preview"
```

---

### Task 4: Add Flutter models and controller for the global timeline

**Files:**
- Create: `lib/core/models/student_lesson_timeline.dart`
- Create: `lib/features/crm/presentation/client_card/student_lesson_timeline_controller.dart`
- Create: `test/core/models/student_lesson_timeline_test.dart`
- Create: `test/features/schedule/student_lesson_timeline_controller_test.dart`
- Modify: `lib/core/services/magic_crm_service_schedule.dart`
- Modify: `lib/core/models/schedule_plan.dart`

**Interfaces:**
- Consumes: Task 1 `StudentLessonTimelinePage` JSON and Task 2 `ruleTimeline` JSON.
- Produces: `MagicCrmService.listStudentLessonTimeline`, immutable timeline models, and `StudentLessonTimelineController` page/load/retry methods.

- [ ] **Step 1: Write failing parsing and paging tests**

```dart
test('parses origins, coverage, and reschedule links', () {
  final item = StudentLessonTimelineItem.fromJson(timelineJson);

  expect(item.origin.kind, StudentLessonOriginKind.schedulePlan);
  expect(item.settlement.coveredBySubscription, isTrue);
  expect(item.reschedule.actionableLessonId, successorId);
});

test('paging replaces the visible page without mixing plan trays', () async {
  await controller.load();
  await controller.next();

  expect(controller.page.items.map((item) => item.id), ['lesson-25', 'lesson-26']);
  expect(service.requestedStudentIds, everyElement(STUDENT_ID));
});
```

- [ ] **Step 2: Run the focused Flutter tests**

Run: `flutter test test/core/models/student_lesson_timeline_test.dart test/features/schedule/student_lesson_timeline_controller_test.dart`

Expected: FAIL because the model, service method, and controller do not exist.

- [ ] **Step 3: Implement typed models and service call**

```dart
Future<StudentLessonTimelinePage> listStudentLessonTimeline({
  required String studentId,
  String? cursor,
  String direction = 'next',
  int limit = 24,
});
```

The controller exposes `page`, `loading`, `paging`, `error`, `load()`, `previous()`, `next()`, and `retry()`. It discards late responses after the student ID changes and keeps the previous successful page visible during a page failure.

- [ ] **Step 4: Parse the recurring rule timeline**

Add `ScheduleRuleTimelineEntry` to `schedule_plan.dart` with exact enum fallbacks that report unknown server values as parse errors in debug tests instead of silently treating them as active rules.

Run: `flutter test test/core/models/student_lesson_timeline_test.dart test/core/models/schedule_plan_test.dart test/features/schedule/student_lesson_timeline_controller_test.dart; flutter analyze`

Expected: PASS.

- [ ] **Step 5: Commit the Flutter data layer**

```powershell
git add lib/core/models/student_lesson_timeline.dart lib/core/models/schedule_plan.dart lib/core/services/magic_crm_service_schedule.dart lib/features/crm/presentation/client_card/student_lesson_timeline_controller.dart test/core/models/student_lesson_timeline_test.dart test/core/models/schedule_plan_test.dart test/features/schedule/student_lesson_timeline_controller_test.dart
git commit -m "feat: load the complete student lesson timeline"
```

---

### Task 5: Render one timeline and expose recurring-row removal

**Files:**
- Create: `lib/features/crm/presentation/client_card/schedule_plan_row_removal_flow.dart`
- Create: `test/features/schedule/schedule_plan_row_removal_flow_test.dart`
- Modify: `lib/features/crm/presentation/client_card/recurring_schedule_plan_controller.dart`
- Modify: `lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart`
- Modify: `lib/features/crm/presentation/client_card/recurring_schedule_plan_view.dart`
- Modify: `test/features/schedule/recurring_schedule_plan_section_test.dart`
- Modify: `test/features/schedule/recurring_schedule_plan_view_test.dart`
- Modify: `integration_test/recurring_plans_device_test.dart`
- Modify: `integration_test/client_calendar_device_test.dart`

**Interfaces:**
- Consumes: Task 3 row-removal preview/commit and Task 4 global timeline controller/model.
- Produces: one `Лента занятий` block per student card, sorted rule/history rows, and `Удалить строку` with explicit impact confirmation.

- [ ] **Step 1: Write failing widget tests for the unified layout**

```dart
testWidgets('shows one timeline containing manual and all plan lessons', (tester) async {
  await pumpCard(tester, plans: [planA, planB], timeline: [manual, fromA, fromB]);

  expect(find.text('Лента занятий'), findsOneWidget);
  expect(find.byKey(const Key('student-lesson-timeline')), findsOneWidget);
  expect(find.byKey(const ValueKey('schedule-plan-tray-plan-a')), findsNothing);
  expect(find.text('Разовое занятие'), findsOneWidget);
});

testWidgets('row removal displays signed impact before commit', (tester) async {
  await tester.tap(find.byKey(const ValueKey('remove-plan-row-series-a')));
  await tester.pumpAndSettle();

  expect(find.text('Будет отменено будущих занятий: 3'), findsOneWidget);
  expect(find.text('История проведённых занятий сохранится'), findsOneWidget);
});
```

Add widths 390, 768, and 1440 to prove the timeline uses the available width and never renders text one character per line.

Extend `recurring_plans_device_test.dart` with its existing fake API so it
returns one manual lesson, occurrences from two plans, a cancelled source, and
its successor from `/crm/students/student-1/lesson-timeline`. Assert one
`student-lesson-timeline`, no `schedule-plan-tray-*` widgets, successful next
page, and the signed impact text before final-row removal. Extend
`client_calendar_device_test.dart` to assert the same covered lesson has the
`Абонемент` marker in both the calendar drill-down and client timeline.

- [ ] **Step 2: Run the view and flow tests**

Run: `flutter test test/features/schedule/recurring_schedule_plan_view_test.dart test/features/schedule/recurring_schedule_plan_section_test.dart test/features/schedule/schedule_plan_row_removal_flow_test.dart`

Expected: FAIL because each plan owns a tray and row removal is absent.

- [ ] **Step 3: Replace per-plan trays with one student timeline**

Remove `_planTray` and `_FallbackLessonTray` from the rendered structure. Keep the old tray service method only as a compatibility endpoint until release reconciliation proves no client still calls it. Place `StudentLessonTimelineView` once after all schedule-plan cards; page it with global previous/next buttons and open the exact lesson by timeline ID.

For group cards, retain the group-specific plan display and use the existing group lesson list until a separate group-timeline requirement is approved; do not call a student endpoint with a group ID.

- [ ] **Step 4: Render rule history and implement the adaptive removal flow**

Each rule/exception row shows teacher, weekday/date, time, duration, range, room, and state. Current rows expose edit and delete actions. The delete action opens the existing adaptive surface, calls preview first, lists the four impact counts, requires reason text and explicit confirmation, then commits using the returned token and a fresh idempotency key.

Initialize the effective-date control from the server projection: row start for
a future row, otherwise the organization-local current date. Do not derive the
school date from the device UTC date.

Map errors exactly:

```dart
const schedulePlanRowRemovalMessages = {
  'SCHEDULE_PLAN_VERSION_STALE': 'Расписание уже изменилось. Я обновил данные — проверьте строку ещё раз.',
  'SCHEDULE_PLAN_ROW_PREVIEW_INVALID': 'Состав занятий изменился. Повторите предварительную проверку.',
  'SCHEDULE_PLAN_ROW_HAS_NO_FUTURE_BOUNDARY': 'Укажите дату, с которой строка перестаёт действовать.',
};
```

- [ ] **Step 5: Run responsive tests, analyze, and commit**

Run: `flutter test test/features/schedule/recurring_schedule_plan_view_test.dart test/features/schedule/recurring_schedule_plan_section_test.dart test/features/schedule/schedule_plan_row_removal_flow_test.dart test/features/schedule/student_lesson_timeline_controller_test.dart; flutter test integration_test/recurring_plans_device_test.dart integration_test/client_calendar_device_test.dart -d windows; flutter analyze`

Expected: PASS; the card shows every lesson in one timeline and the removed row disappears only after a successful commit.

```powershell
git add lib/features/crm/presentation/client_card/schedule_plan_row_removal_flow.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_controller.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_view.dart test/features/schedule/schedule_plan_row_removal_flow_test.dart test/features/schedule/recurring_schedule_plan_section_test.dart test/features/schedule/recurring_schedule_plan_view_test.dart integration_test/recurring_plans_device_test.dart integration_test/client_calendar_device_test.dart
git commit -m "feat: unify the client lesson timeline and row controls"
```
