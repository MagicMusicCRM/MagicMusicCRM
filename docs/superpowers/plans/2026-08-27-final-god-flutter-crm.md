# Final God Files Flutter CRM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace six CRM/manager Flutter god states with lifecycle-safe controllers, focused views and pure projections while preserving public widget contracts.

**Architecture:** Each existing widget remains the composition shell. Controllers own immutable state and async generations, stateless views receive data/callbacks, and pure policies/projections contain deterministic transforms. ClientCard remains a composition of its existing semantic extensions instead of becoming a new mega-controller.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-27-final-god-files-zero-design.md`

## Global Constraints

- Preserve constructors, dialog helpers, providers, keys, Russian copy, navigation and Deep Charcoal/Gold styling.
- Keep backend authorization canonical; hidden/forbidden UI must not issue requests.
- Guard every async completion by mounted/disposed generation semantics.
- New owners: health `>=7.0`, max CCN `<=10`, NLOC `<=350`; shell target `<=150` NLOC.
- Run focused lane smoke; one full Flutter gate follows all lanes.

---

### Task 1: Preferred schedule controller and view

**Files:**
- Create: `lib/features/crm/presentation/client_card/preferred_schedule_editor_controller.dart`
- Create: `lib/features/crm/presentation/client_card/preferred_schedule_editor_view.dart`
- Modify: `lib/features/crm/presentation/client_card/preferred_schedule_editor.dart`
- Create: `test/features/schedule/preferred_schedule_editor_controller_test.dart`
- Modify: `test/features/schedule/preferred_schedule_editor_test.dart`

**Interfaces:** `PreferredScheduleEditorController` exposes immutable draft/filter/validation state, `initialize`, branch/teacher/room/decision mutations, and `buildDraft`; the shell retains `DirtyFormExitController`, date/time pickers and `Navigator.pop`.

- [ ] **Step 1: Write RED controller/architecture tests**

Cover branch filtering, past-date clamp, open-ended state, subscription fallback,
financial decision synchronization, exact Russian validation errors and
immutable `PreferredScheduleDraft`. Assert view imports no services and shell
contains no form business validation.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/features/schedule/preferred_schedule_editor_controller_test.dart
```

Expected: FAIL because the controller does not exist.

- [ ] **Step 3: Extract controller/view and reduce shell**

Move the existing calculations without changing values or copy. View receives
state plus callbacks only. Shell maps successful validation to the existing
draft and keeps the current dirty-exit flow.

- [ ] **Step 4: Run smoke and commit**

```powershell
flutter test test/features/schedule/preferred_schedule_editor_controller_test.dart test/features/schedule/preferred_schedule_editor_test.dart
flutter analyze lib/features/crm/presentation/client_card/preferred_schedule_editor.dart lib/features/crm/presentation/client_card/preferred_schedule_editor_controller.dart lib/features/crm/presentation/client_card/preferred_schedule_editor_view.dart
git diff --check
git add lib/features/crm/presentation/client_card/preferred_schedule_editor* test/features/schedule/preferred_schedule_editor*
git commit -m "refactor(schedule-ui): split preferred schedule editor"
```

### Task 2: Shared task draft, controller and view

**Files:**
- Create: `lib/features/manager/presentation/tasks/shared_task_editor_draft.dart`
- Create: `lib/features/manager/presentation/tasks/shared_task_editor_controller.dart`
- Create: `lib/features/manager/presentation/tasks/shared_task_editor_view.dart`
- Modify: `lib/features/manager/presentation/tasks/shared_task_editor.dart`
- Create: `test/features/tasks/shared_task_editor_controller_test.dart`
- Modify: `test/features/tasks/shared_task_editor_test.dart`

**Interfaces:** Controller owns draft, preview generations, frozen payload, mutation identity/fingerprint, reminders and terminal success; public `showSharedTaskEditor`, `showCreateSharedTask` and `SharedTaskEditor` signatures do not change.

- [ ] **Step 1: Write RED concurrency/identity tests**

Cover stale preview rejection, preview-required submit, same-payload identity
reuse, changed-payload identity rotation, reminder merge, delayed dispose and
terminal success remaining committed when callback/Navigator/UI feedback fails.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/features/tasks/shared_task_editor_controller_test.dart
```

- [ ] **Step 3: Extract immutable draft/controller/view**

Keep network commands in the existing data-source boundary. Controller returns
explicit preview/mutation outcomes; shell alone navigates and shows feedback.
Move `_DateTimeButton` and form sections to the view file.

- [ ] **Step 4: Run smoke and commit**

```powershell
flutter test test/features/tasks/shared_task_editor_controller_test.dart test/features/tasks/shared_task_editor_test.dart test/features/tasks/shared_tasks_data_source_test.dart test/features/tasks/shared_tasks_ui_test.dart
flutter analyze lib/features/manager/presentation/tasks
git diff --check
git add lib/features/manager/presentation/tasks/shared_task_editor* test/features/tasks/shared_task_editor*
git commit -m "refactor(tasks-ui): split shared task editor"
```

### Task 3: Finance controller and normal view library

**Files:**
- Create: `lib/features/manager/presentation/widgets/finance_controller.dart`
- Modify: `lib/features/manager/presentation/widgets/finance_widget.dart`
- Modify: `lib/features/manager/presentation/widgets/finance_widget_widgets.dart`
- Create: `test/features/manager/finance_controller_test.dart`
- Create: `test/features/manager/finance_architecture_test.dart`

**Interfaces:** `FinanceController` receives `MagicCrmService`, `ReportFileOpener`, range and branch; owns load generations, expense CRUD, export bytes/filename and busy/error state. Shell owns provider composition, confirmation dialogs and toasts. The widgets file becomes a normal imported library and no longer imports the shell.

- [ ] **Step 1: Write RED lifecycle/cycle tests**

Cover last-request-wins, disposal during load/export, CRUD refresh,
branch/range propagation, filename/error mapping and realtime debounce. Assert
the two-file part/import cycle is absent and `dart:io`, `path_provider`, and
`OpenFilex` are absent from the widget shell.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/features/manager/finance_controller_test.dart test/features/manager/finance_architecture_test.dart
```

- [ ] **Step 3: Implement controller and convert the view library**

Use `ReportFileOpener`/provider for export. Do not move role visibility into
the controller; unauthorized FinanceWidget mounting remains prevented by its
existing parent. A stale realtime/poll completion cannot overwrite current
state.

- [ ] **Step 4: Run smoke and commit**

```powershell
flutter test test/features/manager/finance_controller_test.dart test/features/manager/finance_architecture_test.dart test/features/commerce/client_finance_roles_test.dart test/features/manager/realtime_poll_ux_test.dart
flutter analyze lib/features/manager/presentation/widgets/finance*
git diff --check
git add lib/features/manager/presentation/widgets/finance* test/features/manager/finance* test/features/commerce/client_finance_roles_test.dart
git commit -m "refactor(finance-ui): split finance controller and view"
```

### Task 4: Student funnel controller and view

**Files:**
- Create: `lib/features/manager/presentation/widgets/student_funnel_editor_controller.dart`
- Create: `lib/features/manager/presentation/widgets/student_funnel_editor_view.dart`
- Modify: `lib/features/manager/presentation/widgets/student_funnel_editor.dart`
- Create: `test/features/crm/student_funnel_editor_controller_test.dart`
- Modify: `test/features/crm/student_funnel_editor_test.dart`

**Interfaces:** Controller owns load, immutable stage draft mutations, preview, confirmed publish and rollback. Shell owns discard/preview/rollback dialogs, Navigator and `onPublished`.

- [ ] **Step 1: Write RED version/lifecycle tests**

Assert `expectedVersion == configuration.scopeVersion`, every publish has a
preview, blocking issues prevent commit, reason is required, rollback produces
a new version, stale loads are ignored, and scope/type changes require an
explicit discard decision supplied by the shell.

- [ ] **Step 2: Run RED, extract owners, then smoke**

```powershell
flutter test test/features/crm/student_funnel_editor_controller_test.dart
flutter test test/features/crm/student_funnel_editor_controller_test.dart test/features/crm/student_funnel_editor_test.dart
flutter analyze lib/features/manager/presentation/widgets/student_funnel_editor*
git diff --check
```

Expected: first run fails before implementation; second run and analyzer PASS.

- [ ] **Step 3: Commit**

```powershell
git add lib/features/manager/presentation/widgets/student_funnel_editor* test/features/crm/student_funnel_editor*
git commit -m "refactor(funnel-ui): split editor controller and view"
```

### Task 5: Students board controller, projection and view boundary

**Files:**
- Create: `lib/features/manager/presentation/widgets/students_board_controller.dart`
- Create: `lib/features/manager/presentation/widgets/students_board_projection.dart`
- Create: `lib/features/manager/presentation/widgets/students_board_models.dart`
- Create: `lib/features/manager/presentation/widgets/students_board_auto_scroll_controller.dart`
- Modify: `lib/features/manager/presentation/widgets/students_board_widget.dart`
- Modify: `lib/features/manager/presentation/widgets/students_board_widgets.dart`
- Create: `test/features/manager/students_board_controller_test.dart`
- Create: `test/features/manager/students_board_projection_test.dart`
- Modify: `test/features/manager/students_board_grouping_test.dart`

**Interfaces:** Controller owns branches, selection, page overlays, search, optimistic status and mutation generations. Projection is pure re-bucketing. Shell retains Riverpod provider watches, capability visibility, `LeadTransferController` and `showClientCard` navigation.

- [ ] **Step 1: Write RED pagination/optimistic tests**

Cover page dedupe, stale page rejection, optimistic move and rollback, realtime
refresh precedence, dispose, pure bucket order/counts and auto-scroll disposal.
Assert widgets file is a normal view library with no back import to the shell.

- [ ] **Step 2: Run RED, implement, then smoke**

```powershell
flutter test test/features/manager/students_board_controller_test.dart test/features/manager/students_board_projection_test.dart
flutter test test/features/manager/students_board_controller_test.dart test/features/manager/students_board_projection_test.dart test/features/manager/students_board_grouping_test.dart test/features/manager/realtime_poll_ux_test.dart
flutter analyze lib/features/manager/presentation/widgets/students_board*
git diff --check
```

- [ ] **Step 3: Commit**

```powershell
git add lib/features/manager/presentation/widgets/students_board* test/features/manager/students_board* test/features/manager/realtime_poll_ux_test.dart
git commit -m "refactor(students-ui): split board state and projection"
```

### Task 6: ClientCard workspace/access/shell split

**Files:**
- Create: `lib/features/crm/presentation/client_card/client_card_workspace_controller.dart`
- Create: `lib/features/crm/presentation/client_card/client_card_access_policy.dart`
- Create: `lib/features/crm/presentation/client_card/client_card_shell.dart`
- Modify: `lib/features/crm/presentation/client_card/client_card.dart`
- Modify only as required: existing `client_card_*.dart` semantic extensions
- Create: `test/features/crm/client_card/client_card_workspace_controller_test.dart`
- Create: `test/features/crm/client_card/client_card_access_policy_test.dart`
- Create: `test/features/crm/client_card/client_card_architecture_test.dart`

**Interfaces:** Workspace controller owns selected section, restored offsets, expanded sections, dirty/close state and scroll-controller lifecycle. Pure access policy projects role/capabilities to visible finance/schedule/task sections. Shell renders routed/dialog layout and PopScope. `_ClientCardState` retains WidgetRef, realtime and semantic extension composition.

- [ ] **Step 1: Write RED policy/lifecycle/architecture tests**

Cover routed/dialog parity, section restore, post-frame disposal, dirty close,
teacher fail-closed commerce access, lead/student/converted section policy,
entity links through `openEntityLink`, and no service/network calls from
access/shell owners.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/features/crm/client_card/client_card_workspace_controller_test.dart test/features/crm/client_card/client_card_access_policy_test.dart test/features/crm/client_card/client_card_architecture_test.dart
```

- [ ] **Step 3: Extract only workspace/access/rendering state**

Do not combine loaders, persistence, family, moderation or other existing
extensions. Adapt their workspace/access field reads through the new owners
without changing API calls, payloads, invalidation, counterpart resolution or
navigation.

- [ ] **Step 4: Run broad ClientCard smoke and commit**

```powershell
flutter test test/features/crm/client_card test/features/crm/client_card_action_inventory_test.dart test/features/crm/client_internal_context_test.dart test/features/navigation/client_card_launcher_boundary_test.dart test/features/navigation/client_workspace_route_test.dart test/features/commerce/client_finance_roles_test.dart
flutter analyze lib/features/crm/presentation/client_card
git diff --check
git add lib/features/crm/presentation/client_card test/features/crm/client_card test/features/crm/client_card_action_inventory_test.dart test/features/crm/client_internal_context_test.dart test/features/navigation/client_card_launcher_boundary_test.dart test/features/navigation/client_workspace_route_test.dart test/features/commerce/client_finance_roles_test.dart
git commit -m "refactor(client-card): split workspace and access owners"
```

### Task 7: Measure each integrated Flutter lane

**Files:** No production edits unless a metric gate identifies the owning lane.

- [ ] **Step 1: After each lane commit update tools**

```powershell
repowise update --index-only
sentrux check
```

Call RepoWise targeted health/risk for the original and new owners and Sentrux
MCP rescan/health/rules. Expected: the original god/brain marker disappears,
new owners satisfy health/CCN/NLOC, Sentrux rules remain 2/2 and no root metric
regresses from baseline.

- [ ] **Step 2: Run the combined Flutter lane smoke**

```powershell
flutter test test/features/schedule/preferred_schedule_editor_test.dart test/features/tasks/shared_task_editor_test.dart test/features/commerce/client_finance_roles_test.dart test/features/crm/student_funnel_editor_test.dart test/features/manager/students_board_grouping_test.dart test/features/manager/realtime_poll_ux_test.dart test/features/crm/client_card test/features/navigation/client_workspace_route_test.dart
flutter analyze lib/features/crm/presentation/client_card lib/features/manager/presentation
```

Expected: all selected tests and analyzer PASS before workspace/admin integration.
