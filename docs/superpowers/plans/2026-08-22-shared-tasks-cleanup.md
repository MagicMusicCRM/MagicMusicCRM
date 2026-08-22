# Shared Tasks Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 2024-NLOC `SharedTasksV4Panel` hotspot with a controller-driven, capability-named task surface while preserving every task workflow and backend contract.

**Architecture:** Keep `MagicCrmService`, mutation identity, realtime, entity links, and backend RBAC authoritative. Extract contracts, orchestration, editor, details, and presentation in separate commits; `SharedTasksPanel` renders controller state and does not call services directly.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter tests, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-22-systematic-codebase-cleanup-design.md`

**Depends on:** `2026-08-22-cleanup-foundation.md` completed.

## Global Constraints

- Preserve task list/calendar filters, search, priority, scope, today mode, linked entity focus, audience preview, reminders, history, close behavior, realtime refresh, and Russian text.
- Preserve `MagicMutationIdentity`, expected version, idempotency headers, server-side audience/resource scope, and canonical entity navigation.
- Keep the last successful list visible during refresh errors; stale async responses must not overwrite the newest query.
- Run focused tests, `repowise update --index-only`, `sentrux check`, and `sentrux gate` after every task. Rules must stay `PASS`; unexplained quality/depth regressions stop execution.
- One task per commit; do not rename `SharedTasksV4Panel` until consumers use the extracted boundaries.
- If a committed cut fails its gate, stop and use a separate `git revert` or corrective commit; never use `git reset --hard`.

---

### Task 1: Extract task contracts and data source

**Files:**
- Create: `lib/features/manager/presentation/tasks/shared_tasks_models.dart`
- Create: `lib/features/manager/presentation/tasks/shared_tasks_data_source.dart`
- Create: `test/features/tasks/shared_tasks_data_source_test.dart`
- Modify: `lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart`
- Verify: `test/features/v4/shared_tasks_ui_test.dart`

**Interfaces:**
- Produces `SharedTasksDataSource` with the current `list`, `listFiltered`, `calendar`, `history`, `previewAudience`, `create`, `update`, `close`, and `audienceOptions` signatures.
- Produces `MagicCrmSharedTasksDataSource(Ref ref)` and `SharedTaskAudienceOption`.

- [ ] **Step 1: Write a failing adapter contract test**

```dart
class RecordingSharedTasksDataSource implements SharedTasksDataSource {
  String? requestedState;
  @override
  Future<Map<String, dynamic>> list({String? state, String? taskId,
      String? linkedEntityType, String? linkedEntityId}) async {
    requestedState = state;
    return {'items': <Map<String, dynamic>>[]};
  }
}

test('data source contract preserves state filtering', () async {
  final source = RecordingSharedTasksDataSource();
  await source.list(state: 'open');
  expect(source.requestedState, 'open');
});
```

In this test fake, `listFiltered` delegates to `list`, `calendar` returns
`<String, int>{}`, `history` returns `[]`, `previewAudience` returns
`{'count': 0, 'recipients': []}`, `create`/`update`/`close` return the supplied
task fixture, and `audienceOptions` returns `[]`.

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/tasks/shared_tasks_data_source_test.dart
```

Expected: compilation fails because the extracted contract does not exist.

- [ ] **Step 3: Move the existing interfaces and service adapter verbatim**

```dart
abstract interface class SharedTasksDataSource {
  Future<Map<String, dynamic>> list({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
  });
  Future<List<Map<String, dynamic>>> history(String taskId);
  Future<Map<String, dynamic>> previewAudience(
    List<Map<String, dynamic>> audiences,
  );
  Future<Map<String, dynamic>> create(
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );
  Future<Map<String, dynamic>> update(
    String taskId,
    Map<String, dynamic> data,
    MagicMutationIdentity identity,
  );
  Future<Map<String, dynamic>> close(
    String taskId,
    int expectedVersion,
    MagicMutationIdentity identity,
  );
  Future<List<SharedTaskAudienceOption>> audienceOptions();
  Future<Map<String, dynamic>> listFiltered({
    String? state,
    String? taskId,
    String? linkedEntityType,
    String? linkedEntityId,
    String? q,
    String? priority,
    String? scope,
    String? from,
    String? to,
  });
  Future<Map<String, int>> calendar({
    required String from,
    required String to,
    String? state,
    String? q,
    String? priority,
    String? scope,
    String? linkedEntityType,
    String? linkedEntityId,
  });
}
```

Move `_ServiceSharedTasksDataSource` to public
`MagicCrmSharedTasksDataSource`; its methods remain thin calls to
`magicCrmServiceProvider` and `magicProfileAdminServiceProvider`.

- [ ] **Step 4: Verify adapter and existing UI**

```powershell
dart format lib/features/manager/presentation/tasks test/features/tasks/shared_tasks_data_source_test.dart
flutter test test/features/tasks/shared_tasks_data_source_test.dart test/features/v4/shared_tasks_ui_test.dart
flutter analyze lib/features/manager/presentation/tasks lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: behavior is unchanged and the monolith no longer defines service contracts.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/tasks lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart test/features/tasks/shared_tasks_data_source_test.dart
git commit -m "refactor(tasks): extract shared task data boundary"
```

### Task 2: Move loading and filters into a controller

**Files:**
- Create: `lib/features/manager/presentation/tasks/shared_tasks_controller.dart`
- Create: `test/features/tasks/shared_tasks_controller_test.dart`
- Modify: `lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart`

**Interfaces:**
- Consumes `SharedTasksDataSource` and an optional `Stream<void> refreshes`.
- Produces immutable `SharedTasksQuery`, `SharedTasksState`, and `SharedTasksController extends ChangeNotifier`.

- [ ] **Step 1: Write controlled-async RED tests**

```dart
test('latest query wins when responses complete out of order', () async {
  final source = ControlledSharedTasksDataSource();
  final controller = SharedTasksController(dataSource: source);
  final first = controller.setQuery(const SharedTasksQuery(state: 'open'));
  final second = controller.setQuery(const SharedTasksQuery(state: 'closed'));
  source.complete('closed', {'items': [{'id': 'closed'}]});
  await second;
  source.complete('open', {'items': [{'id': 'open'}]});
  await first;
  expect(controller.state.query.state, 'closed');
  expect(controller.state.items.single['id'], 'closed');
});

test('refresh error retains last successful items', () async {
  final source = ControlledSharedTasksDataSource();
  final controller = SharedTasksController(dataSource: source);
  final loaded = controller.setQuery(const SharedTasksQuery(state: 'open'));
  source.complete('open', {'items': [{'id': 'kept'}]});
  await loaded;
  source.failNext(StateError('offline'));
  await controller.refresh();
  expect(controller.state.items.single['id'], 'kept');
  expect(controller.state.error, isA<StateError>());
});
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/tasks/shared_tasks_controller_test.dart
```

Expected: compilation fails on missing controller types.

- [ ] **Step 3: Implement a revision-guarded controller**

```dart
@immutable
class SharedTasksQuery {
  const SharedTasksQuery({
    this.state = 'open',
    this.taskId,
    this.linkedEntityType,
    this.linkedEntityId,
    this.search,
    this.priority,
    this.scope,
    this.from,
    this.to,
  });
  final String state;
  final String? taskId;
  final String? linkedEntityType;
  final String? linkedEntityId;
  final String? search;
  final String? priority;
  final String? scope;
  final String? from;
  final String? to;
}

@immutable
class SharedTasksState {
  const SharedTasksState({
    this.query = const SharedTasksQuery(),
    this.items = const [],
    this.calendar = const {},
    this.loading = false,
    this.error,
  });
  final SharedTasksQuery query;
  final List<Map<String, dynamic>> items;
  final Map<String, int> calendar;
  final bool loading;
  final Object? error;

  SharedTasksState copyWith({
    SharedTasksQuery? query,
    List<Map<String, dynamic>>? items,
    Map<String, int>? calendar,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) => SharedTasksState(
    query: query ?? this.query,
    items: items ?? this.items,
    calendar: calendar ?? this.calendar,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
  );
}

class SharedTasksController extends ChangeNotifier {
  SharedTasksController({required this.dataSource, Stream<void>? refreshes}) {
    _refreshSubscription = refreshes?.listen((_) => unawaited(refresh()));
  }
  final SharedTasksDataSource dataSource;
  StreamSubscription<void>? _refreshSubscription;
  SharedTasksState state = const SharedTasksState();
  int _revision = 0;

  Future<void> refresh() => setQuery(state.query);

  Future<void> setQuery(SharedTasksQuery query) async {
    final revision = ++_revision;
    state = state.copyWith(query: query, loading: true, clearError: true);
    notifyListeners();
    try {
      final result = await dataSource.listFiltered(
        state: query.state,
        taskId: query.taskId,
        linkedEntityType: query.linkedEntityType,
        linkedEntityId: query.linkedEntityId,
        q: query.search,
        priority: query.priority,
        scope: query.scope,
        from: query.from,
        to: query.to,
      );
      if (revision != _revision) return;
      final rawItems = result['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => item.map(
                    (key, value) => MapEntry(key.toString(), value),
                  ))
              .toList(growable: false)
          : <Map<String, dynamic>>[];
      state = state.copyWith(
        items: items,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      if (revision != _revision) return;
      state = state.copyWith(loading: false, error: error);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }
}
```

Move `_load`, calendar loading, filter setters, realtime subscription, and close
command orchestration into the controller. Dialog opening and `BuildContext`
remain in presentation.

- [ ] **Step 4: Verify controller and UI regression suite**

```powershell
dart format lib/features/manager/presentation/tasks/shared_tasks_controller.dart test/features/tasks/shared_tasks_controller_test.dart
flutter test test/features/tasks/shared_tasks_controller_test.dart test/features/v4/shared_tasks_ui_test.dart test/features/messenger/tasks_navigation_test.dart
flutter analyze lib/features/manager/presentation/tasks lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: reverse-order responses cannot replace the latest state; UI tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/tasks/shared_tasks_controller.dart lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart test/features/tasks/shared_tasks_controller_test.dart
git commit -m "refactor(tasks): isolate shared task orchestration"
```

### Task 3: Extract the task editor

**Files:**
- Create: `lib/features/manager/presentation/tasks/shared_task_editor.dart`
- Create: `test/features/tasks/shared_task_editor_test.dart`
- Modify: `lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart`
- Verify: `test/features/v4/shared_tasks_ui_test.dart`

**Interfaces:**
- Produces `Future<bool?> showSharedTaskEditor(...)` and preserves `showCreateSharedTask(...)` as the canonical public entry point.
- Consumes `SharedTasksDataSource`, optional task map, linked `EntityLink`, and `VoidCallback? onSaved`.

- [ ] **Step 1: Add editor characterization tests**

```dart
testWidgets('editor keeps mutation identity and expected version on update', (tester) async {
  final source = RecordingSharedTasksDataSource();
  await pumpEditor(tester, source: source, task: taskFixture(version: 7));
  await tester.tap(find.text('Сохранить'));
  await tester.pumpAndSettle();
  expect(source.updatedVersion, 7);
  expect(source.lastIdentity?.idempotencyKey, isNotEmpty);
});
```

Also retain create, audience preview, all-day/interval, reminder, recipient,
validation, error draft-retention, and successful-close assertions.

- [ ] **Step 2: Run and verify RED against the new import**

```powershell
flutter test test/features/tasks/shared_task_editor_test.dart
```

Expected: compilation fails because the extracted editor entry point is absent.

- [ ] **Step 3: Move editor-only widgets and helpers**

```dart
Future<bool?> showSharedTaskEditor(
  BuildContext context, {
  required SharedTasksDataSource dataSource,
  Map<String, dynamic>? task,
  EntityLink? linkedEntity,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => SharedTaskEditor(
      dataSource: dataSource,
      task: task,
      linkedEntity: linkedEntity,
    ),
  );
}
```

Move draft controllers, audience selection/preview, save payload construction,
date/time conversion, and validation. Do not move list filters or task details.

- [ ] **Step 4: Verify editor and quality gates**

```powershell
dart format lib/features/manager/presentation/tasks/shared_task_editor.dart test/features/tasks/shared_task_editor_test.dart
flutter test test/features/tasks/shared_task_editor_test.dart test/features/v4/shared_tasks_ui_test.dart
flutter analyze lib/features/manager/presentation/tasks/shared_task_editor.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: editor tests pass and Sentrux rules remain `PASS`.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/tasks/shared_task_editor.dart lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart test/features/tasks/shared_task_editor_test.dart
git commit -m "refactor(tasks): extract shared task editor"
```

### Task 4: Extract task details and presentation

**Files:**
- Create: `lib/features/manager/presentation/tasks/shared_task_details.dart`
- Create: `lib/features/manager/presentation/tasks/shared_tasks_view.dart`
- Create: `test/features/tasks/shared_task_details_test.dart`
- Modify: `lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart`

**Interfaces:**
- Produces `SharedTaskDetails` with history and linked-entity callbacks.
- Produces pure `SharedTasksView({state, onQueryChanged, onOpen, onClose, onCreate, onRetry})`.

- [ ] **Step 1: Add details and pure-view tests**

```dart
testWidgets('linked task opens canonical entity callback', (tester) async {
  EntityLink? opened;
  await tester.pumpWidget(testApp(SharedTaskDetails(
    task: linkedTaskFixture(),
    history: const [],
    onOpenEntity: (link) => opened = link,
  )));
  await tester.tap(find.text('Открыть карточку'));
  expect(opened?.entityType, 'student');
});
```

Test loading, retained-content error, empty, list, calendar, overdue, and closed
states using explicit `SharedTasksState` fixtures.

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/tasks/shared_task_details_test.dart
```

Expected: compilation fails because details/view classes are missing.

- [ ] **Step 3: Move view-only code and callbacks**

```dart
class SharedTasksView extends StatelessWidget {
  const SharedTasksView({
    super.key,
    required this.state,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onClose,
    required this.onCreate,
    required this.onRetry,
  });
}
```

No service/provider read is allowed in `SharedTasksView` or
`SharedTaskDetails`; async effects are callbacks owned by panel/controller.

- [ ] **Step 4: Verify presentation and graph**

```powershell
dart format lib/features/manager/presentation/tasks test/features/tasks/shared_task_details_test.dart
flutter test test/features/tasks/shared_task_details_test.dart test/features/tasks/shared_tasks_controller_test.dart test/features/v4/shared_tasks_ui_test.dart
flutter analyze lib/features/manager/presentation/tasks
repowise update --index-only
sentrux check
sentrux gate
```

Expected: pure views have no service imports; all tests and rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/tasks lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart test/features/tasks/shared_task_details_test.dart
git commit -m "refactor(tasks): split shared task presentation"
```

### Task 5: Replace `SharedTasksV4Panel` with the canonical panel

**Files:**
- Create: `lib/features/manager/presentation/tasks/shared_tasks_panel.dart`
- Modify all production importers returned by `rg -l 'SharedTasksV4Panel|shared_tasks_v4_panel' lib test integration_test`.
- Move: `test/features/v4/shared_tasks_ui_test.dart` to `test/features/tasks/shared_tasks_ui_test.dart`
- Delete: `lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart`
- Modify: `tool/naming_exceptions.json`

**Interfaces:**
- Produces `SharedTasksPanel` with the old constructor parameters unchanged except the class name.
- Removes `SharedTasksV4Panel` entirely; no typedef or deprecated forwarding file remains.

- [ ] **Step 1: Switch the canonical UI test to the new import and symbol**

```dart
await tester.pumpWidget(testApp(SharedTasksPanel(
  role: 'director',
  dataSource: fakeDataSource,
)));
expect(find.byType(SharedTasksPanel), findsOneWidget);
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/tasks/shared_tasks_ui_test.dart
```

Expected: compilation fails because `SharedTasksPanel` does not exist.

- [ ] **Step 3: Compose the canonical panel**

```dart
class SharedTasksPanel extends ConsumerStatefulWidget {
  const SharedTasksPanel({
    super.key,
    this.dataSource,
    this.embedded = false,
    this.initialLink,
    this.linkedEntity,
    this.scrollController,
    this.canWrite,
    this.defaultToMineToday = false,
  });
  final SharedTasksDataSource? dataSource;
  final bool embedded;
  final EntityLink? initialLink;
  final EntityLink? linkedEntity;
  final ScrollController? scrollController;
  final bool? canWrite;
  final bool defaultToMineToday;
}
```

The state creates/disposes `SharedTasksController`, delegates editor/details
opening, and builds `SharedTasksView`. Update client card, leads, staff workspace,
and messenger navigation imports directly.

- [ ] **Step 4: Run complete Shared Tasks gates**

```powershell
rg -n "SharedTasksV4|shared_tasks_v4_panel" lib test integration_test
dart format lib/features/manager/presentation/tasks test/features/tasks
flutter test test/features/tasks test/features/messenger/tasks_navigation_test.dart test/features/crm/client_card/client_card_task_expand_test.dart
flutter analyze lib/features/manager/presentation/tasks lib/features/crm/presentation lib/features/messenger/presentation
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: no old symbol/path remains; the old health `1.2` monolith is gone;
Sentrux quality is above the plan-start baseline and rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/tasks lib/features/manager/presentation/widgets/shared_tasks_v4_panel.dart lib/features/crm lib/features/messenger test/features/tasks test/features/v4/shared_tasks_ui_test.dart test/features/messenger integration_test tool/naming_exceptions.json
git commit -m "refactor(tasks): install canonical shared tasks panel"
```
