import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/security/capability_snapshot.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reporting_v4_panel.dart';

void main() {
  test('dashboard filter restores from workspace and direct-link state', () {
    final restored = DashboardFilter.fromContext(
      ContextViewState(
        filters: {
          'dashboardFrom': '2026-06-01T00:00:00.000',
          'dashboardTo': '2026-06-30T00:00:00.000',
          'branchId': '11111111-1111-4111-8111-111111111111',
        },
      ),
      const {'branchId': '22222222-2222-4222-8222-222222222222'},
    );

    expect(restored.from, DateTime(2026, 6, 1));
    expect(restored.to, DateTime(2026, 6, 30));
    expect(restored.branchId, '22222222-2222-4222-8222-222222222222');
    expect(
      DashboardFilter.fromContext(restored.toContextViewState(), null),
      restored,
    );
  });

  testWidgets('manager opens exact status drilldown and restores report', (
    tester,
  ) async {
    final api = _ReportingApi();
    EntityLink? opened;
    await tester.pumpWidget(
      _app(api, role: 'manager', onOpenEntity: (link) => opened = link),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reporting-content')), findsOneWidget);
    expect(find.text('Финансы школы'), findsNothing);
    await tester.tap(find.text('Новые'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reporting-drilldown')), findsOneWidget);
    expect(api.lastListFilter?['status'], 'new');
    expect(api.lastListFilter?['clientType'], 'lead');
    await tester.tap(find.text('Алина Тестова'));
    expect(opened?.entityId, 'student-1');

    await tester.tap(find.text('К отчёту'));
    await tester.pumpAndSettle();
    expect(find.text('Новые'), findsOneWidget);
  });

  testWidgets('lesson KPI opens source lessons with the same predicate', (
    tester,
  ) async {
    final api = _ReportingApi();
    EntityLink? opened;
    await tester.pumpWidget(
      _app(api, role: 'manager', onOpenEntity: (link) => opened = link),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Успешно завершённые занятия').first);
    await tester.pumpAndSettle();

    expect(find.text('Занятия: 8'), findsOneWidget);
    final summaryFilter = api.queries['/analytics/v4/lesson-success']!;
    final listFilter = api.queries['/analytics/v4/lesson-success/lessons']!;
    expect(listFilter['from'], summaryFilter['from']);
    expect(listFilter['to'], summaryFilter['to']);
    expect(listFilter['branchId'], summaryFilter['branchId']);
    await tester.tap(find.text('Урок Алины'));
    expect(opened?.rawEntityType, 'lesson');
    expect(opened?.entityId, 'lesson-1');
  });

  testWidgets('director sees finance and completes private async download', (
    tester,
  ) async {
    final api = _ReportingApi(asyncExport: true);
    String? filename;
    List<int>? openedBytes;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
          reportFileOpenerProvider.overrideWithValue((bytes, name) async {
            openedBytes = bytes;
            filename = name;
            return ReportFileOpenResult(path: 'C:/Reports/$name', opened: true);
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ReportingV4Panel(role: 'director')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Финансы школы'), 300);
    expect(find.text('Финансы школы'), findsOneWidget);
    await tester.tap(find.text('2026-07-01'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('reporting-finance-detail')),
      findsOneWidget,
    );
    await tester.tap(find.text('К отчёту'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'XLSX'));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();

    expect(api.jobPolls, greaterThanOrEqualTo(1));
    expect(filename, 'client-status.xlsx');
    expect(openedBytes, [0x50, 0x4b, 0x03, 0x04]);
    await tester.scrollUntilVisible(
      find.text('Файл открыт: client-status.xlsx'),
      300,
    );
    expect(find.text('Файл открыт: client-status.xlsx'), findsOneWidget);
  });

  testWidgets('rejects a corrupt XLSX before saving it', (tester) async {
    final api = _ReportingApi(corruptExport: true);
    var openerCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
          reportFileOpenerProvider.overrideWithValue((bytes, name) async {
            openerCalls++;
            return ReportFileOpenResult(path: name, opened: true);
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ReportingV4Panel(role: 'director')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'XLSX'));
    await tester.pumpAndSettle();

    expect(openerCalls, 0);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('report-export-error')),
      300,
    );
    expect(find.textContaining('повреждённый XLSX-файл'), findsOneWidget);
  });

  testWidgets('reports the saved path when no desktop handler opens the file', (
    tester,
  ) async {
    final api = _ReportingApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
          reportFileOpenerProvider.overrideWithValue((bytes, name) async {
            return ReportFileOpenResult(
              path: 'C:/Reports/$name',
              opened: false,
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ReportingV4Panel(role: 'director')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'XLSX'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('report-export-progress')),
      300,
    );
    expect(
      find.textContaining('Файл сохранён: C:/Reports/client-status-'),
      findsOneWidget,
    );
  });

  testWidgets('loading empty error and forbidden states are explicit', (
    tester,
  ) async {
    final waitingApi = _ReportingApi(wait: true);
    await tester.pumpWidget(_app(waitingApi, role: 'manager'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    waitingApi.release();
    await tester.pumpAndSettle();

    await tester.pumpWidget(_app(_ReportingApi(empty: true), role: 'manager'));
    await tester.pumpAndSettle();
    expect(find.text('За выбранный период клиентов нет'), findsOneWidget);

    await tester.pumpWidget(_app(_ReportingApi(fail: true), role: 'manager'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить раздел'), findsNWidgets(3));

    await tester.pumpWidget(_app(_ReportingApi(), role: 'admin'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reporting-forbidden')), findsOneWidget);
  });

  testWidgets('report surface fits mobile and desktop widths', (tester) async {
    for (final size in const [Size(390, 844), Size(1200, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_app(_ReportingApi(), role: 'manager'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('reporting-content')), findsOneWidget);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('dashboard sections share one normalized filter', (tester) async {
    final api = _ReportingApi();
    final filter = DashboardFilter(
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
      branchId: '11111111-1111-4111-8111-111111111111',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ReportingV4Panel(role: 'director', filter: filter),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final path in const [
      '/analytics/v4/client-status/summary',
      '/analytics/v4/lesson-success',
      '/analytics/v4/school-finance',
    ]) {
      for (final entry in filter.apiFilter.entries) {
        expect(
          api.queries[path],
          containsPair(entry.key, entry.value),
          reason: path,
        );
      }
    }
    expect(api.queries['/crm/shared-tasks'], {'state': 'open', 'limit': 1});
  });

  testWidgets('one failed section keeps the rest of dashboard usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _ReportingApi(failPath: '/analytics/v4/lesson-success'),
        role: 'manager',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Новые'), findsOneWidget);
    expect(find.text('Открыто: 3 · Просрочено: 1'), findsOneWidget);
    expect(find.text('Не удалось загрузить раздел'), findsOneWidget);
  });

  testWidgets('forbidden dashboard roles issue no report requests', (
    tester,
  ) async {
    for (final role in const ['client', 'teacher', 'admin']) {
      final api = _ReportingApi();
      await tester.pumpWidget(_app(api, role: role));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reporting-forbidden')), findsOneWidget);
      expect(api.queries, isEmpty, reason: role);
    }
  });

  testWidgets('capability snapshot removes finance before providers load', (
    tester,
  ) async {
    final api = _ReportingApi();
    final snapshot = CapabilitySnapshot(
      accountId: 'manager-account',
      role: 'manager',
      accessVersion: 4,
      capabilities: const {'report.status.read', 'workflow.task.read'},
      scopes: const {'branch': 'assigned'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ReportingV4Panel(role: 'director', accessSnapshot: snapshot),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('dashboard-finance-section')),
      findsNothing,
    );
    expect(api.queries, isNot(contains('/analytics/v4/school-finance')));
    expect(api.queries, contains('/analytics/v4/client-status/summary'));
  });
}

Widget _app(
  _ReportingApi api, {
  required String role,
  ValueChanged<EntityLink>? onOpenEntity,
}) {
  return ProviderScope(
    overrides: [
      magicCrmServiceProvider.overrideWithValue(MagicCrmService(api)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ReportingV4Panel(
          key: ValueKey(api),
          role: role,
          onOpenEntity: onOpenEntity,
        ),
      ),
    ),
  );
}

class _ReportingApi extends MagicApiClient {
  _ReportingApi({
    this.empty = false,
    this.fail = false,
    this.wait = false,
    this.asyncExport = false,
    this.corruptExport = false,
    this.failPath,
  }) : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final bool empty;
  final bool fail;
  final bool wait;
  final bool asyncExport;
  final bool corruptExport;
  final String? failPath;
  final _gate = Completer<void>();
  Map<String, dynamic>? lastListFilter;
  final Map<String, Map<String, dynamic>> queries = {};
  int jobPolls = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    if (wait) await _gate.future;
    if (fail || path == failPath) {
      throw const MagicApiException(message: 'network', statusCode: 500);
    }
    queries[path] = Map<String, dynamic>.from(queryParameters ?? const {});
    if (path == '/analytics/v4/client-status/summary') {
      return <String, dynamic>{
            'total': empty ? 0 : 2,
            'items': empty
                ? <dynamic>[]
                : [
                    {
                      'clientType': 'lead',
                      'status': 'new',
                      'label': 'Новые',
                      'count': 1,
                      'drilldown': {
                        'entityType': 'client_status_list',
                        'entityId': 'lead:new',
                        'optionalFocus': {
                          'filter': {
                            'version': 1,
                            'clientType': 'lead',
                            'status': 'new',
                          },
                        },
                      },
                    },
                  ],
          }
          as T;
    }
    if (path == '/analytics/v4/client-status/clients') {
      lastListFilter = Map<String, dynamic>.from(queryParameters ?? const {});
      return <String, dynamic>{
            'total': 1,
            'items': [
              {
                'displayName': 'Алина Тестова',
                'statusLabel': 'Новый',
                'entityLink': {
                  'entityType': 'student',
                  'entityId': 'student-1',
                },
              },
            ],
          }
          as T;
    }
    if (path == '/analytics/v4/lesson-success') {
      return <String, dynamic>{
            'totalLessons': empty ? 0 : 10,
            'successfulLessons': empty ? 0 : 8,
            'successRate': empty ? 0 : 0.8,
            'drilldown': {
              'entityType': 'lesson_list',
              'entityId': 'successfully_completed',
              'optionalFocus': {
                'filter': {
                  'version': 1,
                  'status': 'successfully_completed',
                  ...?queryParameters,
                },
              },
            },
          }
          as T;
    }
    if (path == '/analytics/v4/lesson-success/lessons') {
      return <String, dynamic>{
            'total': 8,
            'items': [
              {
                'displayName': 'Урок Алины',
                'subtitle': 'Ирина · Центральный',
                'entityLink': {'entityType': 'lesson', 'entityId': 'lesson-1'},
              },
            ],
          }
          as T;
    }
    if (path == '/analytics/v4/school-finance') {
      return <String, dynamic>{
            'rows': empty
                ? <dynamic>[]
                : [
                    {
                      'monthStart': '2026-07-01',
                      'revenueMinor': '800000',
                      'expensesMinor': '160000',
                      'link': {
                        'entityType': 'school_finance_month',
                        'entityId': '2026-07-01',
                      },
                    },
                  ],
          }
          as T;
    }
    if (path == '/crm/shared-tasks') {
      return <String, dynamic>{
            'items': <dynamic>[],
            'counters': {'open': empty ? 0 : 3, 'overdue': empty ? 0 : 1},
          }
          as T;
    }
    if (path == '/analytics/v4/exports/job-1') {
      jobPolls++;
      return <String, dynamic>{
            'id': 'job-1',
            'status': 'ready',
            'rowCount': 10001,
            'downloadReady': true,
            'filename': 'client-status.xlsx',
          }
          as T;
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<List<int>> postBytes(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (asyncExport) {
      return utf8.encode(
        jsonEncode({
          'mode': 'async',
          'jobId': 'job-1',
          'status': 'queued',
          'rowCount': 10001,
        }),
      );
    }
    if (corruptExport) return utf8.encode('{"not":"xlsx"}');
    return [0x50, 0x4b, 0x03, 0x04];
  }

  @override
  Future<List<int>> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return [0x50, 0x4b, 0x03, 0x04];
  }
}
