# Settlement Policy and Partial Durations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every lesson workflow use one server-owned settlement autofill policy, support independent partial client and teacher durations, hide policy catalogs from users, and report credited teacher hours correctly.

**Architecture:** Extend the existing revisioned settlement catalog and `LessonFinancialDecision`; do not introduce a second payment or payroll model. The server resolves recommendations and exact shares, Flutter consumes catalog metadata and tracks only form-session manual state, and existing settlement facts remain the source for analytics.

**Tech Stack:** NestJS 11, TypeScript 5.8, PostgreSQL, Jest 30, Flutter/Dart, Riverpod, existing Magic adaptive surfaces.

**Spec:** `docs/superpowers/specs/2026-09-03-unified-student-schedule-and-settlement-policy-design.md`

## Global Constraints

- Preserve transaction, expected-version, idempotency, audit/outbox, and append-only settlement facts.
- Keep UI copy Russian and code/comments English.
- Manual teacher compensation requires the existing compensation permission and a business reason.
- Historical configuration revisions and terminal lesson facts remain unchanged.
- `penalty_lesson` is unavailable for new decisions but remains readable in history.
- Business validation returns typed 409/422 responses rather than generic 500 responses.

---

### Task 1: Add system-owned settlement policy metadata

**Files:**
- Create: `server/src/crm/commerce/lesson-settlement-policy.ts`
- Create: `server/src/crm/commerce/lesson-settlement-policy.spec.ts`
- Modify: `server/src/crm/crm-configuration.contracts.ts`
- Modify: `server/src/crm/crm-configuration-baseline.ts`
- Modify: `server/src/crm/crm-configuration-snapshot-normalizer.ts`
- Modify: `server/src/crm/crm-configuration-snapshot-normalizer.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-catalog.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-catalog.spec.ts`

**Interfaces:**
- Produces: `SettlementDurationMode = "zero" | "full" | "manual"`.
- Produces: `resolveSettlementPolicy(catalog, settlementTypeKey): ResolvedSettlementPolicy`.
- Produces catalog fields `clientDurationMode`, `teacherDurationMode`, and `defaultTeacherCompensationRuleKey`.

- [ ] **Step 1: Write failing policy and normalization tests**

```ts
expect(resolveSettlementPolicy(catalog, "paid_miss")).toEqual({
  clientDurationMode: "full",
  teacherDurationMode: "full",
  teacherCompensationRuleKey: "standard",
});
expect(resolveSettlementPolicy(catalog, "partially_paid_miss")).toEqual({
  clientDurationMode: "manual",
  teacherDurationMode: "manual",
  teacherCompensationRuleKey: "percent",
});
expect(resolveSettlementPolicy(catalog, "unpaid_miss")).toEqual({
  clientDurationMode: "zero",
  teacherDurationMode: "zero",
  teacherCompensationRuleKey: "none",
});
expect(catalog.settlement_types.find(row => row.stableKey === "penalty_lesson")?.active).toBe(false);
```

- [ ] **Step 2: Run the focused tests and confirm the new fields are missing**

Run: `cd server; npm test -- --runTestsByPath src/crm/commerce/lesson-settlement-policy.spec.ts src/crm/crm-configuration-snapshot-normalizer.spec.ts src/crm/commerce/lesson-settlement-catalog.spec.ts`

Expected: FAIL because `resolveSettlementPolicy` and the three metadata fields do not exist.

- [ ] **Step 3: Implement the catalog contract and pure resolver**

```ts
export type SettlementDurationMode = "zero" | "full" | "manual";

export interface ResolvedSettlementPolicy {
  clientDurationMode: SettlementDurationMode;
  teacherDurationMode: SettlementDurationMode;
  teacherCompensationRuleKey: string;
}

export function resolveSettlementPolicy(
  catalog: LessonSettlementCatalog,
  settlementTypeKey: string,
): ResolvedSettlementPolicy {
  const type = catalog.settlement_types.find(
    item => item.active && item.stableKey === settlementTypeKey,
  );
  if (!type) invalidLessonSettlementDecision(
    "SETTLEMENT_TYPE_NOT_ALLOWED",
    "settlementTypeKey",
  );
  return {
    clientDurationMode: type.clientDurationMode,
    teacherDurationMode: type.teacherDurationMode,
    teacherCompensationRuleKey: type.defaultTeacherCompensationRuleKey,
  };
}
```

Set the baseline matrix exactly as approved: `lesson` and `paid_miss` full/standard; `free_lesson` and `unpaid_miss` zero/none; both partial types manual/percent; `penalty_lesson.active = false`.

- [ ] **Step 4: Run focused tests and typecheck**

Run: `cd server; npm test -- --runTestsByPath src/crm/commerce/lesson-settlement-policy.spec.ts src/crm/crm-configuration-snapshot-normalizer.spec.ts src/crm/commerce/lesson-settlement-catalog.spec.ts; npm run typecheck`

Expected: PASS.

- [ ] **Step 5: Commit the policy metadata**

```powershell
git add server/src/crm/commerce/lesson-settlement-policy.ts server/src/crm/commerce/lesson-settlement-policy.spec.ts server/src/crm/crm-configuration.contracts.ts server/src/crm/crm-configuration-baseline.ts server/src/crm/crm-configuration-snapshot-normalizer.ts server/src/crm/crm-configuration-snapshot-normalizer.spec.ts server/src/crm/commerce/lesson-settlement-catalog.ts server/src/crm/commerce/lesson-settlement-catalog.spec.ts
git commit -m "feat: define lesson settlement autofill policy"
```

### Task 2: Extend the financial decision with exact partial durations

**Files:**
- Modify: `server/src/crm/dto/lesson-financial-decision.dto.ts`
- Modify: `server/src/crm/dto/lesson-financial-decision.dto.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.port.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.calculation.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.calculation.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-execution.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-execution.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-plan.persistence.ts`
- Modify: `server/src/crm/commerce/lesson-settlement-plan.persistence.spec.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.service.ts`
- Create: `server/src/crm/commerce/lesson-settlement.service.spec.ts`
- Modify: `server/src/crm/schedule/lesson-write-command.service.ts`
- Modify: `server/src/crm/schedule/lesson-planned-settlement-command.service.ts`
- Modify: `server/src/crm/schedule/lesson-settlement-correction.service.ts`
- Modify: `server/src/crm/schedule/lesson-compensation-rbac.spec.ts`
- Modify: `server/src/crm/schedule/lesson-write-parity.integration.spec.ts`

**Interfaces:**
- Consumes: `resolveSettlementPolicy` from Task 1.
- Produces: `LessonClientFinancialDecision.chargeDurationMinutes?: number`.
- Produces: `LessonFinancialDecision.teacherCreditedDurationMinutes?: number` and `teacherCompensationSource?: "automatic" | "manual"`.
- Produces: `durationShareBasisPoints(selectedMinutes, durationMinutes): number`.
- Produces: `LessonSettlementService.resolvePlannedDecision(client, input): Promise<LessonFinancialDecision>` as the only server entry for user-supplied planned decisions.
- Uses: `type TeacherCompensationMutationAuthorization = ReturnType<CrmPolicy["teacherCompensationMutationAuthorization"]>` so permission evaluation stays in the existing policy.

- [ ] **Step 1: Write failing DTO and calculation tests**

```ts
expect(durationShareBasisPoints(30, 60)).toBe(5_000);
expect(durationShareBasisPoints(45, 60)).toBe(7_500);
expect(() => durationShareBasisPoints(61, 60)).toThrow(
  expect.objectContaining({ code: "PARTIAL_DURATION_EXCEEDS_LESSON" }),
);

expect(await validateDecision({
  settlementTypeKey: "partially_paid_lesson",
  teacherCompensationRuleKey: "percent",
  teacherCreditedDurationMinutes: 45,
  clientDecisions: [{ clientId, chargeDurationMinutes: 30 }],
})).toHaveLength(0);
```

Use a table for lesson durations 30, 45, 60, and 90 minutes. Cover zero,
full, and manual boundaries for subscription and personal-account funding,
including client and teacher minutes that differ.

Add RBAC cases where an admin without teacher-compensation permission sends a
manual source, changed rule, changed credited minutes, or changed amount. Each
request must fail before persistence. A permitted manual override without a
business reason returns `422 TEACHER_COMPENSATION_REASON_REQUIRED`.

Add creation and edit integration cases proving an ordinary `lesson` and
`paid_miss` become automatic `standard`, while `free_lesson` and
`unpaid_miss` become automatic `none` even when a stale build-210 client sends
its old default.

- [ ] **Step 2: Run tests and verify they fail on unknown DTO fields**

Run: `cd server; npm test -- --runTestsByPath src/crm/dto/lesson-financial-decision.dto.spec.ts src/crm/commerce/lesson-settlement.calculation.spec.ts src/crm/commerce/lesson-settlement-execution.spec.ts`

Expected: FAIL because partial duration fields and validation do not exist.

- [ ] **Step 3: Implement decision normalization and exact calculations**

```ts
export function durationShareBasisPoints(
  selectedMinutes: number,
  durationMinutes: number,
): number {
  if (!Number.isInteger(selectedMinutes) || selectedMinutes < 0) {
    throw new LessonSettlementCalculationError("INVALID_PARTIAL_DURATION");
  }
  if (selectedMinutes > durationMinutes) {
    throw new LessonSettlementCalculationError(
      "PARTIAL_DURATION_EXCEEDS_LESSON",
    );
  }
  return Number(
    (BigInt(selectedMinutes) * 10_000n + BigInt(durationMinutes / 2)) /
      BigInt(durationMinutes),
  );
}
```

Resolve zero/full/manual modes on the server. For manual client decisions use
`chargeDurationMinutes`; for manual teacher duration derive the existing
percent override. Persist the exact minutes and source in the settlement-plan
JSON so reopening the lesson does not infer operator intent.

Use the resulting basis points for both subscription units and the existing
personal-account base amount, with the current integer-minor-unit rounding
rule. Client and teacher basis points are calculated independently.

Add the central resolver:

```ts
resolvePlannedDecision(
  client: PoolClient,
  input: {
    branchId: string;
    durationMinutes: number;
    decision: LessonFinancialDecision;
    actorUserId: string;
    authorization: TeacherCompensationMutationAuthorization;
    reasonText?: string;
    preservedTeacherDecision?: Pick<LessonFinancialDecision,
      "teacherCompensationRuleKey" |
      "teacherCompensationValueMinor" |
      "teacherCreditedDurationMinutes" |
      "teacherCompensationSource">;
  },
): Promise<LessonFinancialDecision>;
```

New automatic decisions use the resolved policy. Existing lessons may pass a
trusted `preservedTeacherDecision` loaded from storage. User payload cannot
populate that argument. Manual decisions require allowed authorization and a
non-empty reason. Wire lesson creation, planned-settlement updates, and corrections through this
method before `preparePlan`; transition and recurring-plan callers consume the
same method in their own plans.

- [ ] **Step 4: Add typed 422 mappings for invalid or missing partial fields**

```ts
if (policy.clientDurationMode === "manual" &&
    decision.chargeDurationMinutes === undefined) {
  invalidLessonSettlementDecision(
    "CLIENT_PARTIAL_DURATION_REQUIRED",
    `clientDecisions.${decision.clientId}.chargeDurationMinutes`,
  );
}
if (policy.teacherDurationMode === "manual" &&
    input.decision.teacherCreditedDurationMinutes === undefined) {
  invalidLessonSettlementDecision(
    "TEACHER_PARTIAL_DURATION_REQUIRED",
    "teacherCreditedDurationMinutes",
  );
}
```

When either manual value is `0` or equals the scheduled duration, keep it
valid and return a non-blocking preview recommendation to choose the clearer
zero or full settlement type. Never rewrite or clamp the entered minutes.

- [ ] **Step 5: Run settlement tests and typecheck**

Run: `cd server; npm test -- --runTestsByPath src/crm/dto/lesson-financial-decision.dto.spec.ts src/crm/commerce/lesson-settlement.calculation.spec.ts src/crm/commerce/lesson-settlement-execution.spec.ts src/crm/commerce/lesson-settlement-plan.persistence.spec.ts; npm run typecheck`

Also run: `cd server; npm test -- --runTestsByPath src/crm/commerce/lesson-settlement.service.spec.ts src/crm/schedule/lesson-compensation-rbac.spec.ts src/crm/schedule/lesson-command.service.spec.ts src/crm/schedule/lesson-write-parity.integration.spec.ts`

Expected: PASS with exact `0.50` client units and 75 percent teacher compensation for the 30/45-minute example.

- [ ] **Step 6: Commit the financial contract**

```powershell
git add server/src/crm/dto/lesson-financial-decision.dto.ts server/src/crm/dto/lesson-financial-decision.dto.spec.ts server/src/crm/commerce/lesson-settlement.port.ts server/src/crm/commerce/lesson-settlement.calculation.ts server/src/crm/commerce/lesson-settlement.calculation.spec.ts server/src/crm/commerce/lesson-settlement-execution.ts server/src/crm/commerce/lesson-settlement-execution.spec.ts server/src/crm/commerce/lesson-settlement-plan.persistence.ts server/src/crm/commerce/lesson-settlement-plan.persistence.spec.ts server/src/crm/commerce/lesson-settlement.service.ts server/src/crm/commerce/lesson-settlement.service.spec.ts server/src/crm/schedule/lesson-write-command.service.ts server/src/crm/schedule/lesson-planned-settlement-command.service.ts server/src/crm/schedule/lesson-settlement-correction.service.ts server/src/crm/schedule/lesson-compensation-rbac.spec.ts server/src/crm/schedule/lesson-write-parity.integration.spec.ts
git commit -m "feat: support partial lesson settlement durations"
```

### Task 3: Carry the resolved policy through recurring plans and reservations

**Files:**
- Modify: `server/src/crm/dto/schedule-plan.dto.ts`
- Modify: `server/src/crm/schedule/schedule-plan-constraint-preview.service.ts`
- Modify: `server/src/crm/schedule/schedule-plan-mutation.service.ts`
- Modify: `server/src/crm/schedule/schedule-series-materializer.service.ts`
- Modify: `server/src/crm/schedule/schedule-plan-services.spec.ts`
- Modify: `server/src/crm/schedule/schedule-plan-postgres.integration.spec.ts`
- Modify: `lib/features/crm/presentation/client_card/schedule_plan_mutation_flow.dart`
- Modify: `test/features/schedule/schedule_plan_mutation_flow_test.dart`

**Interfaces:**
- Consumes: extended `LessonFinancialDecision` from Task 2.
- Produces: every `SchedulePlanRowDto.financialDecision` as a fully resolved, revision-frozen decision.
- Preserves: `seriesId` lineage and effective-date behavior.

- [ ] **Step 1: Add failing plan tests for fractional materialization**

```ts
expect(createdRow.planned_financial_decision).toMatchObject({
  settlementTypeKey: "partially_paid_lesson",
  teacherCreditedDurationMinutes: 45,
  teacherCompensationSource: "manual",
  clientDecisions: [{
    clientId: fixture.studentId,
    chargeDurationMinutes: 30,
  }],
});
expect(reservations.rows.map(row => row.units)).toEqual(["0.50"]);
```

Add a group case with two participants using different payers/funding sources
and different `chargeDurationMinutes`. Assert one reservation calculation per
participant and one lesson-level teacher decision rather than one teacher
decision per participant.

- [ ] **Step 2: Run the plan mutation and PostgreSQL tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-plan-services.spec.ts src/crm/schedule/schedule-plan-postgres.integration.spec.ts`

Expected: FAIL because schedule rows drop the partial fields and materialization still uses the catalog's fixed share.

- [ ] **Step 3: Resolve and freeze the complete row decision before inserting series**

```ts
const resolvedDecision = await this.settlement.resolvePlannedDecision(
  client,
  {
    branchId: input.row.branchId,
    durationMinutes: input.row.durationMinutes,
    decision: financialDecision,
    actorUserId: actor.userId,
    authorization: this.policy.teacherCompensationMutationAuthorization(actor),
    reasonText: input.row.plannedSettlementReason,
  },
);
const settlementPlan = await this.settlement.preparePlan(
  client,
  input.row.branchId,
  resolvedDecision,
  actor.userId,
);
```

Update the materializer to use the resolved per-client minutes/share from the
stored plan for snapshots and reservations. Group participants receive their
own client values; teacher compensation remains one lesson-level decision.

- [ ] **Step 4: Preserve partial decisions in the Flutter plan-row payload**

```dart
'financialDecision': {
  'settlementTypeKey': draft.settlementTypeKey,
  'teacherCompensationRuleKey': draft.teacherCompensationRuleKey,
  'teacherCreditedDurationMinutes':
      draft.teacherCreditedDurationMinutes,
  'teacherCompensationSource': draft.teacherCompensationSource,
  'clientDecisions': draft.clientDecisions,
},
```

- [ ] **Step 5: Run backend and Flutter plan tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-plan-services.spec.ts src/crm/schedule/schedule-plan-postgres.integration.spec.ts; cd ..; flutter test test/features/schedule/schedule_plan_mutation_flow_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit recurring-plan propagation**

```powershell
git add server/src/crm/dto/schedule-plan.dto.ts server/src/crm/schedule/schedule-plan-constraint-preview.service.ts server/src/crm/schedule/schedule-plan-mutation.service.ts server/src/crm/schedule/schedule-series-materializer.service.ts server/src/crm/schedule/schedule-plan-services.spec.ts server/src/crm/schedule/schedule-plan-postgres.integration.spec.ts lib/features/crm/presentation/client_card/schedule_plan_mutation_flow.dart test/features/schedule/schedule_plan_mutation_flow_test.dart
git commit -m "feat: preserve settlement policy in schedule plans"
```

### Task 4: Add one-time autofill and partial-duration controls to Flutter

**Files:**
- Create: `lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_autofill.dart`
- Create: `test/features/admin/lesson_financial_autofill_test.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_form.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_sections.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_controller.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart`
- Modify: `lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart`
- Modify: `test/features/admin/lesson_editor_decision_policy_test.dart`
- Modify: `test/features/admin/lesson_editor_sections_test.dart`
- Modify: `test/features/schedule/lesson_decision_flow_test.dart`

**Interfaces:**
- Consumes catalog metadata from Task 1 and decision fields from Task 2.
- Produces: `LessonFinancialAutofill.apply(...)` and `restoreRecommendation(...)`.
- Produces form state `compensationTouched`, never persisted as shared state.

- [ ] **Step 1: Write failing pure Dart tests for autofill and manual preservation**

```dart
final paid = autofill.apply(
  settlement: catalog.byKey('paid_miss'),
  durationMinutes: 60,
  compensationTouched: false,
);
expect(paid.compensationRuleKey, 'standard');
expect(paid.teacherCreditedDurationMinutes, 60);

final preserved = autofill.apply(
  settlement: catalog.byKey('unpaid_miss'),
  durationMinutes: 60,
  compensationTouched: true,
  currentRuleKey: 'fixed',
);
expect(preserved.compensationRuleKey, 'fixed');
expect(preserved.source, 'manual');
```

Add widget cases for per-participant group partial minutes and one shared
teacher credited-duration field. A paid or partial absence for one participant
must not change the teacher field or another participant's funding decision.

- [ ] **Step 2: Run focused Flutter tests**

Run: `flutter test test/features/admin/lesson_financial_autofill_test.dart test/features/admin/lesson_editor_decision_policy_test.dart test/features/schedule/lesson_decision_flow_test.dart`

Expected: FAIL because the shared autofill helper and duration controls do not exist.

- [ ] **Step 3: Implement the catalog-driven autofill helper**

```dart
LessonFinancialRecommendation apply({
  required LessonDecisionCatalogItem settlement,
  required int durationMinutes,
  required bool compensationTouched,
  String? currentRuleKey,
  int? currentTeacherMinutes,
}) {
  if (compensationTouched) {
    return LessonFinancialRecommendation.manual(
      ruleKey: currentRuleKey,
      teacherMinutes: currentTeacherMinutes,
    );
  }
  return LessonFinancialRecommendation.automatic(
    ruleKey: settlement.defaultTeacherCompensationRuleKey,
    teacherMinutes: switch (settlement.teacherDurationMode) {
      'zero' => 0,
      'full' => durationMinutes,
      _ => null,
    },
  );
}
```

- [ ] **Step 4: Render partial fields and recommendation state in both forms**

Use integer minute inputs labelled `Списать с клиента` and
`Засчитать преподавателю`. Show the formatted hours/minutes beneath each
field, require values for manual modes, and add
`Применить рекомендуемое правило` after a manual teacher change.

```dart
TextFormField(
  key: const ValueKey('teacher-credited-duration-minutes'),
  decoration: const InputDecoration(
    labelText: 'Засчитать преподавателю, мин *',
  ),
  validator: (value) => partialDurationError(
    value,
    lessonDurationMinutes: draft.durationMinutes,
  ),
)
```

- [ ] **Step 5: Run responsive widget tests and analyze**

Run: `flutter test test/features/admin/lesson_financial_autofill_test.dart test/features/admin/lesson_editor_decision_policy_test.dart test/features/admin/lesson_editor_sections_test.dart test/features/schedule/lesson_decision_flow_test.dart; flutter analyze`

Expected: PASS with no overflow at phone and desktop widths.

- [ ] **Step 6: Commit the Flutter financial UX**

```powershell
git add lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_autofill.dart test/features/admin/lesson_financial_autofill_test.dart lib/features/admin/presentation/widgets/lesson_decision lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart test/features/admin/lesson_editor_decision_policy_test.dart test/features/admin/lesson_editor_sections_test.dart test/features/schedule/lesson_decision_flow_test.dart
git commit -m "feat: autofill lesson settlement and teacher pay"
```

### Task 5: Report credited teacher hours from effective facts

**Files:**
- Modify: `server/src/crm/payroll/payroll.types.ts`
- Modify: `server/src/crm/payroll/payroll-read.repository.ts`
- Modify: `server/src/crm/payroll/payroll-accrual-calculator.ts`
- Modify: `server/src/crm/payroll.service.spec.ts`
- Modify: `server/src/crm/payroll-postgres.integration.spec.ts`
- Modify: `server/src/crm/payroll/teacher-stats-report.service.ts`
- Modify: `server/src/crm/payroll/teacher-stats-xlsx.service.ts`
- Modify: `lib/features/manager/presentation/widgets/teacher_stats_models.dart`
- Modify: `lib/features/manager/presentation/widgets/teacher_stats_components.dart`
- Modify: `test/features/manager/teacher_stats_controller_test.dart`
- Modify: `integration_test/teacher_payroll_device_test.dart`

**Interfaces:**
- Produces: `PayrollLessonAccrual.scheduledHours` and `creditedHours`.
- Adds `compensation_actual_value` to `PayrollLessonRow` for percent facts.
- Keeps `hoursTotal` as credited hours and exposes `scheduledHoursTotal` separately.

- [ ] **Step 1: Write failing accrual and report tests**

```ts
expect(calculator.computeLessonAccrual({
  ...lesson,
  duration_minutes: 60,
  compensation_type: "percent",
  compensation_actual_value: "7500",
  settled_amount_minor: "75000",
}, rates)).toMatchObject({
  scheduledHours: 1,
  creditedHours: 0.75,
  amount: 750,
});
```

Use table tests for `none`, `standard`, `fixed`, `hourly`, and `percent` facts
at 30, 45, 60, and 90 scheduled minutes. Assert one effective teacher fact for
a group lesson and that participant count never multiplies credited hours or
amount.

- [ ] **Step 2: Run payroll tests and verify hours are incorrectly 1.0**

Run: `cd server; npm test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll-postgres.integration.spec.ts`

Expected: FAIL because settled accrual always reports full duration.

- [ ] **Step 3: Calculate credited hours from effective compensation facts**

```ts
private creditedHours(lesson: PayrollLessonRow, scheduledHours: number) {
  if (lesson.compensation_type === "none") return 0;
  if (lesson.compensation_type === "percent") {
    return this.round2(
      scheduledHours * Number(lesson.compensation_actual_value ?? 0) / 10_000,
    );
  }
  return scheduledHours;
}
```

Return both scheduled and credited totals in JSON and XLSX. Label the UI values
`По расписанию` and `Зачтено преподавателю`.

- [ ] **Step 4: Run backend, Flutter, and device-level report tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll-postgres.integration.spec.ts; cd ..; flutter test test/features/manager/teacher_stats_controller_test.dart integration_test/teacher_payroll_device_test.dart`

Expected: PASS and the 45-minute teacher example contributes `0.75` credited hours.

- [ ] **Step 5: Commit credited-hours reporting**

```powershell
git add server/src/crm/payroll server/src/crm/payroll.service.spec.ts server/src/crm/payroll-postgres.integration.spec.ts lib/features/manager/presentation/widgets/teacher_stats_models.dart lib/features/manager/presentation/widgets/teacher_stats_components.dart test/features/manager/teacher_stats_controller_test.dart integration_test/teacher_payroll_device_test.dart
git commit -m "fix: report credited teacher hours"
```

### Task 6: Hide and protect the system-owned commerce catalog

**Files:**
- Modify: `lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart`
- Modify: `lib/features/crm/presentation/client_forms/crm_configuration_workspace_shell.dart`
- Delete: `lib/features/crm/presentation/client_forms/crm_configuration_workspace_commerce.dart` if no remaining imports reference the part.
- Modify: `test/features/settings/crm_configuration_workspace_test.dart`
- Modify: `server/src/crm/crm-configuration.service.ts`
- Modify: `server/src/crm/crm-configuration.service.spec.ts`

**Interfaces:**
- Produces: `assertSystemOwnedCatalogUnchanged(current, next): void`.
- Removes all user navigation to the settlement/compensation catalog editor.

- [ ] **Step 1: Write failing UI and backend authorization tests**

```dart
expect(find.text('Занятия и оплата преподавателю'), findsNothing);
expect(find.byKey(const ValueKey('add-settlement-type')), findsNothing);
```

```ts
await expect(service.preview(actor, {
  ...draft,
  snapshot: { ...snapshot, lessonSettlementTypes: changedTypes },
})).rejects.toMatchObject({
  status: 403,
  response: { code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY" },
});
```

- [ ] **Step 2: Run the focused settings tests**

Run: `flutter test test/features/settings/crm_configuration_workspace_test.dart; cd server; npm test -- --runTestsByPath src/crm/crm-configuration.service.spec.ts`

Expected: FAIL because the editor is visible and the server accepts catalog changes.

- [ ] **Step 3: Remove the Flutter entry and enforce the backend boundary**

```ts
private assertSystemOwnedCatalogUnchanged(
  current: CrmConfigurationSnapshot,
  next: CrmConfigurationSnapshot,
) {
  if (fingerprintPayload(current.lessonSettlementTypes) !==
        fingerprintPayload(next.lessonSettlementTypes) ||
      fingerprintPayload(current.teacherCompensationRules) !==
        fingerprintPayload(next.teacherCompensationRules)) {
    throw new ForbiddenException({
      code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY",
    });
  }
}
```

Call the guard from draft preview and publish paths after effective snapshots
are normalized. Controlled migration code writes policy revisions directly
through its own release-only path.

- [ ] **Step 4: Run settings tests and the complete financial slice**

Run: `flutter test test/features/settings/crm_configuration_workspace_test.dart test/features/admin/lesson_financial_autofill_test.dart test/features/admin/lesson_editor_decision_policy_test.dart; cd server; npm test -- --runTestsByPath src/crm/crm-configuration.service.spec.ts src/crm/commerce/lesson-settlement-policy.spec.ts src/crm/commerce/lesson-settlement-postgres.integration.spec.ts src/crm/payroll-postgres.integration.spec.ts; npm run typecheck`

Expected: PASS.

- [ ] **Step 5: Update the RepoWise index and commit**

Run: `repowise update --index-only`

```powershell
git add lib/features/crm/presentation/client_forms/crm_configuration_workspace.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_shell.dart lib/features/crm/presentation/client_forms/crm_configuration_workspace_commerce.dart test/features/settings/crm_configuration_workspace_test.dart server/src/crm/crm-configuration.service.ts server/src/crm/crm-configuration.service.spec.ts
git commit -m "feat: make lesson settlement policy system owned"
```
