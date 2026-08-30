# Human-readable Audit Journal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two legacy audit renderers with one safe backend presentation contract and one typed expandable Flutter card used by client history and Analytics.

**Architecture:** A pure `AuditPresentationService` converts immutable audit rows into a safe human-readable DTO. Dashboard and client-history queries resolve actor/target context and feed that presenter; Flutter parses the shared DTO once and renders it through a reusable stateful card while feature layers retain navigation and pagination.

**Tech Stack:** NestJS 11, TypeScript 5.8, PostgreSQL audit queries, Jest 30, Flutter/Dart 3.11, Riverpod, Flutter widget tests.

**Spec:** `docs/superpowers/specs/2026-08-30-human-readable-audit-journal-design.md`

## Global Constraints

- Both journal endpoints return the exact `AuditPresentationEvent` shape defined in the spec.
- Unknown business actions and fields use a safe human-readable fallback; known mappings are not an allowlist.
- Raw action keys, metadata, database ids, technical version counters, auth/session maintenance events, and secrets are never rendered in ordinary Flutter UI.
- `app.audit_events` and lead status history remain append-only; no rows are deleted or rewritten and no production migration is added.
- Client history keeps newest-first cursor pagination with default 10 and maximum 100 items.
- Analytics keeps its existing filters and maximum 100 items for this release.
- Expansion and navigation are separate actions; expansion never reloads a page or clears filters.
- Existing backend RBAC/resource scope and Flutter `ContextTransitionRegistry`/`openEntityLink` remain the authorization/navigation boundaries.
- UI copy is Russian; code and comments are English; colors use existing Quiet Graphite & Sophisticated Gold semantic tokens.
- Tests follow strict RED → GREEN and production code is not written before the focused test fails for the expected behavior.
- Work only in `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM`; do not create a worktree or parallel project copy.
- Do not release, deploy, push, or mutate production as part of this plan.

---

### Task 1: Shared Backend Audit Presenter

**Files:**
- Create: `server/src/audit/audit-presentation.types.ts`
- Create: `server/src/audit/audit-presentation.service.ts`
- Create: `server/src/audit/audit-presentation.service.spec.ts`
- Modify: `server/src/audit/audit.module.ts`

**Interfaces:**
- Consumes: normalized immutable audit input with actor and target display context.
- Produces: `AuditPresentationService.present(input: AuditPresentationInput): AuditPresentationEvent` and `isBusinessAction(actionKey: string): boolean`.

- [ ] **Step 1: Write the failing presenter contract tests**

Add table-driven Jest tests using literal expected values. The test fixture must include the complete input shape and must prove these observable breaks: a known email change renders `Электронная почта изменена`; an unknown `crm.student_marketing_consent_updated` action becomes readable without raw snake case; `beforeRef`/`afterRef` differences become labeled changes; `version`, `refreshToken`, and `[REDACTED]` do not appear; `auth.session_rotated` is not a business action.

```ts
const emailChange: AuditPresentationInput = {
  id: "event-1",
  actionKey: "crm.student_updated",
  actor: { id: "user-1", name: "Наталия Назарова", role: "director" },
  target: {
    type: "student",
    id: "student-1",
    displayName: "Мария Баранова",
  },
  metadata: {},
  beforeRef: { email: "old@example.com", version: 11 },
  afterRef: { email: "new@example.com", version: 12 },
  reason: null,
  reasonText: null,
  occurredAt: new Date("2026-08-30T17:21:00.000Z"),
};

expect(service.present(emailChange)).toMatchObject({
  title: "Электронная почта изменена",
  target: {
    type: "student",
    id: "student-1",
    label: "Ученик",
    displayName: "Мария Баранова",
    routeType: "student",
  },
  changes: [
    {
      key: "email",
      label: "Электронная почта",
      before: "old@example.com",
      after: "new@example.com",
    },
  ],
});
expect(JSON.stringify(service.present(emailChange))).not.toContain("version");
```

- [ ] **Step 2: Run the presenter test and verify RED**

Run: `cd server; npm test -- --runTestsByPath src/audit/audit-presentation.service.spec.ts`

Expected: FAIL because `AuditPresentationService` and its types do not exist.

- [ ] **Step 3: Implement the typed presenter and safety rules**

Create the exact public types:

```ts
export interface AuditPresentationChange {
  key: string;
  label: string;
  before: string | null;
  after: string | null;
}

export interface AuditPresentationEvent {
  id: string;
  actionKey: string;
  title: string;
  summary: string | null;
  reason: string | null;
  actor: { id: string | null; name: string; role: string | null };
  target: {
    type: string;
    id: string | null;
    label: string;
    displayName: string | null;
    routeType: string | null;
  };
  changes: AuditPresentationChange[];
  occurredAt: Date | string;
}

export interface AuditPresentationInput {
  id: string;
  actionKey: string;
  actor: { id: string | null; name: string; role: string | null };
  target: { type: string; id: string | null; displayName: string | null };
  metadata: Record<string, unknown> | null;
  beforeRef: Record<string, unknown> | null;
  afterRef: Record<string, unknown> | null;
  reason: string | null;
  reasonText: string | null;
  occurredAt: Date | string;
}
```

Implement safe extraction in one place. Sensitive-key matching is case-insensitive for `password|token|secret|authorization|credential|otp|hash|session|refresh|cookie|privatekey`; `version` is ignored as technical state. Redaction markers become null. Known entity/field/action dictionaries improve Russian copy, while `humanizeIdentifier` and action-suffix fallbacks cover unknown keys. Export the service from `AuditModule`.

- [ ] **Step 4: Run focused tests and typecheck**

Run: `cd server; npm test -- --runTestsByPath src/audit/audit-presentation.service.spec.ts; npm run typecheck`

Expected: presenter tests PASS and TypeScript reports no errors.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- server/src/audit/audit-presentation.types.ts server/src/audit/audit-presentation.service.ts server/src/audit/audit-presentation.service.spec.ts server/src/audit/audit.module.ts
git commit -m "feat(audit): add shared journal presenter"
```

### Task 2: Analytics Activity Endpoint Uses the Shared Contract

**Files:**
- Modify: `server/src/crm/dashboard.service.ts`
- Modify: `server/src/crm/dashboard.service.spec.ts`

**Interfaces:**
- Consumes: `AuditPresentationService.present` from Task 1.
- Produces: `DashboardService.listActivityLog(...)` returning `{ items: AuditPresentationEvent[] }` with existing query filters unchanged.

- [ ] **Step 1: Replace raw-map expectations with failing shared-contract tests**

Update the fixture row to include `before_ref`, `after_ref`, `reason`, `reason_text`, and `target_display_name`. Assert literal nested DTO values and assert that the generated SQL excludes technical auth/session actions and resolves a target display name without a per-row query.

```ts
expect(result.items[0]).toMatchObject({
  id: "audit-1",
  title: "Электронная почта изменена",
  actor: { id: actor.userId, name: "Наталия Назарова" },
  target: {
    type: "student",
    id: "student-1",
    label: "Ученик",
    displayName: "Мария Баранова",
  },
  changes: [
    {
      key: "email",
      label: "Электронная почта",
      before: "old@example.com",
      after: "new@example.com",
    },
  ],
});
expect(database.query).toHaveBeenCalledTimes(1);
expect(database.query.mock.calls[0][0]).toContain("ae.action not like 'auth.%'");
```

- [ ] **Step 2: Run the dashboard test and verify RED**

Run: `cd server; npm test -- --runTestsByPath src/crm/dashboard.service.spec.ts`

Expected: FAIL because the service still returns flat raw metadata fields and does not select/resolve presentation context.

- [ ] **Step 3: Inject the presenter and normalize dashboard rows**

Extend `ActivityLogRow` with the four immutable reference/reason fields and `target_display_name`. Add bounded SQL joins/`CASE` for `student`, `lead`, `lesson`, `staff|teacher|profile`, `group`, `task`, `payment`, `subscription`, `homework`, and `comment`; unsupported/historical entities remain null. Add predicates excluding `auth.%`, refresh/session actions, and their technical history types. Keep all existing filter parameters and limit behavior. Remove `toActivityLogDto` and raw `metadata` from the response; map rows through `presenter.present`.

- [ ] **Step 4: Run dashboard regression, typecheck, and build**

Run: `cd server; npm test -- --runTestsByPath src/crm/dashboard.service.spec.ts; npm run typecheck; npm run build`

Expected: focused tests PASS, TypeScript and Nest build succeed.

- [ ] **Step 5: Commit Task 2**

```powershell
git add -- server/src/crm/dashboard.service.ts server/src/crm/dashboard.service.spec.ts
git commit -m "feat(crm): present analytics journal events"
```

### Task 3: Client Operational History Uses the Shared Contract

**Files:**
- Modify: `server/src/crm/clients/client-internal-context.service.ts`
- Modify: `server/src/crm/clients/client-internal-context.service.spec.ts`

**Interfaces:**
- Consumes: `AuditPresentationService.present` and `isBusinessAction` from Task 1.
- Produces: the existing paged response with `items: AuditPresentationEvent[]` and `nextCursor: string | null`.

- [ ] **Step 1: Write failing client-history tests for global coverage**

Replace the legacy `action/reason/summary/actorName` assertions with the shared nested DTO. Add a test row for `crm.student_updated` that was absent from `HISTORY_ACTIONS`, a synthetic lead-status row, and a note event with version refs. Assert newest-first default 10, cursor behavior, no version text, generic unknown-field readability, and no auth/session row eligibility.

```ts
expect(result.items[0]).toMatchObject({
  title: "Направление изменено",
  actor: { name: "Наталия Назарова" },
  target: { type: "student", id: studentId, displayName: "Мария Баранова" },
  changes: [
    {
      key: "direction",
      label: "Направление",
      before: "Вокал",
      after: "Фортепиано",
    },
  ],
});
expect(JSON.stringify(result.items)).not.toMatch(/Версия|auth\.|session|refresh/i);
```

- [ ] **Step 2: Run the client-history test and verify RED**

Run: `cd server; npm test -- --runTestsByPath src/crm/clients/client-internal-context.service.spec.ts`

Expected: FAIL because the allowlist excludes generic updates and `historyDto` returns the legacy shape.

- [ ] **Step 3: Replace the client-only translator and action allowlist**

Inject `AuditPresentationService`. Change `HistoryRow` to carry actor id/role and target type/id/display name. In the lineage query accept lineage-related `crm.*` and `workflow.*` events while excluding technical actions; do not add a replacement fixed allowlist. Normalize synthetic lead status rows to the same row shape. Remove `ACTION_LABELS`, `historyDto`, `historySummary`, `historyReason`, and version summary logic. Preserve RBAC, lineage, ordering, cursor, default 10, and max 100 exactly.

- [ ] **Step 4: Run client-history and dashboard regression tests**

Run: `cd server; npm test -- --runTestsByPath src/audit/audit-presentation.service.spec.ts src/crm/dashboard.service.spec.ts src/crm/clients/client-internal-context.service.spec.ts; npm run typecheck`

Expected: all three suites PASS and TypeScript reports no errors.

- [ ] **Step 5: Commit Task 3**

```powershell
git add -- server/src/crm/clients/client-internal-context.service.ts server/src/crm/clients/client-internal-context.service.spec.ts
git commit -m "feat(crm): unify client history presentation"
```

### Task 4: Typed Flutter Audit Model and Shared Card

**Files:**
- Create: `lib/core/models/audit_presentation_event.dart`
- Create: `lib/shared/widgets/audit_event_card.dart`
- Create: `test/core/models/audit_presentation_event_test.dart`
- Create: `test/shared/widgets/audit_event_card_test.dart`

**Interfaces:**
- Consumes: the exact backend `AuditPresentationEvent` JSON contract.
- Produces: immutable Dart models and `AuditEventCard(event:, onOpenTarget:)`.

- [ ] **Step 1: Write failing model and widget tests**

Use one complete JSON fixture with nested actor, target, and two changes. Model tests must assert strict parsing/defaults. Widget tests must assert collapsed content, absence of raw `actionKey`, expansion revealing `Было`/`Стало` and reason, collapse without navigation, and a separate open-target callback.

```dart
await tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AuditEventCard(event: event, onOpenTarget: onOpen),
    ),
  ),
);
expect(find.text('Электронная почта изменена'), findsOneWidget);
expect(find.text('crm.student_updated'), findsNothing);
expect(find.text('old@example.com'), findsNothing);
await tester.tap(find.byKey(const Key('audit-event-expand')));
await tester.pumpAndSettle();
expect(find.text('Было: old@example.com'), findsOneWidget);
expect(find.text('Стало: new@example.com'), findsOneWidget);
expect(openCount, 0);
```

- [ ] **Step 2: Run both Flutter tests and verify RED**

Run: `flutter test test/core/models/audit_presentation_event_test.dart test/shared/widgets/audit_event_card_test.dart`

Expected: FAIL because the model and widget files do not exist.

- [ ] **Step 3: Implement immutable models and the shared card**

Create `AuditPresentationActor`, `AuditPresentationTarget`, `AuditPresentationChange`, and `AuditPresentationEvent` with `fromJson`. The card uses existing `AppColor`, `AppSpace`, and `AppRadius` tokens. Its local `_expanded` state is keyed by event id; the card header/chevron only toggles expansion. Render target display name, actor/time, optional summary, change rows, optional reason, and an `Открыть <entity label>` text button only when `onOpenTarget` is non-null.

```dart
class AuditEventCard extends StatefulWidget {
  const AuditEventCard({
    super.key,
    required this.event,
    this.onOpenTarget,
  });

  final AuditPresentationEvent event;
  final VoidCallback? onOpenTarget;
}
```

- [ ] **Step 4: Run focused tests and analyze the new files**

Run: `flutter test test/core/models/audit_presentation_event_test.dart test/shared/widgets/audit_event_card_test.dart; dart analyze lib/core/models/audit_presentation_event.dart lib/shared/widgets/audit_event_card.dart`

Expected: model/widget tests PASS and analyzer reports no issues.

- [ ] **Step 5: Commit Task 4**

```powershell
git add -- lib/core/models/audit_presentation_event.dart lib/shared/widgets/audit_event_card.dart test/core/models/audit_presentation_event_test.dart test/shared/widgets/audit_event_card_test.dart
git commit -m "feat(ui): add shared audit event card"
```

### Task 5: Wire Both Flutter Consumers and Remove Legacy Rendering

**Files:**
- Modify: `lib/core/models/client_internal_context.dart`
- Modify: `lib/core/services/magic_crm_service_core.dart`
- Modify: `lib/core/services/magic_crm_service_legacy_map_adapter.dart`
- Modify: `lib/features/crm/presentation/client_card/client_card.dart`
- Modify: `lib/features/crm/presentation/client_card/client_card_internal_context.dart`
- Modify: `lib/features/crm/presentation/client_card/client_internal_context_widgets.dart`
- Modify: `lib/features/manager/presentation/widgets/reports_widget_widgets.dart`
- Modify: `test/core/services/magic_crm_service_test.dart`
- Modify: `test/features/crm/client_internal_context_test.dart`
- Modify: `integration_test/analytics_device_test.dart`

**Interfaces:**
- Consumes: `AuditPresentationEvent.fromJson` and `AuditEventCard` from Task 4.
- Produces: typed `listActivityLog`, shared client/Analytics rendering, existing filters/pagination, and existing authorized target navigation.

- [ ] **Step 1: Write failing consumer and regression tests**

Update the service mock response to the complete nested DTO and assert `List<AuditPresentationEvent>`. In client tests assert only 10 initial cards, `Показать ещё`, expansion without a service reload, and no `Версия`. In Analytics tests assert concrete target/person text, expansion preserves filter state, and `Открыть Ученик` routes through the existing target registry.

```dart
final activity = await service.listActivityLog(limit: 25);
expect(activity.single.title, 'Электронная почта изменена');
expect(activity.single.target.displayName, 'Мария Баранова');
expect(activity.single.changes.single.before, 'old@example.com');
expect(api.lastRequest?.queryParameters['limit'], 25);
```

- [ ] **Step 2: Run consumer tests and verify RED**

Run: `flutter test test/core/services/magic_crm_service_test.dart test/features/crm/client_internal_context_test.dart integration_test/analytics_device_test.dart`

Expected: FAIL because services and consumers still use raw maps and two legacy row widgets.

- [ ] **Step 3: Switch services and client page to the shared model**

Change `listActivityLog` to `Future<List<AuditPresentationEvent>>` and parse with `AuditPresentationEvent.fromJson`. Delete `_legacyActivityLog`. Change `ClientOperationalHistoryPage.items`, card state, load/dedupe methods, and parameters from `ClientOperationalHistoryItem` to `AuditPresentationEvent`; delete the old item class.

- [ ] **Step 4: Replace both legacy UI rows with `AuditEventCard`**

Delete `_ActivityLogTile`, `_OperationalHistoryRow`, and their raw-label helpers that are no longer referenced. Both lists render `AuditEventCard`. Analytics provides `onOpenTarget` only when `ContextTransitionRegistry` supports `event.target.routeType` and id. Client history uses the same rule and preserves the current client tab/state when expansion occurs. Keep client first-10 pagination and Analytics loading/filter behavior unchanged.

- [ ] **Step 5: Run focused and full regression gates**

Run:

```powershell
flutter test test/core/models/audit_presentation_event_test.dart test/shared/widgets/audit_event_card_test.dart test/core/services/magic_crm_service_test.dart test/features/crm/client_internal_context_test.dart integration_test/analytics_device_test.dart
flutter analyze
Push-Location server
npm test -- --runTestsByPath src/audit/audit-presentation.service.spec.ts src/crm/dashboard.service.spec.ts src/crm/clients/client-internal-context.service.spec.ts
npm run typecheck
npm run build
Pop-Location
```

Expected: all focused Flutter/backend suites PASS, Flutter analyzer reports no issues, TypeScript typecheck and Nest build succeed.

- [ ] **Step 6: Commit Task 5**

```powershell
git add -- lib/core/models/client_internal_context.dart lib/core/services/magic_crm_service_core.dart lib/core/services/magic_crm_service_legacy_map_adapter.dart lib/features/crm/presentation/client_card/client_card.dart lib/features/crm/presentation/client_card/client_card_internal_context.dart lib/features/crm/presentation/client_card/client_internal_context_widgets.dart lib/features/manager/presentation/widgets/reports_widget_widgets.dart test/core/services/magic_crm_service_test.dart test/features/crm/client_internal_context_test.dart integration_test/analytics_device_test.dart
git commit -m "feat(crm): use readable audit cards everywhere"
```

### Task 6: Repository Index and Release-Candidate Evidence

**Files:**
- Modify only if commands require generated evidence already tracked by repository policy; otherwise no source changes.

**Interfaces:**
- Consumes: Tasks 1–5 at one HEAD.
- Produces: updated local RepoWise index and a verified local release candidate; no deploy or publish.

- [ ] **Step 1: Run structural search for forbidden legacy output**

Run: `rg -n "_legacyActivityLog|_ActivityLogTile|_OperationalHistoryRow|Версия .*→|Действие с клиентом|return ['\"]Действие['\"]" lib server/src test integration_test`

Expected: no production renderer or adapter match; test fixtures may mention forbidden strings only in negative assertions.

- [ ] **Step 2: Run repository-level verification**

Run: `flutter test; flutter analyze; Push-Location server; npm test; npm run typecheck; npm run build; Pop-Location`

Expected: all tests PASS and all analyzers/builds succeed without warnings attributable to this change.

- [ ] **Step 3: Update the local RepoWise index**

Run: `repowise update --index-only`

Expected: the local index completes at the current HEAD. No remote or production state changes.

- [ ] **Step 4: Record final verification state**

Run: `git status --short --branch; git log -7 --oneline`

Expected: working tree clean; commits for the spec, plan, and Tasks 1–5 are visible; branch is ahead of `origin/main` only by this approved work.
