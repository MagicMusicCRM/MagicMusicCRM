# Lesson Cancel and Reschedule Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cancellation and rescheduling explicit, atomic lesson workflows with correct default finances, one linear move chain, and one shared editing surface on desktop and mobile.

**Architecture:** Extend the existing signed preview/commit transition pipeline instead of adding another lesson mutation path. Rescheduling receives separate source and successor financial decisions: the source records a zero-effect move fact, while the successor keeps the editable planned settlement and current teacher-rate snapshot. A rolling-compatible DTO adapter treats the build-210 `financialDecision` field as a successor decision only, and all UI entry points open the same adaptive editor and commit through typed transition commands.

**Tech Stack:** NestJS 11, TypeScript 5.8, PostgreSQL, Jest 30, Flutter/Dart, Riverpod, existing Magic adaptive surfaces.

**Spec:** `docs/superpowers/specs/2026-09-03-unified-student-schedule-and-settlement-policy-design.md`

## Global Constraints

- Cancellation defaults to `unpaid_miss` for the client and `none` for the teacher, while still allowing an authorized operator to choose another supported settlement before confirmation.
- Rescheduling creates one successor in the same transaction, moves the active reservation, and records zero client/teacher effect on the source.
- A reschedule chain is linear: A → B → C; an action opened from A or B resolves to current actionable lesson C.
- The successor uses the rate and resource snapshots effective for its new teacher, date, and time.
- Completed-lesson correction remains append-only and auditable.
- Expected-version, idempotency, signed preview fingerprint, advisory locks, audit/outbox, and typed 409/422 responses are mandatory.

---

### Task 1: Separate source and successor financial contracts for rescheduling

**Files:**
- Modify: `server/src/crm/dto/lesson-transition.dto.ts`
- Modify: `server/src/crm/dto/lesson-financial-decision.dto.ts`
- Modify: `server/src/crm/schedule/lesson-transition.types.ts`
- Modify: `server/src/crm/schedule/lesson-transition.rules.ts`
- Modify: `server/src/crm/schedule/lesson-transition-preparation.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-preview.service.ts`
- Modify: `server/src/crm/schedule/lesson-bulk-transition.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-boundaries.spec.ts`
- Modify: `server/src/crm/schedule/lesson-transition-order.spec.ts`

**Interfaces:**
- Consumes: `LessonFinancialDecision` from the settlement-policy plan and the existing `UpsertLessonDto` successor draft.
- Produces: a transport contract where cancel/settle keep `financialDecision`, while reschedule carries `successorFinancialDecision`; the source zero decision is server-generated and never client-selectable. Build-210 `financialDecision` is accepted temporarily as an alias for the successor decision.
- Produces: `normalizeRescheduleDto(dto: LessonReschedulePreviewDto): NormalizedReschedulePreview` with resolved `sourceFinancialDecision` and `successorFinancialDecision`.

- [x] **Step 1: Write failing contract tests**

```ts
it("rejects a client-supplied source charge for reschedule", async () => {
  await expectValidation(LessonReschedulePreviewDto, {
    expectedVersion: 3,
    reasonText: "Перенос по просьбе клиента",
    sourceFinancialDecision: paidDecision,
    successor: successorDto,
    successorFinancialDecision: paidDecision,
  }).rejects.toMatchObject({ property: "sourceFinancialDecision" });
});

it("treats the build-210 financialDecision as successor-only", async () => {
  const normalized = normalizeRescheduleDto({
    expectedVersion: 3,
    reasonText: "Перенос",
    successor: successorDto,
    financialDecision: paidDecision,
  });
  expect(normalized.successorFinancialDecision).toEqual(paidDecision);
  expect(normalized.sourceFinancialDecision.teacherCompensationRuleKey).toBe("none");
});

it("prepares a server-owned zero source and editable successor", async () => {
  const prepared = await preparation.prepareReschedule(actor, source, dto);

  expect(prepared.sourceFinancialDecision).toMatchObject({
    settlementTypeKey: "free_lesson",
    teacherCompensationRuleKey: "none",
  });
  expect(prepared.successorFinancialDecision).toEqual(dto.successorFinancialDecision);
});
```

Also assert that partial successor decisions retain `chargeDurationMinutes` and `teacherCreditedDurationMinutes`.

- [x] **Step 2: Run the transition contract tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts`

Expected: FAIL because reschedule currently reuses one `financialDecision` for both source settlement and successor planning.

- [x] **Step 3: Split the DTO and internal types**

```ts
export class LessonReschedulePreviewDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  expectedVersion!: number;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{1,120}$/)
  reasonCode?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reasonText!: string;

  @ValidateNested()
  @Type(() => UpsertLessonDto)
  successor!: UpsertLessonDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  successorFinancialDecision?: ConfiguredLessonFinancialDecisionDto;

  /** Build 210 compatibility alias; normalized as successor-only. */
  @IsOptional()
  @ValidateNested()
  @Type(() => ConfiguredLessonFinancialDecisionDto)
  financialDecision?: ConfiguredLessonFinancialDecisionDto;
}
```

Define the internal result once:

```ts
export interface PreparedRescheduleFinancials {
  sourceFinancialDecision: LessonFinancialDecision;
  successorFinancialDecision: LessonFinancialDecision;
}
```

`TransitionPreviewDto` becomes a discriminated union keyed by `operation`; only cancel/settle variants expose `financialDecision`. This prevents accidental source reuse at compile time.

Normalization requires one of the two successor-decision fields. If both are
present and their canonical hashes differ, return HTTP 422 with
`LESSON_RESCHEDULE_DECISION_AMBIGUOUS`. Apply the same discriminated contract
to each `LessonBulkTransitionItemDto`: reschedule items use
`successorFinancialDecision` or the legacy successor alias; cancel/settle
items use `financialDecision`. Return both resolved decisions in committed
reschedule projections instead of a single ambiguous `financialDecision`.

- [x] **Step 4: Update preview fingerprints and projections**

The signed reschedule fingerprint includes both resolved decisions, successor draft, source version, reservation coverage snapshot, and calculated financial projections. The preview response exposes `sourceFinancialPreview` and `successorPlannedSettlementPreview` with Russian-safe labels; it never accepts or echoes a source decision from the client.

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts; npm run typecheck`

Expected: PASS.

- [x] **Step 5: Commit the split transition contract**

```powershell
git add server/src/crm/dto/lesson-transition.dto.ts server/src/crm/dto/lesson-financial-decision.dto.ts server/src/crm/schedule/lesson-transition.types.ts server/src/crm/schedule/lesson-transition.rules.ts server/src/crm/schedule/lesson-transition-preparation.service.ts server/src/crm/schedule/lesson-transition-preview.service.ts server/src/crm/schedule/lesson-bulk-transition.service.ts server/src/crm/schedule/lesson-transition-boundaries.spec.ts server/src/crm/schedule/lesson-transition-order.spec.ts
git commit -m "refactor: separate reschedule source and successor finances"
```

---

### Task 2: Commit a reschedule with zero source effect and inherited successor plan

**Files:**
- Modify: `server/src/crm/schedule/lesson-transition-financial.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-commit.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-command.service.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-execution.ts`
- Modify: `server/src/crm/schedule/lesson-transition-order.spec.ts`
- Modify: `server/src/crm/schedule/reschedule-postgres.integration.spec.ts`
- Modify: `server/src/crm/commerce/subscription-reservation.service.spec.ts`

**Interfaces:**
- Consumes: Task 1 `PreparedRescheduleFinancials` and existing transaction context.
- Produces: `commitRescheduleFinancials(client, source, successorId, financials)` that records a zero source fact, writes the successor planned decision, and transfers reservation ownership once.

- [ ] **Step 1: Write failing PostgreSQL assertions for no double charge**

```ts
it("moves a covered lesson without consuming twice", async () => {
  const moved = await transitions.reschedule(actor, sourceId, command, metadata);

  const facts = await readEffectiveFacts([sourceId, moved.successor!.id]);
  expect(facts.client).toEqual([
    expect.objectContaining({ lessonId: sourceId, amountMinor: 0, durationShareBasisPoints: 0 }),
  ]);
  expect(facts.teacher).toContainEqual(
    expect.objectContaining({ lessonId: sourceId, amountMinor: 0, compensationType: "none" }),
  );
  expect(await activeReservationLessonIds(subscriptionId)).toEqual([moved.successor!.id]);
  expect(await plannedDecision(moved.successor!.id)).toEqual(command.successorFinancialDecision);
});
```

Add cases for personal-account funding, partial duration, a changed teacher using the new teacher’s effective rate, and idempotent replay returning the same successor ID.

Add a completed-source case proving that the existing correction reverses the
effective client/teacher facts append-only before the zero-effect source move
and successor plan are committed.

- [ ] **Step 2: Run financial and reschedule integration tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/reschedule-postgres.integration.spec.ts src/crm/schedule/lesson-transition-order.spec.ts src/crm/commerce/subscription-reservation.service.spec.ts`

Expected: FAIL because the existing command applies the same decision during source transition and successor planning.

- [ ] **Step 3: Implement the two-phase financial write inside one transaction**

```ts
export interface CommittedRescheduleFinancials {
  sourceSettlement: LessonSettlementResult;
  successorPlanId: string;
  transferredReservationId: string | null;
}

async commitRescheduleFinancials(
  client: PoolClient,
  source: TransitionSource,
  successorId: string,
  financials: PreparedRescheduleFinancials,
): Promise<CommittedRescheduleFinancials>;
```

Order the transaction as: lock source and relevant resources, validate successor, insert successor with `predecessor_id`, write successor snapshot, settle/reverse source to zero-effect append-only facts, write successor planned settlement, transfer/recreate the active reservation against successor, append source lifecycle `rescheduled`, enqueue source/successor outbox records, commit. Any failure rolls back all steps.

- [ ] **Step 4: Resolve the successor’s current teacher rate**

Call the existing teacher-rate resolver using successor `teacherId` and `scheduledAt`. Store its rule/rate snapshot in the successor plan; never copy the source teacher amount when the teacher or effective date changed. Explicit operator overrides still require the existing teacher-compensation capability and reason.

Resolve `successorFinancialDecision` through
`LessonSettlementService.resolvePlannedDecision` with the actor authorization,
reason, new duration, new branch, and the newly resolved teacher-rate snapshot.
Generate the source zero decision inside the transition service; never pass it
through the user-override path.

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/reschedule-postgres.integration.spec.ts src/crm/schedule/lesson-transition-order.spec.ts src/crm/commerce/subscription-reservation.service.spec.ts src/crm/commerce/lesson-settlement-postgres.integration.spec.ts; npm run typecheck`

Expected: PASS; one subscription unit is reserved before and after the move, and only the eventual completed successor consumes it.

- [ ] **Step 5: Commit atomic reschedule finances**

```powershell
git add server/src/crm/schedule/lesson-transition-financial.service.ts server/src/crm/schedule/lesson-transition-commit.service.ts server/src/crm/schedule/lesson-transition-command.service.ts server/src/crm/commerce/lesson-settlement-execution.ts server/src/crm/schedule/lesson-transition-order.spec.ts server/src/crm/schedule/reschedule-postgres.integration.spec.ts server/src/crm/commerce/subscription-reservation.service.spec.ts
git commit -m "fix: move lesson finances and reservation atomically"
```

---

### Task 3: Resolve every reschedule-chain action to the current lesson

**Files:**
- Create: `server/src/crm/schedule/lesson-actionable-chain.service.ts`
- Create: `server/src/crm/schedule/lesson-actionable-chain.service.spec.ts`
- Modify: `server/src/crm/schedule/lesson-lifecycle.repository.ts`
- Modify: `server/src/crm/schedule/lesson-transition.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-preview.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-command.service.ts`
- Modify: `server/src/crm/schedule/lesson-schema-postgres.integration.spec.ts`
- Modify: `server/src/crm/crm.module.ts`

**Interfaces:**
- Consumes: unique predecessor/successor constraints from migration `0083_lesson_lifecycle_schema.up.sql`.
- Produces: `LessonActionableChainService.resolve(actor, lessonId, client?): Promise<LessonActionableResolution>`.

- [ ] **Step 1: Write failing A → B → C resolution tests**

```ts
it.each(["lesson-a", "lesson-b", "lesson-c"])(
  "resolves %s to lesson-c",
  async (openedLessonId) => {
    await expect(service.resolve(actor, openedLessonId)).resolves.toMatchObject({
      requestedLessonId: openedLessonId,
      actionableLessonId: "lesson-c",
      chainIds: ["lesson-a", "lesson-b", "lesson-c"],
    });
  },
);
```

Add cycle/overlong-chain defense returning `422 LESSON_RESCHEDULE_CHAIN_INVALID`, cross-organization denial, deleted successor handling, and concurrent second reschedule returning `409 LESSON_VERSION_STALE` or `409 LESSON_ALREADY_RESCHEDULED`.

- [ ] **Step 2: Run chain and schema tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/lesson-actionable-chain.service.spec.ts src/crm/schedule/lesson-schema-postgres.integration.spec.ts`

Expected: FAIL because the current transition services only load the requested lesson.

- [ ] **Step 3: Implement bounded chain resolution**

```ts
export interface LessonActionableResolution {
  requestedLessonId: string;
  actionableLessonId: string;
  chainIds: string[];
  redirected: boolean;
}
```

Use one recursive CTE scoped to the actor’s organization, cap depth at 64, require every forward link to point back through `predecessor_id`, and reject cycles or forks as invalid data. The final node is actionable unless terminal without successor.

- [ ] **Step 4: Resolve before preview and revalidate under commit lock**

Preview responses include `requestedLessonId`, `actionableLessonId`, and `redirected`. Commit resolves again inside the transaction before checking expected version and signed fingerprint, preventing a new successor from racing between preview and commit.

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/lesson-actionable-chain.service.spec.ts src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/reschedule-postgres.integration.spec.ts; npm run typecheck`

Expected: PASS.

- [ ] **Step 5: Commit actionable-chain routing**

```powershell
git add server/src/crm/schedule/lesson-actionable-chain.service.ts server/src/crm/schedule/lesson-actionable-chain.service.spec.ts server/src/crm/schedule/lesson-lifecycle.repository.ts server/src/crm/schedule/lesson-transition.service.ts server/src/crm/schedule/lesson-transition-preview.service.ts server/src/crm/schedule/lesson-transition-command.service.ts server/src/crm/schedule/lesson-schema-postgres.integration.spec.ts server/src/crm/crm.module.ts
git commit -m "feat: route lesson actions through reschedule chains"
```

---

### Task 4: Apply cancellation defaults and explicit visual states

**Files:**
- Modify: `server/src/crm/schedule/lesson-transition-preparation.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-financial.service.ts`
- Modify: `server/src/crm/schedule/lesson-transition-boundaries.spec.ts`
- Modify: `server/src/crm/schedule/lesson-transition-order.spec.ts`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_controller.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_form.dart`
- Modify: `test/features/schedule/lesson_decision_flow_test.dart`
- Modify: `test/features/schedule/lesson_decision_models_test.dart`

**Interfaces:**
- Consumes: `resolveSettlementPolicy("unpaid_miss")` and the one-time autofill helper from the settlement-policy plan.
- Produces: cancellation preview initialized to zero client/teacher duration, editable settlement selection, and stable markers `cancelled`/`rescheduled` for all schedule views.

- [ ] **Step 1: Write failing default and override tests**

```dart
test('cancel opens with unpaid miss and no teacher payment', () {
  final draft = LessonDecisionDraft.forCancel(catalog: catalog, lesson: lesson);

  expect(draft.settlementTypeKey, 'unpaid_miss');
  expect(draft.teacherCompensationRuleKey, 'none');
  expect(draft.clientDecisions.single.chargeDurationMinutes, 0);
  expect(draft.teacherCreditedDurationMinutes, 0);
});

test('paid miss autofills full client and teacher durations once', () {
  final changed = reducer.selectSettlementType(state, 'paid_miss');

  expect(changed.clientDecisions.single.chargeDurationMinutes, 60);
  expect(changed.teacherCreditedDurationMinutes, 60);
  expect(changed.teacherCompensationRuleKey, 'standard');
});
```

Add backend assertions for released room/teacher occupancy and reservation disposition: unpaid cancellation releases the reservation and the existing allocator offers that capacity to the next eligible scheduled lesson; paid cancellation settles it according to the chosen type without allocating another unit.

Add a group case proving whole-group cancellation creates one zero teacher
fact, while a paid or partial absence for one participant changes only that
participant's client fact and leaves the lesson-level teacher decision intact.

- [ ] **Step 2: Run cancellation policy tests**

Run: `flutter test test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_decision_models_test.dart; cd server; npm test -- --runTestsByPath src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts`

Expected: FAIL on current manually inherited defaults.

- [ ] **Step 3: Resolve defaults on server and mirror them in Flutter**

The server remains authoritative when the client omits a recommendation revision or sends an obsolete one. The form applies the catalog recommendation once, then preserves every user-touched field. Switching type after manual edits prompts `Применить рекомендованные значения для нового типа?`; declining keeps the edits and still allows preview validation.

- [ ] **Step 4: Normalize lesson markers and copy**

Use one mapping in all lesson cards/details:

```dart
const lessonLifecyclePresentation = {
  'scheduled': LessonLifecycleStyle(label: 'Забронировано', semantic: LessonSemantic.reserved),
  'successfully_completed': LessonLifecycleStyle(label: 'Завершено', semantic: LessonSemantic.completed),
  'cancelled': LessonLifecycleStyle(label: 'Отменено', semantic: LessonSemantic.cancelled),
  'rescheduled': LessonLifecycleStyle(label: 'Перенесено', semantic: LessonSemantic.rescheduled),
  'settlement_pending': LessonLifecycleStyle(label: 'Нужно проверить расчёт', semantic: LessonSemantic.warning),
};
```

Cancelled cards use the existing semantic red token. Rescheduled source cards show a neutral move marker and link to the current lesson. Subscription coverage remains a separate green subscription badge and does not replace lifecycle color.

Run: `flutter test test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_decision_models_test.dart test/features/schedule/recurring_schedule_plan_view_test.dart; cd server; npm test -- --runTestsByPath src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts`

Expected: PASS.

- [ ] **Step 5: Commit cancellation defaults and status mapping**

```powershell
git add server/src/crm/schedule/lesson-transition-preparation.service.ts server/src/crm/schedule/lesson-transition-financial.service.ts server/src/crm/schedule/lesson-transition-boundaries.spec.ts server/src/crm/schedule/lesson-transition-order.spec.ts lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_controller.dart lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_form.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_decision_models_test.dart
git commit -m "feat: normalize lesson cancellation decisions"
```

---

### Task 5: Use one adaptive editor for edit, move, and cancel actions

**Files:**
- Modify: `lib/features/admin/presentation/widgets/lesson_details_sheet.dart`
- Modify: `lib/features/admin/presentation/widgets/schedule_widget_actions.dart`
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision_flow.dart`
- Modify: `lib/core/services/magic_crm_service_schedule.dart`
- Modify: `lib/core/theme/lesson_state_palette.dart`
- Modify: `test/features/admin/lesson_editor_decision_policy_test.dart`
- Modify: `test/features/admin/lesson_editor_save_flow_test.dart`
- Modify: `test/features/schedule/lesson_decision_flow_test.dart`
- Modify: `test/features/schedule/lesson_state_palette_test.dart`
- Modify: `test/features/schedule/client_schedule_calendar_test.dart`
- Modify: `integration_test/lesson_settlement_device_test.dart`
- Modify: `integration_test/modal_device_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4 transition responses and the shared `showMagicAdaptiveSurface` implementation.
- Produces: a single editor that chooses ordinary edit or reschedule from the changed fields, plus an explicit cancel action using the same financial section and preview confirmation.

- [ ] **Step 1: Write failing routing and responsive tests**

```dart
test('date or time change routes through reschedule', () {
  final request = policy.editRequest(session: session, draft: movedDraft);

  expect(request.operation, LessonDecisionOperation.reschedule);
  expect(request.successorFinancialDecision, movedDraft.financialDecision);
});

test('teacher-only change keeps the same lesson id and uses ordinary edit', () {
  final request = policy.editRequest(session: session, draft: teacherDraft);

  expect(request.operation, LessonDecisionOperation.edit);
  expect(request.lessonId, existingLessonId);
});
```

Add widget widths 390 and 1440: on desktop the editor is a centered rounded dialog matching `Новое занятие`; on phone it is a bottom sheet with drag handle, scroll, close button, swipe-to-close when the form is clean, and a discard confirmation when dirty. Add a completed-lesson move case that displays the append-only reversal warning before preview confirmation.

Extend `lesson_settlement_device_test.dart` to record distinct source and
successor decisions, assert an unpaid cancellation submits zero/none, and
assert a move retains one subscription reservation in the fake API state.
Extend `modal_device_test.dart` so `Изменить занятие`, `Перенести`, and
`Отменить занятие` all open the shared adaptive editor, the completed move
warning is visible, and no `Изменить расчёт` button is rendered.

- [ ] **Step 2: Run editor and decision tests**

Run: `flutter test test/features/admin/lesson_editor_decision_policy_test.dart test/features/admin/lesson_editor_save_flow_test.dart test/features/schedule/lesson_decision_flow_test.dart`

Expected: FAIL because reschedule still expects the shared decision field and the entry points do not resolve chain redirects.

- [ ] **Step 3: Route all entry points through one editor**

The lesson quick view exposes `Изменить занятие`, `Перенести`, and `Отменить занятие`. The first two open the same `CreateLessonDialog.show(context, lesson: actionableLesson)` adaptive editor; `Перенести` focuses the date/time section, date/time changes commit reschedule, resource-only changes update the actionable lesson, and the financial section remains in the same form. The third opens the same adaptive surface in cancellation mode with the cancellation defaults from Task 4. Remove any separate `Изменить расчёт` action while retaining settlement history as read-only context.

Both the general calendar and student timeline pass the same effective marker
projection into `lessonStateProjection`. The subscription badge stays green
for a covered scheduled lesson in both places, while lifecycle color remains
reserved/completed/cancelled/rescheduled independently.

- [ ] **Step 4: Map typed server failures to actionable Russian messages**

```dart
const lessonTransitionErrorMessages = {
  'LESSON_VERSION_STALE': 'Занятие уже изменилось. Я открыл актуальную версию.',
  'LESSON_ALREADY_RESCHEDULED': 'Это занятие уже перенесено. Я открыл последнее занятие в цепочке.',
  'LESSON_RESCHEDULE_CHAIN_INVALID': 'Цепочка переносов повреждена. Изменения не сохранены; обратитесь администратору.',
  'LESSON_TRANSITION_PREVIEW_STALE': 'Расписание или расчёт изменились. Проверьте обновлённый предварительный расчёт.',
  'LESSON_PARTIAL_DURATION_REQUIRED': 'Укажите часы списания клиента и начисления преподавателю.',
};
```

On redirect, reload the actionable lesson, update the form version, and require a new preview. Preserve typed 409/422 codes in `MagicApiError`; never replace them with `Сервис временно недоступен`.

- [ ] **Step 5: Run the complete transition slice and commit**

Run: `flutter test test/features/admin/lesson_editor_decision_policy_test.dart test/features/admin/lesson_editor_save_flow_test.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/recurring_schedule_plan_view_test.dart test/features/schedule/lesson_state_palette_test.dart test/features/schedule/client_schedule_calendar_test.dart; flutter test integration_test/lesson_settlement_device_test.dart integration_test/modal_device_test.dart -d windows; flutter analyze; cd server; npm test -- --runTestsByPath src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts src/crm/schedule/lesson-actionable-chain.service.spec.ts src/crm/schedule/reschedule-postgres.integration.spec.ts; npm run typecheck`

Expected: PASS; actions from A or B edit C, moving a lesson consumes no extra subscription unit, and cancellation defaults to zero/none.

```powershell
git add lib/features/admin/presentation/widgets/lesson_details_sheet.dart lib/features/admin/presentation/widgets/schedule_widget_actions.dart lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart lib/features/admin/presentation/widgets/lesson_decision_flow.dart lib/core/services/magic_crm_service_schedule.dart lib/core/theme/lesson_state_palette.dart test/features/admin/lesson_editor_decision_policy_test.dart test/features/admin/lesson_editor_save_flow_test.dart test/features/schedule/lesson_decision_flow_test.dart test/features/schedule/lesson_state_palette_test.dart test/features/schedule/client_schedule_calendar_test.dart integration_test/lesson_settlement_device_test.dart integration_test/modal_device_test.dart
git commit -m "feat: unify lesson edit cancel and reschedule flows"
```
