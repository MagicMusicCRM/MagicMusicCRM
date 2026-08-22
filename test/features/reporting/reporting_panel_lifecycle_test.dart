import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart'
    as export_files;
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_data_source.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart'
    as models;
import 'package:magic_music_crm/features/manager/presentation/widgets/reporting_v4_panel.dart';
import 'package:flutter_riverpod/legacy.dart';

final _activeReportingSourceProvider = StateProvider<ReportingDataSource?>(
  (ref) => null,
);

void main() {
  testWidgets(
    'same-version account replacement cannot reuse stale finance access',
    (tester) async {
      final source = _LifecycleReportingSource(label: 'A status');
      final inputs = ValueNotifier(
        _PanelInputs(snapshot: _snapshot('account-a', 1, finance: true)),
      );
      addTearDown(inputs.dispose);

      await tester.pumpWidget(_fixedSourceApp(source, inputs));
      await tester.pumpAndSettle();
      expect(source.financeCalls, 1);

      inputs.value = _PanelInputs(
        snapshot: _snapshot('account-b', 1, finance: false),
        reloadToken: 1,
      );
      await tester.pumpAndSettle();

      expect(source.financeCalls, 1);
      expect(
        find.byKey(const ValueKey('dashboard-finance-section')),
        findsNothing,
      );
      expect(source.statusCalls, 2);
    },
  );

  testWidgets(
    'finance revoke clears detail and starts no new finance request',
    (tester) async {
      final source = _LifecycleReportingSource(label: 'A status');
      final inputs = ValueNotifier(
        _PanelInputs(snapshot: _snapshot('account-a', 1, finance: true)),
      );
      addTearDown(inputs.dispose);

      await tester.pumpWidget(_fixedSourceApp(source, inputs));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('2026-08-01'), 250);
      await tester.tap(find.text('2026-08-01'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reporting-finance-detail')),
        findsOneWidget,
      );

      inputs.value = _PanelInputs(
        snapshot: _snapshot('account-a', 2, finance: false),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reporting-finance-detail')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('dashboard-finance-section')),
        findsNothing,
      );
      expect(source.financeCalls, 1);
    },
  );

  testWidgets('provider identity replacement owns every subsequent load', (
    tester,
  ) async {
    final sourceA = _LifecycleReportingSource(
      label: 'A status',
      holdSummaries: true,
    );
    final sourceB = _LifecycleReportingSource(
      label: 'B status',
      statusFailures: 1,
    );
    final container = _reactiveContainer(sourceA);
    addTearDown(container.dispose);

    await tester.pumpWidget(_reactiveSourceApp(container));
    await tester.pump();
    expect(sourceA.statusCalls, 1);

    container.read(_activeReportingSourceProvider.notifier).state = sourceB;
    await tester.pump();
    await tester.pump();
    expect(sourceB.statusCalls, 1);
    expect(sourceB.financeCalls, 1);

    sourceA.completeHeldSummaries();
    await tester.pumpAndSettle();
    expect(find.text('A status'), findsNothing);

    await tester.scrollUntilVisible(find.text('Повторить'), 250);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(sourceA.statusCalls, 1);
    expect(sourceB.statusCalls, 2);
    expect(find.text('B status'), findsOneWidget);
  });

  testWidgets(
    'input generation rejects late drilldown and export side effects',
    (tester) async {
      final sourceA = _LifecycleReportingSource(
        label: 'A status',
        holdDrilldown: true,
        holdExportRequest: true,
      );
      final sourceB = _LifecycleReportingSource(label: 'B status');
      final container = _reactiveContainer(sourceA);
      addTearDown(container.dispose);
      var openerCalls = 0;

      await tester.pumpWidget(
        _reactiveSourceApp(
          container,
          opener: (bytes, filename) async {
            openerCalls++;
            return export_files.ReportFileOpenResult(
              path: filename,
              opened: true,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'XLSX'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('A status'), 250);
      await tester.tap(find.text('A status'));
      await tester.pump();
      expect(sourceA.drilldownCalls, 1);
      expect(sourceA.exportCalls, 1);

      container.read(_activeReportingSourceProvider.notifier).state = sourceB;
      await tester.pump();
      await tester.pump();
      sourceA.completeDrilldown('Старый клиент');
      sourceA.completeExportRequest();
      await tester.pumpAndSettle();

      expect(openerCalls, 0);
      expect(find.text('Старый клиент'), findsNothing);
      expect(find.byKey(const ValueKey('reporting-drilldown')), findsNothing);
      expect(
        find.byKey(const ValueKey('report-export-progress')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('report-export-error')), findsNothing);
      expect(find.text('B status'), findsOneWidget);
    },
  );
}

CapabilitySnapshot _snapshot(
  String accountId,
  int version, {
  required bool finance,
}) => CapabilitySnapshot(
  accountId: accountId,
  role: 'director',
  accessVersion: version,
  capabilities: {
    'report.status.read',
    'crm.client.read.basic',
    if (finance) 'commerce.school_finance.read',
  },
  scopes: const {},
);

class _PanelInputs {
  const _PanelInputs({required this.snapshot, this.reloadToken = 0});

  final CapabilitySnapshot snapshot;
  final int reloadToken;
}

Widget _fixedSourceApp(
  ReportingDataSource source,
  ValueNotifier<_PanelInputs> inputs,
) => ProviderScope(
  overrides: [reportingDataSourceProvider.overrideWithValue(source)],
  child: MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<_PanelInputs>(
        valueListenable: inputs,
        builder: (context, value, child) => ReportingV4Panel(
          role: 'director',
          accessSnapshot: value.snapshot,
          reloadToken: value.reloadToken,
        ),
      ),
    ),
  ),
);

ProviderContainer _reactiveContainer(ReportingDataSource source) =>
    ProviderContainer(
      overrides: [
        _activeReportingSourceProvider.overrideWith((ref) => source),
        reportingDataSourceProvider.overrideWith(
          (ref) => ref.watch(_activeReportingSourceProvider)!,
        ),
      ],
    );

Widget _reactiveSourceApp(
  ProviderContainer container, {
  export_files.ReportFileOpener? opener,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: ProviderScope(
        overrides: [
          if (opener != null)
            export_files.reportFileOpenerProvider.overrideWithValue(opener),
        ],
        child: ReportingV4Panel(
          role: 'director',
          accessSnapshot: _snapshot('account-a', 1, finance: true),
        ),
      ),
    ),
  ),
);

class _LifecycleReportingSource implements ReportingDataSource {
  _LifecycleReportingSource({
    required this.label,
    this.holdSummaries = false,
    this.holdDrilldown = false,
    this.holdExportRequest = false,
    this.statusFailures = 0,
  });

  final String label;
  final bool holdSummaries;
  final bool holdDrilldown;
  final bool holdExportRequest;
  int statusFailures;

  int statusCalls = 0;
  int lessonCalls = 0;
  int taskCalls = 0;
  int financeCalls = 0;
  int drilldownCalls = 0;
  int exportCalls = 0;

  final _heldStatus = <Completer<Map<String, dynamic>>>[];
  final _heldLessons = <Completer<Map<String, dynamic>>>[];
  final _heldTasks = <Completer<Map<String, dynamic>>>[];
  final _heldFinance = <Completer<Map<String, dynamic>>>[];
  Completer<Map<String, dynamic>>? _drilldown;
  Completer<V4ReportExportResult>? _exportRequest;

  @override
  Future<Map<String, dynamic>> loadClientStatus(models.DashboardFilter filter) {
    statusCalls++;
    if (holdSummaries) {
      final result = Completer<Map<String, dynamic>>();
      _heldStatus.add(result);
      return result.future;
    }
    if (statusFailures > 0) {
      statusFailures--;
      return Future.error(StateError('status unavailable'));
    }
    return Future.value(_statusPayload);
  }

  @override
  Future<Map<String, dynamic>> loadLessonSuccess(
    models.DashboardFilter filter,
  ) {
    lessonCalls++;
    if (holdSummaries) {
      final result = Completer<Map<String, dynamic>>();
      _heldLessons.add(result);
      return result.future;
    }
    return Future.value(_lessonPayload);
  }

  @override
  Future<Map<String, dynamic>> loadOpenTaskSummary() {
    taskCalls++;
    if (holdSummaries) {
      final result = Completer<Map<String, dynamic>>();
      _heldTasks.add(result);
      return result.future;
    }
    return Future.value(_taskPayload);
  }

  @override
  Future<Map<String, dynamic>> loadSchoolFinance(
    models.DashboardFilter filter,
  ) {
    financeCalls++;
    if (holdSummaries) {
      final result = Completer<Map<String, dynamic>>();
      _heldFinance.add(result);
      return result.future;
    }
    return Future.value(_financePayload);
  }

  @override
  Future<Map<String, dynamic>> loadDrilldown(
    EntityLink link,
    models.DashboardFilter filter,
  ) {
    drilldownCalls++;
    if (!holdDrilldown) {
      return Future.value(_drilldownPayload('Текущий клиент'));
    }
    _drilldown = Completer<Map<String, dynamic>>();
    return _drilldown!.future;
  }

  @override
  Future<V4ReportExportResult> requestExport({
    required String reportKey,
    required String format,
    required Map<String, dynamic> filter,
  }) {
    exportCalls++;
    if (!holdExportRequest) {
      return Future.value(
        const V4ReportExportResult.sync(
          bytes: [0x50, 0x4b, 0x03, 0x04],
          filename: 'report.xlsx',
        ),
      );
    }
    _exportRequest = Completer<V4ReportExportResult>();
    return _exportRequest!.future;
  }

  @override
  Future<V4ReportExportJob> getExportJob(String jobId) =>
      throw UnimplementedError();

  @override
  Future<List<int>> downloadExport(String jobId) => throw UnimplementedError();

  void completeHeldSummaries() {
    for (final result in _heldStatus) {
      result.complete(_statusPayload);
    }
    for (final result in _heldLessons) {
      result.complete(_lessonPayload);
    }
    for (final result in _heldTasks) {
      result.complete(_taskPayload);
    }
    for (final result in _heldFinance) {
      result.complete(_financePayload);
    }
  }

  void completeDrilldown(String displayName) {
    _drilldown!.complete(_drilldownPayload(displayName));
  }

  void completeExportRequest() {
    _exportRequest!.complete(
      const V4ReportExportResult.sync(
        bytes: [0x50, 0x4b, 0x03, 0x04],
        filename: 'old-report.xlsx',
      ),
    );
  }

  Map<String, dynamic> get _statusPayload => {
    'items': [
      {
        'clientType': 'lead',
        'status': 'new',
        'label': label,
        'count': 1,
        'drilldown': {
          'entityType': 'client_status_list',
          'entityId': 'lead:new',
          'optionalFocus': {
            'filter': {'version': 1, 'clientType': 'lead', 'status': 'new'},
          },
        },
      },
    ],
  };

  Map<String, dynamic> get _lessonPayload => const {
    'totalLessons': 1,
    'successfulLessons': 1,
    'successRate': 1.0,
  };

  Map<String, dynamic> get _taskPayload => const {
    'counters': {'open': 1, 'overdue': 0},
  };

  Map<String, dynamic> get _financePayload => const {
    'rows': [
      {
        'monthStart': '2026-08-01',
        'revenueMinor': '10000',
        'expensesMinor': '1000',
        'successfulLessons': 1,
        'link': {
          'entityType': 'school_finance_month',
          'entityId': '2026-08-01',
        },
      },
    ],
  };

  Map<String, dynamic> _drilldownPayload(String displayName) => {
    'total': 1,
    'items': [
      {
        'displayName': displayName,
        'statusLabel': 'Новый',
        'entityLink': {'entityType': 'student', 'entityId': 'student-1'},
      },
    ],
  };
}
