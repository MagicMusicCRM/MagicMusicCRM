# Reporting Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `ReportingV4Panel` god state with a capability-named reporting surface while preserving the real `/analytics/v4` contract and all export/drilldown behavior.

**Architecture:** Keep V4 names only on route-bound service methods and DTOs. A typed presentation data source feeds a revision-guarded controller; file export orchestration and pure views are independent, and `ReportingPanel` owns RBAC-aware composition without direct section orchestration.

**Tech Stack:** Flutter, Dart, Riverpod, OpenFileX, path_provider, Flutter tests, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-22-systematic-codebase-cleanup-design.md`

**Depends on:** `2026-08-22-cleanup-foundation.md` completed.

## Global Constraints

- Preserve `/analytics/v4/*` routes, `getV4*`, `requestV4ReportExport`, `V4ReportExportResult`, and `V4ReportExportJob` names.
- Preserve filters, role/capability checks, partial section loading, retained successful data, entity links, CSV/XLSX validation, polling, save/open behavior, and Russian messages.
- Forbidden UI must not start a request; finance remains limited to Director/system_admin or the authoritative capability snapshot.
- Run focused tests, RepoWise update, and both Sentrux commands after every task. Rules stay `PASS`; quality/depth regressions block the next task.
- One behavior-neutral task per commit; do not rename the panel until its collaborators exist.
- If a committed cut fails its gate, stop and use a separate `git revert` or corrective commit; never use `git reset --hard`.

---

### Task 1: Extract reporting contracts and data source

**Files:**
- Create: `lib/features/manager/presentation/reporting/reporting_models.dart`
- Create: `lib/features/manager/presentation/reporting/reporting_data_source.dart`
- Create: `test/features/reporting/reporting_data_source_test.dart`
- Modify: `lib/features/manager/presentation/widgets/reporting_v4_panel.dart`
- Verify: `test/features/v4/reporting_drilldown_test.dart`

**Interfaces:**
- Produces unchanged `DashboardFilter`, `ReportFileOpenResult`, `ReportFileOpener`, and `validateReportExportBytes` in focused files.
- Produces `ReportingDataSource` and `MagicCrmReportingDataSource(Ref ref)` wrapping the existing V4 service calls.

- [ ] **Step 1: Write a failing data-source contract test**

```dart
test('dashboard filter maps exact analytics query keys', () {
  final filter = DashboardFilter(
    from: DateTime(2026, 8, 1),
    to: DateTime(2026, 8, 22),
    branchId: 'branch-1',
  );
  expect(filter.apiFilter, {
    'from': '2026-08-01T00:00:00.000',
    'to': '2026-08-22T00:00:00.000',
    'branchId': 'branch-1',
  });
});
```

Add a recording adapter test proving status, lesson, task, and finance calls
receive the same filter values as the monolith.

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/reporting/reporting_data_source_test.dart
```

Expected: compilation fails because reporting contracts are not extracted.

- [ ] **Step 3: Move contracts and add the thin service adapter**

```dart
abstract interface class ReportingDataSource {
  Future<Map<String, dynamic>> loadClientStatus(DashboardFilter filter);
  Future<Map<String, dynamic>> loadLessonSuccess(DashboardFilter filter);
  Future<Map<String, dynamic>> loadTaskSummary(DashboardFilter filter);
  Future<Map<String, dynamic>> loadSchoolFinance(DashboardFilter filter);
  Future<Map<String, dynamic>> loadDrilldown(
    EntityLink link,
    DashboardFilter filter,
  );
  Future<V4ReportExportResult> requestExport({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
  });
  Future<V4ReportExportJob> getExportJob(String jobId);
  Future<List<int>> downloadExport(String jobId);
}
```

The adapter delegates to the current `MagicCrmService` methods; it does not
translate or rename V4 route-bound DTOs.

- [ ] **Step 4: Verify adapter and current panel**

```powershell
dart format lib/features/manager/presentation/reporting test/features/reporting/reporting_data_source_test.dart
flutter test test/features/reporting/reporting_data_source_test.dart test/features/v4/reporting_drilldown_test.dart
flutter analyze lib/features/manager/presentation/reporting lib/features/manager/presentation/widgets/reporting_v4_panel.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: exact V4 calls remain and the current UI suite stays green.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/reporting lib/features/manager/presentation/widgets/reporting_v4_panel.dart test/features/reporting/reporting_data_source_test.dart
git commit -m "refactor(reporting): extract analytics data boundary"
```

### Task 2: Isolate report export orchestration

**Files:**
- Create: `lib/features/manager/presentation/reporting/report_export_coordinator.dart`
- Create: `test/features/reporting/report_export_coordinator_test.dart`
- Modify: `lib/features/manager/presentation/widgets/reporting_v4_panel.dart`

**Interfaces:**
- Consumes `ReportingDataSource`, `ReportFileOpener`, `Duration pollInterval`, and `Future<void> Function(Duration)` delay.
- Produces `Future<ReportExportOutcome> export({reportKey, format, filter})` and immutable progress/outcome models.

- [ ] **Step 1: Write RED tests for sync, async, corrupt, and failed exports**

```dart
test('polls async export and opens downloaded bytes once', () async {
  final source = FakeReportingDataSource.asyncJob(
    statuses: ['queued', 'running', 'completed'],
    bytes: validCsvBytes,
  );
  final opened = <String>[];
  final coordinator = ReportExportCoordinator(
    dataSource: source,
    opener: (bytes, filename) async {
      opened.add(filename);
      return ReportFileOpenResult(path: filename, opened: true);
    },
    delay: (_) async {},
  );
  final result = await coordinator.export(
    reportKey: 'client-status',
    format: 'csv',
    filter: DashboardFilter.defaults().apiFilter,
  );
  expect(result.opened, isTrue);
  expect(source.jobReads, 3);
  expect(opened, hasLength(1));
});
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/reporting/report_export_coordinator_test.dart
```

Expected: compilation fails on missing coordinator.

- [ ] **Step 3: Move polling and file handling behind the coordinator**

```dart
@immutable
class ReportExportOutcome {
  const ReportExportOutcome({
    required this.path,
    required this.filename,
    required this.opened,
  });
  final String path;
  final String filename;
  final bool opened;
}

class ReportExportCoordinator {
  ReportExportCoordinator({
    required this.dataSource,
    required this.opener,
    this.pollInterval = const Duration(seconds: 1),
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;

  final ReportingDataSource dataSource;
  final ReportFileOpener opener;
  final Duration pollInterval;
  final Future<void> Function(Duration) delay;

  Future<ReportExportOutcome> export({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
  }) async {
    final requested = await dataSource.requestExport(
      reportKey: reportKey,
      format: format,
      filter: filter,
    );
    if (!requested.isAsync) {
      return _open(requested.bytes!, requested.filename!, format);
    }
    final jobId = requested.jobId!;
    for (var attempt = 0; attempt < 120; attempt++) {
      await delay(pollInterval);
      final job = await dataSource.getExportJob(jobId);
      if (job.status == 'failed' || job.status == 'expired') {
        throw StateError(job.errorCode ?? 'Экспорт недоступен');
      }
      if (job.downloadReady) {
        final bytes = await dataSource.downloadExport(jobId);
        return _open(bytes, job.filename ?? 'report.$format', format);
      }
    }
    throw TimeoutException('Экспорт занимает слишком много времени.');
  }

  Future<ReportExportOutcome> _open(
    List<int> bytes,
    String filename,
    String format,
  ) async {
    validateReportExportBytes(bytes, format);
    final opened = await opener(bytes, filename);
    return ReportExportOutcome(
      path: opened.path,
      filename: filename,
      opened: opened.opened,
    );
  }
}
```

The panel observes progress callbacks/state but contains no polling loop or
filesystem/OpenFileX calls after this task.

- [ ] **Step 4: Verify exports and quality gates**

```powershell
dart format lib/features/manager/presentation/reporting/report_export_coordinator.dart test/features/reporting/report_export_coordinator_test.dart
flutter test test/features/reporting/report_export_coordinator_test.dart test/features/v4/reporting_drilldown_test.dart
flutter analyze lib/features/manager/presentation/reporting/report_export_coordinator.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: all export paths pass without real waits or filesystem effects in tests.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/reporting/report_export_coordinator.dart lib/features/manager/presentation/widgets/reporting_v4_panel.dart test/features/reporting/report_export_coordinator_test.dart
git commit -m "refactor(reporting): isolate report export workflow"
```

### Task 3: Move section orchestration into a controller

**Files:**
- Create: `lib/features/manager/presentation/reporting/reporting_controller.dart`
- Create: `test/features/reporting/reporting_controller_test.dart`
- Modify: `lib/features/manager/presentation/widgets/reporting_v4_panel.dart`

**Interfaces:**
- Produces `ReportingSection<T>`, `ReportingState`, and revision-guarded `ReportingController`.
- Consumes `ReportingDataSource`, access booleans, and `DashboardFilter`.

- [ ] **Step 1: Write RED tests for RBAC and partial failure**

```dart
test('forbidden school finance never starts a request', () async {
  final source = RecordingReportingDataSource();
  final controller = ReportingController(
    dataSource: source,
    canReadStatus: true,
    canReadSchoolFinance: false,
  );
  await controller.load(DashboardFilter.defaults());
  expect(source.financeCalls, 0);
  expect(controller.state.finance.forbidden, isTrue);
});

test('one failed section does not clear successful sections', () async {
  final source = RecordingReportingDataSource(
    status: {'count': 3},
    lessonError: StateError('offline'),
  );
  final controller = ReportingController(
    dataSource: source,
    canReadStatus: true,
    canReadSchoolFinance: false,
  );
  await controller.load(DashboardFilter.defaults());
  expect(controller.state.status.data?['count'], 3);
  expect(controller.state.lessons.error, isA<StateError>());
});
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/reporting/reporting_controller_test.dart
```

Expected: compilation fails because controller/state types are missing.

- [ ] **Step 3: Implement independent section states and latest-filter wins**

```dart
enum ReportingSectionKey { status, lessons, tasks, finance }

@immutable
class ReportingSection<T> {
  const ReportingSection({this.data, this.loading = false, this.error, this.forbidden = false});
  final T? data;
  final bool loading;
  final Object? error;
  final bool forbidden;
}

@immutable
class ReportingState {
  const ReportingState({
    required this.status,
    required this.lessons,
    required this.tasks,
    required this.finance,
  });
  factory ReportingState.initial() => const ReportingState(
    status: ReportingSection<Map<String, dynamic>>(),
    lessons: ReportingSection<Map<String, dynamic>>(),
    tasks: ReportingSection<Map<String, dynamic>>(),
    finance: ReportingSection<Map<String, dynamic>>(),
  );
  final ReportingSection<Map<String, dynamic>> status;
  final ReportingSection<Map<String, dynamic>> lessons;
  final ReportingSection<Map<String, dynamic>> tasks;
  final ReportingSection<Map<String, dynamic>> finance;
}

class ReportingController extends ChangeNotifier {
  ReportingController({
    required this.dataSource,
    required this.canReadStatus,
    required this.canReadSchoolFinance,
  });
  final ReportingDataSource dataSource;
  final bool canReadStatus;
  final bool canReadSchoolFinance;
  ReportingState state = ReportingState.initial();
  int _revision = 0;
  Future<void> load(DashboardFilter filter) async {
    final revision = ++_revision;
    await Future.wait([
      if (canReadStatus)
        _loadSection(revision, ReportingSectionKey.status,
            () => dataSource.loadClientStatus(filter)),
      if (canReadStatus)
        _loadSection(revision, ReportingSectionKey.lessons,
            () => dataSource.loadLessonSuccess(filter)),
      if (canReadStatus)
        _loadSection(revision, ReportingSectionKey.tasks,
            () => dataSource.loadTaskSummary(filter)),
      if (canReadSchoolFinance)
        _loadSection(revision, ReportingSectionKey.finance,
            () => dataSource.loadSchoolFinance(filter)),
    ]);
  }
}
```

Implement `_loadSection` as the single state-update seam: mark only its target
section loading, await the loader, ignore the result when `revision != _revision`,
retain prior `data` on failure, set that section's `error`, and notify listeners.

Move `_load`, `_loadStatus`, `_loadLessons`, `_loadTasks`, `_loadFinance`, and
`_loadSection`. Keep BuildContext navigation and export UI outside the controller.

- [ ] **Step 4: Verify orchestration and quality gates**

```powershell
dart format lib/features/manager/presentation/reporting/reporting_controller.dart test/features/reporting/reporting_controller_test.dart
flutter test test/features/reporting/reporting_controller_test.dart test/features/v4/reporting_drilldown_test.dart
flutter analyze lib/features/manager/presentation/reporting/reporting_controller.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: forbidden requests are zero; partial data survives section failures.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/reporting/reporting_controller.dart lib/features/manager/presentation/widgets/reporting_v4_panel.dart test/features/reporting/reporting_controller_test.dart
git commit -m "refactor(reporting): isolate dashboard orchestration"
```

### Task 4: Extract reporting views and drilldown navigation

**Files:**
- Create: `lib/features/manager/presentation/reporting/reporting_summary_view.dart`
- Create: `lib/features/manager/presentation/reporting/reporting_drilldown_view.dart`
- Create: `test/features/reporting/reporting_views_test.dart`
- Modify: `lib/features/manager/presentation/widgets/reporting_v4_panel.dart`

**Interfaces:**
- Produces pure summary/drilldown widgets using `ReportingState` and callbacks.
- No view file imports `MagicCrmService`, OpenFileX, path_provider, or Riverpod providers.

- [ ] **Step 1: Add pure-view tests**

```dart
testWidgets('drilldown forwards the canonical entity link', (tester) async {
  EntityLink? opened;
  await tester.pumpWidget(testApp(ReportingDrilldownView(
    rows: [drilldownRowFixture()],
    onOpenEntity: (link) => opened = link,
  )));
  await tester.tap(find.text('Открыть'));
  expect(opened?.entityType, 'student');
});
```

Cover loading, empty, error/retry, forbidden finance, status summary, lesson
summary, task summary, and finance row selection.

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/reporting/reporting_views_test.dart
```

Expected: compilation fails because view classes do not exist.

- [ ] **Step 3: Move build-only methods into pure widgets**

```dart
class ReportingSummaryView extends StatelessWidget {
  const ReportingSummaryView({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onOpenDrilldown,
    required this.onExport,
  });
}
```

Move `_section`, summary cards, finance chart/detail, header, error view, and
drilldown rendering. The panel retains navigation callbacks and controller ownership.

- [ ] **Step 4: Verify presentation boundary**

```powershell
rg -n "magicCrmServiceProvider|open_filex|path_provider" lib/features/manager/presentation/reporting/*view.dart
flutter test test/features/reporting/reporting_views_test.dart test/features/v4/reporting_drilldown_test.dart
flutter analyze lib/features/manager/presentation/reporting
repowise update --index-only
sentrux check
sentrux gate
```

Expected: `rg` returns no view-layer service/filesystem hits; tests and rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/reporting lib/features/manager/presentation/widgets/reporting_v4_panel.dart test/features/reporting/reporting_views_test.dart
git commit -m "refactor(reporting): split dashboard views"
```

### Task 5: Install `ReportingPanel` and remove the presentation V4 name

**Files:**
- Create: `lib/features/manager/presentation/reporting/reporting_panel.dart`
- Modify production importers in `reports_widget.dart` and `teacher_stats_widget.dart`.
- Move: `test/features/v4/reporting_drilldown_test.dart` to `test/features/reporting/reporting_drilldown_test.dart`
- Modify affected integration tests returned by `rg -l 'ReportingV4Panel|reporting_v4_panel' integration_test test lib`.
- Delete: `lib/features/manager/presentation/widgets/reporting_v4_panel.dart`
- Modify: `tool/naming_exceptions.json`

**Interfaces:**
- Produces `ReportingPanel` with the old public constructor parameters.
- Removes `ReportingV4Panel` and its file; route-bound V4 service names remain.

- [ ] **Step 1: Switch the canonical test to `ReportingPanel`**

```dart
await tester.pumpWidget(testApp(
  ReportingPanel(role: 'director', filter: filter),
));
expect(find.byType(ReportingPanel), findsOneWidget);
```

- [ ] **Step 2: Run and verify RED**

```powershell
flutter test test/features/reporting/reporting_drilldown_test.dart
```

Expected: compilation fails on the new panel import/symbol.

- [ ] **Step 3: Compose the canonical panel and update all callers**

```dart
class ReportingPanel extends ConsumerStatefulWidget {
  const ReportingPanel({
    super.key,
    required this.role,
    this.onOpenEntity,
    this.filter,
    this.reloadToken = 0,
    this.accessSnapshot,
  });
  final String role;
  final ValueChanged<EntityLink>? onOpenEntity;
  final DashboardFilter? filter;
  final int reloadToken;
  final CapabilitySnapshot? accessSnapshot;
}
```

The state owns `ReportingController` and `ReportExportCoordinator`, translates
capability snapshot to access booleans, and delegates rendering to the pure views.
It passes export filters as
`{...filter.apiFilter, ...?drilldownLink.optionalFocus?.filter}` so drilldown
exports keep the current narrowed dataset.

- [ ] **Step 4: Run complete Reporting gates**

```powershell
rg -n "ReportingV4Panel|reporting_v4_panel" lib test integration_test
rg -n "getV4|requestV4ReportExport|/analytics/v4" lib/core/services/magic_crm_service_finance.dart lib/features/manager/presentation/reporting
dart format lib/features/manager/presentation/reporting test/features/reporting
flutter test test/features/reporting test/features/manager/reports_tab_persistence_test.dart
flutter analyze lib/features/manager/presentation/reporting lib/features/manager/presentation/widgets/reports_widget.dart lib/features/manager/presentation/widgets/teacher_stats_widget.dart
dart run tool/check_repository_naming.dart
repowise update --index-only
sentrux check
sentrux gate
```

Expected: presentation V4 name is gone, V4 API contract remains, Sentrux quality
exceeds the plan-start baseline, and rules pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/manager/presentation/reporting lib/features/manager/presentation/widgets/reporting_v4_panel.dart lib/features/manager/presentation/widgets/reports_widget.dart lib/features/manager/presentation/widgets/teacher_stats_widget.dart test/features/reporting test/features/v4/reporting_drilldown_test.dart integration_test tool/naming_exceptions.json
git commit -m "refactor(reporting): install canonical reporting panel"
```
