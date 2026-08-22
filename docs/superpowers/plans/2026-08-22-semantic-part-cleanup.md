# Semantic Part Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate `views_a/views_b`, `tabs_a/tabs_b`, and `builders_a/builders_b` production files by regrouping existing code into named Schedule, Client Card, and Messenger responsibilities.

**Architecture:** This plan is a behavior-neutral semantic cut using the repository's current Dart `part` mechanism. Each new part owns a named surface or operation; action/orchestration methods do not remain in builder files, and no new cross-feature dependency is introduced.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter widget tests, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-22-systematic-codebase-cleanup-design.md`

**Depends on:** Foundation, Shared Tasks, and Reporting cleanup plans completed.

## Global Constraints

- Preserve every current method body, callback, key, route, payload, RBAC guard, retained-error behavior, and Russian UI text unless a test first proves a defect.
- A task may move declarations and update `part` directives only; product behavior changes require a separate approved task.
- No new file may end in `_a`, `_b`, `_c`, generic `_data`, or generic `_builders`.
- Run focused tests, analyzer, RepoWise update, and Sentrux check/gate after every task. Unexplained regression blocks the next task.
- One subsystem cut per commit; use `rg` before deletion to prove the old part and extension name have zero references.
- If a committed cut fails its gate, stop and use a separate `git revert` or corrective commit; never use `git reset --hard`.

---

### Task 1: Split Schedule toolbar and calendar surfaces

**Files:**
- Create: `lib/features/admin/presentation/widgets/schedule_widget_toolbar.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_widget_week_view.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_widget_room_day_view.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_widget_context_banners.dart`
- Modify: `lib/features/admin/presentation/widgets/schedule_widget.dart`
- Modify: `test/features/v4/schedule_regression_test.dart`
- Delete: `lib/features/admin/presentation/widgets/schedule_widget_views_a.dart`

**Interfaces:**
- Produces semantic private extensions on `_ScheduleWidgetState`; public `ScheduleWidget` API is unchanged.
- Task 2 consumes any private helpers moved here by their exact existing names.

- [ ] **Step 1: Add a source-ownership RED test**

```dart
test('schedule parts are named by surface', () {
  final owner = File('lib/features/admin/presentation/widgets/schedule_widget.dart')
      .readAsStringSync();
  expect(owner, isNot(contains("part 'schedule_widget_views_a.dart';")));
  expect(owner, contains("part 'schedule_widget_toolbar.dart';"));
  expect(owner, contains("part 'schedule_widget_week_view.dart';"));
  expect(owner, contains("part 'schedule_widget_room_day_view.dart';"));
});
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/v4/schedule_regression_test.dart
```

Expected: source-ownership assertion fails.

- [ ] **Step 3: Move exact method groups**

```dart
// schedule_widget_toolbar.dart
part of 'schedule_widget.dart';
extension _ScheduleToolbar on _ScheduleWidgetState {
  // _buildScheduleContent, _buildScheduleToolbar, _openLessonCreate,
  // _schedulePeriodLabel, _buildViewSwitcher, _switchView,
  // _buildBranchSelector, _editBranchTimezone, _buildDateNavigation,
  // _dateNavigationLabel.
}
```

Move `_buildWeekView` to `_ScheduleWeekView`; move `_buildDayView`,
`_buildDayViewByRoom`, `_durationMinutes` to `_ScheduleRoomDayView`; move
`_buildClientFilterBanner`, `_buildClientContextBanner`,
`_buildScheduleSearchBanner`, `_clientContextLegend`, and
`_buildAvailabilitySummary` to `_ScheduleContextBanners`. Do not edit bodies.

- [ ] **Step 4: Verify Schedule surfaces and quality**

```powershell
dart format lib/features/admin/presentation/widgets/schedule_widget*.dart
flutter test test/features/v4/schedule_regression_test.dart test/features/v6/production_workspace_mount_test.dart test/features/v6/client_schedule_calendar_test.dart
flutter analyze lib/features/admin/presentation/widgets/schedule_widget.dart lib/features/admin/presentation/widgets/schedule_widget_toolbar.dart lib/features/admin/presentation/widgets/schedule_widget_week_view.dart lib/features/admin/presentation/widgets/schedule_widget_room_day_view.dart lib/features/admin/presentation/widgets/schedule_widget_context_banners.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: behavior tests pass and Sentrux rules remain `PASS`.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/schedule_widget.dart lib/features/admin/presentation/widgets/schedule_widget_toolbar.dart lib/features/admin/presentation/widgets/schedule_widget_week_view.dart lib/features/admin/presentation/widgets/schedule_widget_room_day_view.dart lib/features/admin/presentation/widgets/schedule_widget_context_banners.dart lib/features/admin/presentation/widgets/schedule_widget_views_a.dart test/features/v4/schedule_regression_test.dart
git commit -m "refactor(schedule): name calendar parts by surface"
```

### Task 2: Split Schedule focus, teacher day, and lesson operations

**Files:**
- Create: `lib/features/admin/presentation/widgets/schedule_widget_focus.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_widget_teacher_day_view.dart`
- Move operation methods into existing: `lib/features/admin/presentation/widgets/schedule_widget_actions.dart`
- Modify: `lib/features/admin/presentation/widgets/schedule_widget.dart`
- Modify: `test/features/v4/schedule_regression_test.dart`
- Delete: `lib/features/admin/presentation/widgets/schedule_widget_views_b.dart`

**Interfaces:**
- Preserves `_ScheduleWidgetState` and all current operation signatures.
- Produces no new public symbols.

- [ ] **Step 1: Extend the source-ownership test**

```dart
expect(owner, isNot(contains('schedule_widget_views_b.dart')));
expect(owner, contains("part 'schedule_widget_focus.dart';"));
expect(owner, contains("part 'schedule_widget_teacher_day_view.dart';"));
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/v4/schedule_regression_test.dart
```

Expected: new ownership assertions fail.

- [ ] **Step 3: Move exact method groups**

```dart
// schedule_widget_focus.dart
part of 'schedule_widget.dart';
extension _ScheduleFocus on _ScheduleWidgetState {
  // _applyScheduleFocus, _armHighlightClear, _clearHighlight.
}
```

Move `_buildDayViewByTeacher` to `_ScheduleTeacherDayView`. Move
`_openLeadCreateFromSchedule`, `_openQuickCreate`, `_openWeekCreate`,
`_refreshEditedSchedule`, `_showLessonDetails`, `_editLesson`, `_cancelLesson`,
`_settleLesson`, and `_adjustLessonSettlement` into `_ScheduleActions` in the
existing actions part. Resolve duplicate extension names by keeping exactly one
`_ScheduleActions` declaration.

- [ ] **Step 4: Verify no mechanical Schedule part remains**

```powershell
rg -n "ScheduleViewsA|ScheduleViewsB|schedule_widget_views_[ab]" lib test
flutter test test/features/v4/schedule_regression_test.dart test/features/v4/lesson_form_test.dart test/features/v7/lesson_decision_flow_test.dart test/features/v7/recurring_schedule_plan_section_test.dart
flutter analyze lib/features/admin/presentation/widgets/schedule_widget*.dart
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: `rg` returns no hits and all focused tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/admin/presentation/widgets/schedule_widget.dart lib/features/admin/presentation/widgets/schedule_widget_focus.dart lib/features/admin/presentation/widgets/schedule_widget_teacher_day_view.dart lib/features/admin/presentation/widgets/schedule_widget_actions.dart lib/features/admin/presentation/widgets/schedule_widget_views_a.dart lib/features/admin/presentation/widgets/schedule_widget_views_b.dart test/features/v4/schedule_regression_test.dart
git commit -m "refactor(schedule): separate focus and lesson operations"
```

### Task 3: Replace `client_card_data.dart` with named responsibilities

**Files:**
- Create: `client_card_internal_context.dart`, `client_card_counterpart_resolution.dart`, `client_card_loaders.dart`, `client_card_realtime.dart`, `client_card_persistence.dart` under `lib/features/crm/presentation/client_card/`.
- Modify: `lib/features/crm/presentation/client_card/client_card.dart`
- Modify: `test/features/crm/client_card/client_card_save_payload_test.dart`
- Delete: `lib/features/crm/presentation/client_card/client_card_data.dart`

**Interfaces:**
- Preserves private `_ClientCardState` method signatures and the public `ClientCard` contract.
- Produces semantic part ownership only; no new runtime model or API call.

- [ ] **Step 1: Add ownership and behavior assertions**

```dart
test('client card data responsibilities have semantic parts', () {
  final owner = File('lib/features/crm/presentation/client_card/client_card.dart')
      .readAsStringSync();
  expect(owner, isNot(contains("part 'client_card_data.dart';")));
  for (final part in const [
    'client_card_internal_context.dart',
    'client_card_counterpart_resolution.dart',
    'client_card_loaders.dart',
    'client_card_realtime.dart',
    'client_card_persistence.dart',
  ]) {
    expect(owner, contains("part '$part';"));
  }
});
```

Retain existing payload assertions for typed custom fields, core fields, version,
duplicate attachment, and close-on-success.

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/crm/client_card/client_card_save_payload_test.dart
```

Expected: ownership assertions fail.

- [ ] **Step 3: Move exact method groups without editing bodies**

```text
internal_context: _fetchInternalContext, _saveInternalNote,
                  _reloadOperationalHistory, _loadMoreOperationalHistory
counterpart_resolution: _resolveLeadCounterpart, _resolveStudentCounterpart,
                        _hasLinkedStudent
loaders: _fetchStudentData, _fetchStatuses, _fetchCard,
         _fetchDuplicateCandidates, _fetchStatusHistory, _fetchFamily,
         _fetchClientAccess, _fetchMetadata
realtime: _scheduleRealtimeRefresh, _refreshFromRealtime
persistence: _save, _emptyTypedCustomValue, _persistEdits,
             _linkExistingStudent, _updateCustomDataForEntity,
             _attachDuplicateCandidate
```

Each file declares one private extension named after its responsibility.

- [ ] **Step 4: Verify Client Card behavior and graph**

```powershell
rg -n "client_card_data|_ClientCardData" lib test
dart format lib/features/crm/presentation/client_card
flutter test test/features/crm/client_card/client_card_save_payload_test.dart test/features/crm/client_card/client_card_family_access_test.dart test/features/crm/client_card/client_card_contact_person_options_test.dart test/features/v4/client_card_roles_test.dart
flutter analyze lib/features/crm/presentation/client_card
repowise update --index-only
sentrux check
sentrux gate
```

Expected: old part is absent, payloads and UI behavior are unchanged.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/crm/presentation/client_card test/features/crm/client_card/client_card_save_payload_test.dart
git commit -m "refactor(client-card): name data responsibilities"
```

### Task 4: Replace Client Card tabs A/B with surface names

**Files:**
- Create semantic parts under `lib/features/crm/presentation/client_card/`: `client_card_header.dart`, `client_card_overview_tab.dart`, `client_card_tasks_tab.dart`, `client_card_collaboration_tabs.dart`, `client_card_presentation.dart`.
- Modify: `lib/features/crm/presentation/client_card/client_card.dart`
- Modify: `test/features/v7/client_card_action_inventory_test.dart`
- Delete: `client_card_tabs_a.dart`, `client_card_tabs_b.dart`

**Interfaces:**
- Preserves every private method signature and public card surface.
- No tab owns service orchestration; it calls existing state methods/callbacks.

- [ ] **Step 1: Add source ownership and action inventory assertions**

```dart
expect(clientCardSource, isNot(contains('client_card_tabs_a.dart')));
expect(clientCardSource, isNot(contains('client_card_tabs_b.dart')));
expect(clientCardSource, contains('client_card_overview_tab.dart'));
expect(clientCardSource, contains('client_card_collaboration_tabs.dart'));
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/v7/client_card_action_inventory_test.dart
```

Expected: ownership assertions fail.

- [ ] **Step 3: Move exact method groups**

```text
header: _isBlacklisted, _blacklistReason, _buildBlacklistBanner, _buildHeader,
        _buildTabBar, _buildTabChip, _buildActionBar
overview_tab: _buildClientInfoTab, _buildClientInfoContent, _hhField,
              _stringifyCustom, _responsibleLabel, _visitDateLabel
tasks_tab: _buildTasksTab, _openScheduleFromCard
collaboration_tabs: _buildCommentsTab, _buildFamilyTab, _buildFamilyAddButton,
                    _buildClientAccessSection, _buildHistoryTab
presentation: _nonEmpty, client name/contact/source/branch getters,
              _clientPresentationLabel, _syncWorkspaceTitle, _updateClientCore,
              _refreshLedger, age/appeal labels, balance color,
              _buildStudentHeader
```

- [ ] **Step 4: Verify Client Card surfaces**

```powershell
rg -n "ClientCardTabsA|ClientCardTabsB|client_card_tabs_[ab]" lib test
flutter test test/features/v7/client_card_action_inventory_test.dart test/features/crm/client_card/client_card_family_access_test.dart test/features/crm/client_card/client_card_task_expand_test.dart test/features/crm/client_card/client_card_student_action_bar_test.dart
flutter analyze lib/features/crm/presentation/client_card
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: old A/B parts have zero references and behavior tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/crm/presentation/client_card test/features/v7/client_card_action_inventory_test.dart
git commit -m "refactor(client-card): name tab surfaces"
```

### Task 5: Replace Messenger builders A/B with shell and conversation parts

**Files:**
- Create: `messenger_screen_shell.dart`, `messenger_screen_chat_list.dart`, `messenger_screen_conversation_view.dart`, `messenger_screen_pinned_messages.dart`, `messenger_screen_search.dart` under `lib/features/messenger/presentation/screens/`.
- Modify: `messenger_screen.dart`, `messenger_screen_actions.dart`.
- Modify: `test/features/messenger/inbox_logic_test.dart`, `test/features/messenger/chat_archive_test.dart`.
- Delete: `messenger_screen_builders_a.dart`, `messenger_screen_builders_b.dart`.
- Modify: `tool/naming_exceptions.json`.

**Interfaces:**
- Preserves `_MessengerScreenState`, public `MessengerScreen`, and all current callbacks.
- Builders contain rendering only; forwarding, pinning, search, and fetch operations live in named action parts.

- [ ] **Step 1: Add source ownership assertions**

```dart
test('messenger parts are named by responsibility', () {
  final source = File('lib/features/messenger/presentation/screens/messenger_screen.dart')
      .readAsStringSync();
  expect(source, isNot(contains('messenger_screen_builders_a.dart')));
  expect(source, isNot(contains('messenger_screen_builders_b.dart')));
  expect(source, contains('messenger_screen_conversation_view.dart'));
  expect(source, contains('messenger_screen_search.dart'));
});
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/messenger/inbox_logic_test.dart test/features/messenger/chat_archive_test.dart
```

Expected: source ownership assertion fails.

- [ ] **Step 3: Move exact responsibilities**

```text
shell: _buildMessengerShell
chat_list: _buildChatList and chat-list-only builders
actions: _onForwardMessage
conversation_view: _buildChatView and message rendering helpers
pinned_messages: _buildPinnedBar, _showPinnedMessagesDialog,
                 _fetchPinnedMessages, _togglePin, _jumpToMessage
search: _onSearchInChat, _performSearch, _nextSearchMatch, _prevSearchMatch
```

Each new file has one private extension. Merge action methods into the existing
actions part only when that leaves one cohesive extension declaration.

- [ ] **Step 4: Run complete semantic-part gates**

```powershell
rg -n "BuildersA|BuildersB|builders_[ab]|tabs_[ab]|views_[ab]" lib test
dart format lib/features/messenger/presentation/screens
flutter test test/features/messenger test/features/v4/schedule_regression_test.dart test/features/v7/client_card_action_inventory_test.dart
flutter analyze lib/features/messenger/presentation/screens lib/features/admin/presentation/widgets lib/features/crm/presentation/client_card
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: all six ambiguous A/B files are gone; Sentrux quality exceeds the
plan-start baseline, depth does not increase, and rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/messenger/presentation/screens test/features/messenger tool/naming_exceptions.json
git commit -m "refactor(messenger): name presentation parts by responsibility"
```
