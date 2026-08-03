import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_error.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/entity_link.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reporting_v4_panel.dart';

void main() {
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
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ReportingV4Panel(role: 'director')),
        ),
      ),
    );
    await tester.pumpAndSettle();

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
    expect(find.text('Файл готов'), findsOneWidget);
  });

  testWidgets('loading empty error and forbidden states are explicit', (
    tester,
  ) async {
    final waitingApi = _ReportingApi(wait: true);
    await tester.pumpWidget(_app(waitingApi, role: 'manager'));
    await tester.pump();
    expect(find.byKey(const ValueKey('reporting-loading')), findsOneWidget);
    waitingApi.release();
    await tester.pumpAndSettle();

    await tester.pumpWidget(_app(_ReportingApi(empty: true), role: 'manager'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reporting-empty')), findsOneWidget);

    await tester.pumpWidget(_app(_ReportingApi(fail: true), role: 'manager'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reporting-error')), findsOneWidget);

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
  }) : super(
         baseUrl: 'http://localhost',
         tokenStore: MemoryMagicTokenStore(),
       );

  final bool empty;
  final bool fail;
  final bool wait;
  final bool asyncExport;
  final _gate = Completer<void>();
  Map<String, dynamic>? lastListFilter;
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
    if (fail) {
      throw const MagicApiException(message: 'network', statusCode: 500);
    }
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
                      'count': 2,
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
