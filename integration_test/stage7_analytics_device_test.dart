import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:magic_music_crm/core/api/magic_api_client.dart';
import 'package:magic_music_crm/core/api/magic_api_providers.dart';
import 'package:magic_music_crm/core/api/magic_token_store.dart';
import 'package:magic_music_crm/core/navigation/context_route_state.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/report_export_files.dart';
import 'package:magic_music_crm/features/manager/presentation/reporting/reporting_models.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/reports_widget.dart';

import 'evidence_screenshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ru', null));

  testWidgets('stage 7 analytics IA and capability projection work on device', (
    tester,
  ) async {
    final directorApi = _DeviceApi();
    await tester.pumpWidget(
      _app(directorApi, role: 'director', initialViewState: _fixedFilter),
    );
    await tester.pumpAndSettle();

    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Журналы'), findsOneWidget);
    expect(find.text('XLSX'), findsOneWidget);
    expect(find.text('Финансы XLSX'), findsOneWidget);
    _expectSharedFilter(directorApi, _branchA);

    await tester.tap(find.byKey(const ValueKey('dashboard-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Второй филиал').last);
    await tester.pumpAndSettle();
    _expectSharedFilter(directorApi, _branchB);

    await tester.tap(find.widgetWithText(OutlinedButton, 'XLSX'));
    await tester.pumpAndSettle();
    expect(directorApi.openedReports, hasLength(1));
    final xlsx = directorApi.openedReports[0];
    expect(xlsx.filename, startsWith('client-status-'));
    expect(xlsx.filename, endsWith('.xlsx'));
    expect(xlsx.bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
    await tester.drag(
      find.byKey(const ValueKey('reporting-content')).first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Файл открыт:'), findsOneWidget);
    await captureEvidence(tester, 'director-dashboard-xlsx-export');

    await tester.drag(
      find.byKey(const ValueKey('reporting-content')).first,
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'CSV'));
    await tester.pumpAndSettle();
    expect(directorApi.openedReports, hasLength(2));
    final csv = directorApi.openedReports[1];
    expect(csv.filename, endsWith('.csv'));
    expect(csv.bytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(csv.bytes), contains('Алёна Смирнова'));
    expect(utf8.decode(csv.bytes), contains('Тип;Клиент;Статус;Филиал'));
    expect(directorApi.exports, hasLength(2));
    final expectedFilter = _fixedApiFilter;
    for (final export in directorApi.exports) {
      expect(export['from'], expectedFilter['from']);
      expect(export['to'], expectedFilter['to']);
      expect(export['branchId'], _branchB);
    }
    await captureEvidence(tester, 'director-dashboard-csv-export');

    await tester.tap(find.text('Журналы'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('operational-journals')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final managerApi = _DeviceApi();
    await tester.pumpWidget(
      _app(managerApi, role: 'manager', initialViewState: _fixedFilter),
    );
    await tester.pumpAndSettle();
    expect(managerApi.queries, isNot(contains('/analytics/v4/school-finance')));
    expect(find.text('Финансы XLSX'), findsNothing);
    await tester.tap(find.text('Журналы'));
    await tester.pumpAndSettle();
    expect(find.text('Финансовые операции'), findsNothing);
    await captureEvidence(tester, 'manager-dashboard-without-school-finance');
    expect(tester.takeException(), isNull);
  });
}

final _fixedFilter = ContextViewState(
  filters: const {
    'dashboardFrom': '2026-07-01T00:00:00.000',
    'dashboardTo': '2026-07-31T00:00:00.000',
    'branchId': _branchA,
  },
);

const _branchA = '11111111-1111-4111-8111-111111111111';
const _branchB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> get _fixedApiFilter => DashboardFilter(
  from: DateTime(2026, 7, 1),
  to: DateTime(2026, 7, 31),
  branchId: _branchB,
).apiFilter;

void _expectSharedFilter(_DeviceApi api, String branchId) {
  final expected = DashboardFilter(
    from: DateTime(2026, 7, 1),
    to: DateTime(2026, 7, 31),
    branchId: branchId,
  ).apiFilter;
  for (final path in const [
    '/analytics/v4/client-status/summary',
    '/analytics/v4/lesson-success',
    '/analytics/v4/school-finance',
  ]) {
    expect(api.queries[path], containsPair('branchId', branchId), reason: path);
    expect(
      api.queries[path],
      containsPair('from', expected['from']),
      reason: path,
    );
    expect(api.queries[path], containsPair('to', expected['to']), reason: path);
  }
}

Widget _app(
  _DeviceApi api, {
  required String role,
  ContextViewState? initialViewState,
}) => ProviderScope(
  overrides: [
    magicApiClientProvider.overrideWithValue(api),
    reportFileOpenerProvider.overrideWithValue((bytes, filename) async {
      api.openedReports.add((bytes: List<int>.from(bytes), filename: filename));
      return ReportFileOpenResult(path: 'C:/Reports/$filename', opened: true);
    }),
  ],
  child: RepaintBoundary(
    key: evidenceRootKey,
    child: MaterialApp(
      home: Scaffold(
        body: ReportsWidget(role: role, initialViewState: initialViewState),
      ),
    ),
  ),
);

class _DeviceApi extends MagicApiClient {
  _DeviceApi()
    : super(baseUrl: 'http://localhost', tokenStore: MemoryMagicTokenStore());

  final Map<String, Map<String, dynamic>> queries = {};
  final List<Map<String, dynamic>> exports = [];
  final List<({List<int> bytes, String filename})> openedReports = [];

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    queries[path] = Map<String, dynamic>.from(queryParameters ?? const {});
    if (path == '/crm/branches') {
      return <String, dynamic>{
            'items': [
              {'id': _branchA, 'name': 'Первый филиал'},
              {'id': _branchB, 'name': 'Второй филиал'},
            ],
          }
          as T;
    }
    return <String, dynamic>{
          'items': <dynamic>[],
          'rows': <dynamic>[],
          'monthly': <dynamic>[],
          'summary': <String, dynamic>{},
          'counters': <String, dynamic>{'open': 0, 'overdue': 0},
        }
        as T;
  }

  @override
  Future<List<int>> postBytes(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(path, '/analytics/v4/exports');
    final payload = Map<String, dynamic>.from(data! as Map);
    exports.add(payload);
    if (payload['format'] == 'csv') {
      return utf8.encode(
        '\uFEFFТип;Клиент;Статус;Филиал ID;Создан\r\n'
        'student;Алёна Смирнова;Занимается;$_branchB;2026-07-10\r\n',
      );
    }
    return [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00];
  }
}
