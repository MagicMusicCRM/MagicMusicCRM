# Final God Files Workspace and Admin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ProductionWorkspaceHost and reference lifecycle god states with focused runtime/controller and stateless view owners.

**Architecture:** The workspace host retains Riverpod effects and dirty prompts while a runtime owns restore/persistence/logout generations and a view renders responsive shells. The reference dialog retains text/Navigator ownership while a controller owns API lifecycle and content renders server-driven state.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_test, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-27-final-god-files-zero-design.md`

## Global Constraints

- Preserve public widget constructors, provider contracts, keys, Russian copy, navigation and theme.
- Preserve workspace reset-before-restore, capability fallback, direct-link precedence, dirty prompts and mobile/desktop topology.
- Preserve reference preview/version/blockers/history and archive-as-unassign behavior.
- New owners: health `>=7.0`, max CCN `<=10`, NLOC `<=350`; shell target `<=150` NLOC.
- Run focused smoke; full Flutter gate runs once after every final owner integrates.

---

### Task 1: Reference lifecycle controller and content

**Files:**
- Create: `lib/features/admin/presentation/widgets/reference_catalog_lifecycle_controller.dart`
- Create: `lib/features/admin/presentation/widgets/reference_catalog_lifecycle_content.dart`
- Modify: `lib/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart`
- Create: `test/features/settings/reference_catalog_lifecycle_controller_test.dart`
- Create: `test/features/settings/reference_catalog_lifecycle_architecture_test.dart`
- Modify: `test/features/settings/reference_catalog_lifecycle_test.dart`

**Interfaces:** `ReferenceCatalogLifecycleController` receives `MagicCrmService` and the initial item; exposes immutable loading/saving/error/preview/history state plus `load`, `rename`, `commitLifecycle`, `dispose`. Content receives state, text values and callbacks only. Dialog owns two text controllers, listener and Navigator.

- [ ] **Step 1: Write RED controller and dependency tests**

Cover load/rename/archive/restore, branch-discipline rename prohibition,
camel/snake lifecycle fields, number/string version normalization, reason
minimum length, blockers, stale completion, API error reconciliation and
dispose. Assert dialog invokes no service mutation and content imports neither
Riverpod nor API/service files.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/features/settings/reference_catalog_lifecycle_controller_test.dart test/features/settings/reference_catalog_lifecycle_architecture_test.dart
```

- [ ] **Step 3: Extract orchestration and content**

Keep preview entity precedence, server-driven `canArchive`/`canRestore`, current
expected version, implicit `confirm: true`, append-only history and maximum ten
rendered entries. Rename reloads without closing; archive/restore close only
after success.

- [ ] **Step 4: Run smoke and commit**

```powershell
flutter test test/features/settings/reference_catalog_lifecycle_controller_test.dart test/features/settings/reference_catalog_lifecycle_architecture_test.dart test/features/settings/reference_catalog_lifecycle_test.dart
flutter test test/core/services/magic_crm_service_test.dart --name "reference lifecycle uses preview, history and versioned mutation paths"
flutter analyze lib/features/admin/presentation/widgets/reference_catalog_lifecycle*
git diff --check
git add lib/features/admin/presentation/widgets/reference_catalog_lifecycle* test/features/settings/reference_catalog_lifecycle* test/core/services/magic_crm_service_test.dart
git commit -m "refactor(settings-ui): split reference lifecycle dialog"
```

### Task 2: Production workspace runtime and view

**Files:**
- Create: `lib/core/workspace/production_workspace_runtime.dart`
- Create: `lib/core/workspace/production_workspace_view.dart`
- Modify: `lib/core/workspace/production_workspace_host.dart`
- Create: `test/core/workspace/production_workspace_runtime_test.dart`
- Create: `test/features/workspace/production_workspace_host_architecture_test.dart`
- Modify: `test/features/workspace/production_workspace_mount_test.dart`

**Interfaces:** `ProductionWorkspaceRuntime` owns `WorkspaceController`, persistence binding, logout attach/detach and restore generation. It exposes current controller plus initialize/replace/dispose operations and accepts capability/title/route collaborators explicitly. `ProductionWorkspaceView` receives active tab, shell data and callbacks only. Host owns Riverpod listeners, dirty decision UI and provider effects.

- [ ] **Step 1: Write RED restore/lifecycle tests**

Cover delayed restore after dispose, account/role reset-before-restore,
forbidden initial-link fallback to `chat/home`, direct-link precedence and
deduplication by raw entity type/id/focus. Architecture test requires runtime as
the sole persistence/logout owner and forbids Riverpod/services in the view.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/core/workspace/production_workspace_runtime_test.dart test/features/workspace/production_workspace_host_architecture_test.dart
```

- [ ] **Step 3: Extract runtime and responsive view**

Keep `WorkspaceNavigationScope` around all tab content. Preserve desktop
multi-tab limit ten, mobile single stack, breadcrumb/back, unseen marking,
active-view updates, canonical title and dirty save/discard/cancel ordering.
Dispose invalidates generations before detaching bindings/controller.

- [ ] **Step 4: Run smoke and commit**

```powershell
flutter test test/core/workspace/production_workspace_runtime_test.dart test/features/workspace/production_workspace_host_architecture_test.dart test/features/workspace/production_workspace_mount_test.dart test/features/workspace/workspace_persistence_logout_test.dart test/features/navigation/client_workspace_route_test.dart test/features/messenger/tasks_navigation_test.dart
flutter analyze lib/core/workspace
git diff --check
git add lib/core/workspace/production_workspace* test/core/workspace/production_workspace_runtime_test.dart test/features/workspace/production_workspace* test/features/workspace/workspace_persistence_logout_test.dart test/features/navigation/client_workspace_route_test.dart test/features/messenger/tasks_navigation_test.dart
git commit -m "refactor(workspace): split production runtime and view"
```

### Task 3: Measure and hand off to the final global gate

**Files:** No production edits unless a lane-owned metric gate fails.

- [ ] **Step 1: Refresh RepoWise and Sentrux after each lane**

```powershell
repowise update --index-only
sentrux check
```

Call targeted RepoWise health/risk and Sentrux MCP rescan/health/rules. Expected:
both original god/brain findings disappear, new owners satisfy budgets, rules
remain 2/2 and no root metric regresses.

- [ ] **Step 2: Run combined workspace/admin smoke**

```powershell
flutter test test/features/settings/reference_catalog_lifecycle_controller_test.dart test/features/settings/reference_catalog_lifecycle_test.dart test/core/workspace/production_workspace_runtime_test.dart test/features/workspace/production_workspace_mount_test.dart test/features/navigation/client_workspace_route_test.dart
flutter analyze lib/core/workspace lib/features/admin/presentation/widgets
git diff --check
```

Expected: all selected tests and analyzer PASS; production god owner count is ready for the final exact `11 -> 0` recount.
